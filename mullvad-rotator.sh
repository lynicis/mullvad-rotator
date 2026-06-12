#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

# --- Paths ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
CONFIG_DIR="${HOME}/.config/mullvad-rotator"
CONFIG_FILE="${CONFIG_DIR}/config"
CACHE_FILE="${CONFIG_DIR}/countries.cache"
PID_FILE="/tmp/mullvad-rotator.pid"
CACHE_TTL=3600

# --- Default config values ---
COUNTRIES=""
MODE="random"
INTERVAL=0
ROTATE_KEY=false

# --- Color/ANSI ---
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'
CHECK="✓"

# --- TUI helpers ---
BOX_WIDTH=60

strip_ansi() { printf '%s' "$1" | sed $'s/\e\\[[0-9;]*m//g'; }

draw_box_line() {
    local content="$1" width="${2:-$BOX_WIDTH}"
    local inner=$(( width - 4 ))
    local visible
    visible=$(strip_ansi "$content")
    local pad=$(( inner - ${#visible} ))
    (( pad < 0 )) && pad=0
    printf "│ %s%*s │\n" "$content" "$pad" ""
}

draw_box_top()    { printf "┌"; printf '─%.0s' $(seq 1 $(($BOX_WIDTH - 2))); printf "┐\n"; }
draw_box_bottom() { printf "└"; printf '─%.0s' $(seq 1 $(($BOX_WIDTH - 2))); printf "┘\n"; }
draw_box_sep()    { printf "├"; printf '─%.0s' $(seq 1 $(($BOX_WIDTH - 2))); printf "┤\n"; }
draw_box_line_plain() { printf "─%.0s" $(seq 1 "$BOX_WIDTH"); printf "\n"; }

read_key() {
    KEY=""
    local byte
    IFS= read -rsn1 byte

    if [[ "$byte" == $'\x1b' ]]; then
        if read -t 0; then
            local char1 char2 char3
            read -rsn1 char1
            if [[ "$char1" == "[" ]]; then
                read -rsn1 char2
                if [[ "$char2" =~ ^[0-9]$ ]]; then
                    read -rsn1 char3
                    if [[ "$char3" == "~" ]]; then
                        case "$char2" in
                            5) KEY="pageup" ;;
                            6) KEY="pagedown" ;;
                            *) KEY="unknown" ;;
                        esac
                    else
                        KEY="unknown"
                    fi
                else
                    case "$char2" in
                        A) KEY="up" ;;
                        B) KEY="down" ;;
                        H) KEY="home" ;;
                        F) KEY="end" ;;
                        *) KEY="unknown" ;;
                    esac
                fi
            else
                KEY="unknown"
            fi
        else
            KEY="escape"
        fi
    elif [[ "$byte" == $'\x7f' || "$byte" == $'\x08' ]]; then
        KEY="backspace"
    elif [[ "$byte" == "" ]]; then
        KEY="enter"
    elif [[ "$byte" == " " ]]; then
        KEY="space"
    elif [[ "$byte" =~ ^[[:print:]]$ ]]; then
        KEY="$byte"
    else
        KEY="unknown"
    fi
}

tui_cursor_hide() { printf "\033[?25l"; trap 'printf "\033[?25h"' EXIT; }
tui_cursor_show() { printf "\033[?25h"; trap - EXIT; }

tui_die() { error "$*"; [[ "${TUI_MODE:-false}" == "true" ]] && return 1 || exit 1; }

# --- Utility functions ---
log()    { echo -e "$*" >&2; }
info()   { log "${CYAN}::${NC} $*"; }
success(){ log "${GREEN}::${NC} $*"; }
warn()   { log "${YELLOW}::${NC} $*"; }
error()  { log "${RED}!!${NC} $*"; }
die()    { error "$*"; exit 1; }

confirm() {
    local prompt="$1" default="${2:-y}"
    local suffix
    if [[ "$default" =~ ^[Yy] ]]; then
        suffix="(Y/n)"
    else
        suffix="(y/N)"
    fi
    read -p "$prompt $suffix " ans
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy] ]]
}

# --- OS detection ---
case "$(uname)" in
    Darwin) OS="macos"; STAT_CMD="stat -f %m" ;;
    Linux)  OS="linux";  STAT_CMD="stat -c %Y" ;;
    *)      die "Unsupported OS: $(uname)" ;;
esac

# --- Config management ---
init_config() {
    mkdir -p "$CONFIG_DIR"
    [[ -f "$CONFIG_FILE" ]] && return
    cat > "$CONFIG_FILE" <<-EOF
# Mullvad Rotator Configuration
COUNTRIES=""
MODE="random"
INTERVAL=0
ROTATE_KEY=false
EOF
    info "Created config at $CONFIG_FILE"
}

load_config() {
    init_config
    source "$CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" <<-EOF
# Mullvad Rotator Configuration
COUNTRIES="${COUNTRIES}"
MODE="${MODE}"
INTERVAL=${INTERVAL}
ROTATE_KEY=${ROTATE_KEY}
EOF
}

# --- Relay list parsing and caching ---
refresh_cache() {
    info "Fetching relay list from Mullvad..."
    local output
    output=$(mullvad relay list 2>/dev/null) || die "Failed to get relay list.\nIs Mullvad CLI installed and daemon running?"

    # Parse: lines starting with uppercase = country entries
    # Format: "Country Name (cc)"
    echo "$output" | while IFS= read -r line; do
        if [[ "$line" =~ ^[[:upper:]] ]]; then
            # Trim leading/trailing whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            if [[ "$line" =~ ^(.+)[[:space:]]+\(([a-z]{2})\)$ ]]; then
                name="${BASH_REMATCH[1]}"
                code="${BASH_REMATCH[2]}"
                echo "${code}|${name}"
            fi
        fi
    done > "$CACHE_FILE"

    if [[ ! -s "$CACHE_FILE" ]]; then
        die "Failed to parse relay list. Unexpected format."
    fi

    local count
    count=$(wc -l < "$CACHE_FILE" | tr -d ' ')
    success "Found ${count} countries"
}

get_cached_countries() {
    if [[ -f "$CACHE_FILE" ]]; then
        local mtime=0 now
        now=$(date +%s)
        mtime=$($STAT_CMD "$CACHE_FILE" 2>/dev/null || echo 0)
        if (( (now - mtime) < CACHE_TTL )); then
            cat "$CACHE_FILE"
            return
        fi
    fi
    refresh_cache
    cat "$CACHE_FILE"
}

load_country_arrays() {
    countries_codes=()
    countries_names=()
    while IFS='|' read -r code name; do
        countries_codes+=("$code")
        countries_names+=("$name")
    done < <(get_cached_countries)
    selected=()
    for ((i=0; i<${#countries_codes[@]}; i++)); do
        selected+=("0")
    done
}

# --- Connection status functions ---
get_status_json() {
    mullvad status --json 2>/dev/null || echo '{"state":"error"}'
}

get_status_summary() {
    local json
    json=$(get_status_json)

    state=$(echo "$json" | grep '"state"' | sed 's/.*"state":[[:space:]]*"\([^"]*\)".*/\1/')
    hostname=$(echo "$json" | grep '"hostname"' | sed 's/.*"hostname":[[:space:]]*"\([^"]*\)".*/\1/')
    country=$(echo "$json" | grep '"country"' | sed 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/')
    city=$(echo "$json" | grep '"city"' | sed 's/.*"city":[[:space:]]*"\([^"]*\)".*/\1/')
    ipv4=$(echo "$json" | grep '"ipv4"' | sed 's/.*"ipv4":[[:space:]]*"\([^"]*\)".*/\1/')

    state="${state:-unknown}"
    hostname="${hostname:--}"
    country="${country:--}"
    city="${city:--}"
    ipv4="${ipv4:--}"
}

print_status_line() {
    get_status_summary
    if [[ "$state" == "connected" ]]; then
        printf "${GREEN}%-12s${NC} %s | %s, %s | %s\n" "$state" "$hostname" "$city" "$country" "$ipv4"
    else
        printf "${YELLOW}%-12s${NC} %s\n" "$state" "$hostname"
    fi
}

# --- Main TUI menu ---
show_main_menu() {
    TUI_MODE=true
    local menu_cursor=0
    local menu_items=(
        "Rotate connection"
        "Rotate WireGuard key"
        "Select countries"
        "Show available countries"
        "View detailed status"
        "Set rotation interval"
        "Install/remove daemon service"
        "Exit"
    )
    
    tui_cursor_hide

    while true; do
        clear
        draw_box_top
        draw_box_line "${BOLD}Mullvad Rotator v${VERSION}${NC}"
        draw_box_sep
        get_status_summary
        local status_str
        if [[ "$state" == "connected" ]]; then
            status_str="Status: ${GREEN}${state}${NC}"
        else
            status_str="Status: ${YELLOW}${state}${NC}"
        fi
        draw_box_line "$status_str"
        draw_box_line "Relay: ${hostname}"
        draw_box_line "Location: ${country}/${city}"
        
        local interval_str="manual"
        (( INTERVAL > 0 )) && interval_str="${INTERVAL}m"
        draw_box_line "Mode: ${MODE} | Interval: ${interval_str}"
        draw_box_sep

        for ((i=0; i<8; i++)); do
            local num=$((i+1))
            if (( i == menu_cursor )); then
                draw_box_line "${BOLD}${GREEN}> ${num}) ${menu_items[$i]}${NC}"
            else
                draw_box_line "  ${num}) ${menu_items[$i]}"
            fi
        done

        draw_box_sep
        draw_box_line "↑↓ Navigate  Enter Select"
        draw_box_bottom
        echo ""

        read_key

        local action=0
        case "$KEY" in
            up)
                menu_cursor=$(( (menu_cursor - 1 + 8) % 8 ))
                ;;
            down)
                menu_cursor=$(( (menu_cursor + 1) % 8 ))
                ;;
            enter)
                action=$(( menu_cursor + 1 ))
                ;;
            1|2|3|4|5|6|7|8)
                action="$KEY"
                ;;
            *)
                ;;
        esac

        if (( action > 0 )); then
            tui_cursor_show
            case "$action" in
                1) rotate_connection; press_enter ;;
                2) rotate_wireguard_key; press_enter ;;
                3) select_countries_tui; press_enter ;;
                4) show_country_list; press_enter ;;
                5) show_detailed_status; press_enter ;;
                6) set_rotation_interval; press_enter ;;
                7) daemon_menu ;;
                8)
                    if confirm "Exit?" "n"; then
                        exit 0
                    fi
                    ;;
            esac
            tui_cursor_hide
        fi
    done
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

# --- Country TUI selection ---
select_countries_tui() {
    load_country_arrays

    # Pre-load existing selection
    if [[ -n "$COUNTRIES" ]]; then
        IFS=' ' read -ra selected_codes <<< "$COUNTRIES"
        for code in "${selected_codes[@]}"; do
            for ((i=0; i<${#countries_codes[@]}; i++)); do
                if [[ "${countries_codes[$i]}" == "$code" ]]; then
                    selected[$i]=1
                fi
            done
        done
    fi

    local cursor=0
    local scroll_offset=0
    local window_size=15
    local total=${#countries_codes[@]}
    local filter_query=""

    # Hide cursor
    tui_cursor_hide

    while true; do
        # Build filtered list of indices
        local filtered_indices=()
        for ((i=0; i<total; i++)); do
            if [[ -z "$filter_query" ]]; then
                filtered_indices+=("$i")
            else
                # Case-insensitive substring match
                local name_lower
                name_lower=$(echo "${countries_names[$i]}" | tr '[:upper:]' '[:lower:]')
                local code_lower
                code_lower=$(echo "${countries_codes[$i]}" | tr '[:upper:]' '[:lower:]')
                local query_lower
                query_lower=$(echo "$filter_query" | tr '[:upper:]' '[:lower:]')
                if [[ "$name_lower" == *"$query_lower"* || "$code_lower" == *"$query_lower"* ]]; then
                    filtered_indices+=("$i")
                fi
            fi
        done

        local filtered_total=${#filtered_indices[@]}

        # Adjust cursor if it exceeds filtered bounds
        if (( cursor >= filtered_total )); then
            cursor=$(( filtered_total > 0 ? filtered_total - 1 : 0 ))
        fi
        if (( cursor < 0 )); then
            cursor=0
        fi

        # Adjust scroll offset
        if (( cursor < scroll_offset )); then
            scroll_offset=$cursor
        elif (( cursor >= scroll_offset + window_size )); then
            scroll_offset=$(( cursor - window_size + 1 ))
        fi
        if (( scroll_offset < 0 )); then
            scroll_offset=0
        fi

        clear
        draw_box_top
        draw_box_line "Select Countries (↑↓/Space/Enter)"
        draw_box_line "Type to search. Backspace to delete."
        draw_box_line "Esc: clear/exit. 'a': All, 'n': None."
        draw_box_bottom
        if [[ -n "$filter_query" ]]; then
            printf "${YELLOW}Search: %-48s${NC}\n" "$filter_query"
        else
            printf "${DIM}Search: Type to filter... (e.g. 'se' or 'sweden')${NC}\n"
        fi
        draw_box_line_plain

        if (( filtered_total == 0 )); then
            echo "  [No matching countries found]"
        else
            # Print visible window
            for ((w=scroll_offset; w<scroll_offset+window_size && w<filtered_total; w++)); do
                local i=${filtered_indices[$w]}
                local mark=" "
                [[ "${selected[$i]}" == "1" ]] && mark="${CHECK}"
                
                if (( w == cursor )); then
                    printf "${BOLD}${GREEN}> [%s] %-25s (%s)${NC}\n" "$mark" "${countries_names[$i]}" "${countries_codes[$i]}"
                else
                    printf "  [%s] %-25s (%s)\n" "$mark" "${countries_names[$i]}" "${countries_codes[$i]}"
                fi
            done
        fi

        draw_box_line_plain
        local sel_count=0
        for s in "${selected[@]}"; do
            [[ "$s" == "1" ]] && (( sel_count++ ))
        done
        printf "Viewing %d/%d countries | Selected: %d | PgUp/PgDn\n" "$filtered_total" "$total" "$sel_count"

        # Read key press
        read_key

        case "$KEY" in
            up)
                (( cursor > 0 )) && (( cursor-- ))
                ;;
            down)
                (( cursor < filtered_total - 1 )) && (( cursor++ ))
                ;;
            pageup)
                cursor=$(( cursor - window_size ))
                (( cursor < 0 )) && cursor=0
                ;;
            pagedown)
                cursor=$(( cursor + window_size ))
                (( cursor >= filtered_total )) && cursor=$(( filtered_total - 1 ))
                (( cursor < 0 )) && cursor=0
                ;;
            home)
                cursor=0
                ;;
            end)
                cursor=$(( filtered_total - 1 ))
                (( cursor < 0 )) && cursor=0
                ;;
            space)
                if (( filtered_total > 0 )); then
                    local idx=${filtered_indices[$cursor]}
                    selected[$idx]=$(( 1 - selected[$idx] ))
                fi
                ;;
            enter)
                break
                ;;
            escape)
                if [[ -n "$filter_query" ]]; then
                    filter_query=""
                    cursor=0
                else
                    tui_cursor_show
                    return
                fi
                ;;
            backspace)
                if [[ -n "$filter_query" ]]; then
                    filter_query="${filter_query%?}"
                    cursor=0
                fi
                ;;
            a|A)
                if [[ -z "$filter_query" ]]; then
                    for idx in "${filtered_indices[@]}"; do
                        selected[$idx]=1
                    done
                else
                    filter_query+="$KEY"
                    cursor=0
                fi
                ;;
            n|N)
                if [[ -z "$filter_query" ]]; then
                    for idx in "${filtered_indices[@]}"; do
                        selected[$idx]=0
                    done
                else
                    filter_query+="$KEY"
                    cursor=0
                fi
                ;;
            *)
                if [[ ${#KEY} -eq 1 ]]; then
                    filter_query+="$KEY"
                    cursor=0
                fi
                ;;
        esac
    done

    # Restore cursor
    tui_cursor_show

    # Save selection
    COUNTRIES=""
    local first=true
    for ((i=0; i<total; i++)); do
        if [[ "${selected[$i]}" == "1" ]]; then
            if $first; then
                COUNTRIES="${countries_codes[$i]}"
                first=false
            else
                COUNTRIES+=" ${countries_codes[$i]}"
            fi
        fi
    done

    if [[ -z "$COUNTRIES" ]]; then
        MODE="random"
        info "No countries selected, using random mode."
    else
        MODE="selection"
        local count
        count=$(echo "$COUNTRIES" | wc -w | tr -d ' ')
        success "Selected ${count} country/ies"
    fi
    save_config
}

show_country_list() {
    load_country_arrays
    clear
    echo "Available countries:"
    echo ""
    for ((i=0; i<${#countries_codes[@]}; i++)); do
        printf "  %3d) %s (%s)\n" $((i+1)) "${countries_names[$i]}" "${countries_codes[$i]}"
    done
    echo ""
    echo "Total: ${#countries_codes[@]} countries"
}

# --- Core rotation functions ---
pick_random_country() {
    if [[ "$MODE" == "random" ]]; then
        load_country_arrays
        local total=${#countries_codes[@]}
        local idx=$((RANDOM % total))
        echo "${countries_codes[$idx]}"
    else
        # Pick from selected countries
        IFS=' ' read -ra codes <<< "$COUNTRIES"
        [[ ${#codes[@]} -eq 0 ]] && { load_country_arrays; idx=$((RANDOM % ${#countries_codes[@]})); echo "${countries_codes[$idx]}"; return; }
        local idx=$((RANDOM % ${#codes[@]}))
        echo "${codes[$idx]}"
    fi
}

rotate_connection() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true

    local target_country
    target_country=$(pick_random_country)
    local country_name
    country_name=$(get_cached_countries | grep "^${target_country}|" | cut -d'|' -f2)
    country_name="${country_name:-$target_country}"

    info "Rotating to: ${country_name} (${target_country})"
    $dry_run && { info "[DRY RUN] Would set location: ${target_country}"; return; }

    get_status_summary

    if [[ "$state" != "connected" ]]; then
        info "Not connected. Connecting..."
        mullvad relay set location "$target_country" || tui_die "Failed to set location"
        mullvad connect --wait || tui_die "Failed to connect"
    else
        mullvad relay set location "$target_country" || tui_die "Failed to set location"

        local should_reconnect=true
        if [[ "${TUI_MODE:-false}" == "true" ]]; then
            confirm "Reconnect now?" || should_reconnect=false
        fi

        if $should_reconnect; then
            info "Reconnecting..."
            mullvad reconnect --wait 2>/dev/null || {
                warn "Reconnect failed, trying fresh connect..."
                mullvad disconnect 2>/dev/null
                sleep 1
                mullvad connect --wait 2>/dev/null || tui_die "Failed to connect"
            }
        fi
    fi

    sleep 1
    get_status_summary
    if [[ "$state" == "connected" ]]; then
        success "Connected to ${hostname} (${city}, ${country})"
    else
        warn "State: ${state}"
    fi
}

rotate_wireguard_key() {
    info "Rotating WireGuard key..."
    if ! confirm "This will immediately invalidate the current key. Continue?" "n"; then
        info "Cancelled."
        return
    fi

    mullvad tunnel set rotate-key 2>/dev/null || tui_die "Failed to rotate key"

    if confirm "Reconnect with new key?"; then
        mullvad reconnect --wait 2>/dev/null || {
            warn "Reconnect failed"
            mullvad connect --wait 2>/dev/null
        }
        get_status_summary
        success "Key rotated and reconnected via ${hostname}"
    else
        success "Key rotated. Reconnect manually when ready."
    fi
}

show_detailed_status() {
    clear
    draw_box_top
    draw_box_line "Mullvad Connection Status"
    draw_box_sep

    get_status_summary
    draw_box_line "State:     $state"
    draw_box_line "Relay:     ${hostname:--}"
    draw_box_line "Location:  ${city}/${country}"
    draw_box_line "IPv4:      ${ipv4:--}"

    # Show current relay constraints
    draw_box_sep
    local relay_config
    relay_config=$(mullvad relay get 2>/dev/null || echo "unavailable")
    while IFS= read -r line; do
        # trim leading space
        line="${line#"${line%%[![:space:]]*}"}"
        draw_box_line "$line"
    done <<< "$relay_config"

    # Show tunnel info
    draw_box_sep
    local tunnel_info
    tunnel_info=$(mullvad tunnel get 2>/dev/null || echo "unavailable")
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        draw_box_line "$line"
    done <<< "$tunnel_info"

    draw_box_bottom
}

# --- Daemon and interval management ---
set_rotation_interval() {
    echo ""
    echo "Current interval: ${INTERVAL} minutes (0 = manual only)"
    echo ""
    read -p "New interval in minutes (0 = manual only): " new_interval
    new_interval="${new_interval:-$INTERVAL}"
    [[ "$new_interval" =~ ^[0-9]+$ ]] || { warn "Invalid number"; return; }
    INTERVAL=$new_interval
    save_config

    if (( INTERVAL > 0 )); then
        success "Interval set to ${INTERVAL} minutes"
        if confirm "Install daemon service to run automatically?"; then
            daemon_service_install
        fi
    else
        info "Manual mode. Use 'Rotate connection' from menu."
        local has_daemon=false
        if [[ "$OS" == "macos" ]]; then
            [[ -f "${HOME}/Library/LaunchAgents/com.user.mullvad-rotator.plist" ]] && has_daemon=true
        elif [[ "$OS" == "linux" ]]; then
            [[ -f "${HOME}/.config/systemd/user/mullvad-rotator.timer" ]] && has_daemon=true
        fi
        if $has_daemon; then
            if confirm "Daemon service is installed. Remove it now?" "y"; then
                daemon_service_remove
            fi
        fi
    fi
}

daemon_service_install() {
    clear
    info "Installing Mullvad Rotator daemon..."

    if [[ "$OS" == "macos" ]]; then
        local plist_dir="${HOME}/Library/LaunchAgents"
        local plist="${plist_dir}/com.user.mullvad-rotator.plist"
        mkdir -p "$plist_dir"

        local interval_secs=$((INTERVAL * 60))
        (( interval_secs < 60 )) && interval_secs=1800  # default 30min

        cat > "$plist" <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.mullvad-rotator</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_PATH}</string>
        <string>daemon</string>
    </array>
    <key>StartInterval</key>
    <integer>${interval_secs}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/daemon.log</string>
</dict>
</plist>
EOF

        launchctl load "$plist" 2>/dev/null && \
            success "Daemon installed and loaded (every ${INTERVAL} min)" || \
            warn "Created plist but launchctl load failed. Try: launchctl load ${plist}"

    elif [[ "$OS" == "linux" ]]; then
        local unit_dir="${HOME}/.config/systemd/user"
        mkdir -p "$unit_dir"

        cat > "${unit_dir}/mullvad-rotator.service" <<-EOF
[Unit]
Description=Mullvad Rotator
After=network.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} daemon
EOF

        cat > "${unit_dir}/mullvad-rotator.timer" <<-EOF
[Unit]
Description=Rotate Mullvad VPN connection periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=${INTERVAL}min

[Install]
WantedBy=timers.target
EOF

        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable --now mullvad-rotator.timer 2>/dev/null && \
            success "Daemon installed (every ${INTERVAL} min)" || \
            warn "Created service files but systemctl failed. Check manually."
    fi
}

daemon_service_remove() {
    if [[ "$OS" == "macos" ]]; then
        local plist="${HOME}/Library/LaunchAgents/com.user.mullvad-rotator.plist"
        if [[ -f "$plist" ]]; then
            launchctl unload "$plist" 2>/dev/null || true
            rm "$plist"
            success "Daemon removed"
        else
            info "No daemon installed"
        fi
    elif [[ "$OS" == "linux" ]]; then
        local unit_dir="${HOME}/.config/systemd/user"
        systemctl --user disable --now mullvad-rotator.timer 2>/dev/null || true
        rm -f "${unit_dir}/mullvad-rotator.service" "${unit_dir}/mullvad-rotator.timer"
        systemctl --user daemon-reload 2>/dev/null || true
        success "Daemon removed"
    fi
}

daemon_menu() {
    local d_cursor=0
    local d_items=(
        "Install daemon"
        "Remove daemon"
        "Back"
    )

    tui_cursor_hide

    while true; do
        clear
        draw_box_top
        draw_box_line "Daemon Service"
        draw_box_sep

        for ((i=0; i<3; i++)); do
            local num=$((i+1))
            if (( i == d_cursor )); then
                draw_box_line "${BOLD}${GREEN}> ${num}) ${d_items[$i]}${NC}"
            else
                draw_box_line "  ${num}) ${d_items[$i]}"
            fi
        done

        draw_box_sep
        draw_box_line "↑↓ Navigate  Enter Select"
        draw_box_bottom
        echo ""

        read_key

        local action=0
        case "$KEY" in
            up)
                d_cursor=$(( (d_cursor - 1 + 3) % 3 ))
                ;;
            down)
                d_cursor=$(( (d_cursor + 1) % 3 ))
                ;;
            enter)
                action=$(( d_cursor + 1 ))
                ;;
            1|2|3)
                action="$KEY"
                ;;
            escape)
                action=3
                ;;
        esac

        if (( action > 0 )); then
            tui_cursor_show
            case "$action" in
                1) daemon_service_install; press_enter ;;
                2) daemon_service_remove; press_enter ;;
                3) return ;;
            esac
            tui_cursor_hide
        fi
    done
}

daemon_mode() {
    load_config
    rotate_connection
    if [[ "$ROTATE_KEY" == "true" ]]; then
        mullvad tunnel set rotate-key 2>/dev/null || warn "Key rotation failed"
    fi
}

daemon_setup() {
    load_config
    INTERVAL="${INTERVAL:-30}"
    save_config
    daemon_service_install
}

# --- CLI argument parsing and main entry point ---
main() {
    load_config

    case "${1:-}" in
        rotate|--rotate)
            load_country_arrays
            rotate_connection "${@:2}"
            ;;
        rotate-key|--rotate-key)
            rotate_wireguard_key
            ;;
        status|--status)
            show_detailed_status
            ;;
        daemon)
            daemon_mode
            ;;
        daemon-setup)
            daemon_setup
            ;;
        --version|-v)
            echo "mullvad-rotator v${VERSION}"
            exit 0
            ;;
        --help|-h)
            show_help
            ;;
        ""|menu|--menu)
            show_main_menu
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    cat <<-EOF
Mullvad Rotator v${VERSION}

Usage:
  $(basename "$0")           Interactive TUI menu
  $(basename "$0") rotate    Rotate to a random country (supports --dry-run)
  $(basename "$0") rotate-key  Rotate WireGuard key
  $(basename "$0") status    Show detailed status
  $(basename "$0") daemon    Run one rotation cycle (for daemon service)
  $(basename "$0") daemon-setup Setup and install daemon service
  $(basename "$0") --help    Show this help

Config: ~/.config/mullvad-rotator/config
EOF
}

main "$@"







