# Mullvad Rotator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A pure-bash TUI script that lets users manage Mullvad VPN connection rotation — select countries, rotate relays, rotate WireGuard keys, and run as a daemon.

**Architecture:** Single `mullvad-rotator.sh` bash script with sourced config file. Parses `mullvad relay list` text output to build country menus. Uses bash `select`/`read` for TUI. Daemon mode generated via launchd plist (macOS) or systemd service (Linux). Zero external dependencies — only the `mullvad` CLI and built-in bash commands.

**Tech Stack:** bash (>=3.2, macOS default), Mullvad CLI, launchd (macOS), systemd (Linux)

**Project Root:** `/Users/lynicis/Projects/mullvad-rotator`

---

### Task 1: Project scaffold and config management

**Files:**
- Create: `mullvad-rotator.sh`
- Create: `~/.config/mullvad-rotator/config` (auto-created on first run)

**Step 1: Write the script skeleton**

Create `mullvad-rotator.sh` with:

```bash
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
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
CHECK="✓"
CROSS="✗"

# --- OS detection ---
case "$(uname)" in
    Darwin) OS="macos"; STAT_CMD="stat -f %m" ;;
    Linux)  OS="linux";  STAT_CMD="stat -c %Y" ;;
    *)      die "Unsupported OS: $(uname)" ;;
esac
```

**Step 2: Add utility functions**

```bash
log()    { echo -e "$*" >&2; }
info()   { log "${CYAN}::${NC} $*"; }
success(){ log "${GREEN}::${NC} $*"; }
warn()   { log "${YELLOW}::${NC} $*"; }
error()  { log "${RED}!!${NC} $*"; }
die()    { error "$*"; exit 1; }

confirm() {
    local prompt="$1" default="${2:-y}"
    read -p "$prompt (Y/n) " ans
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy] ]]
}
```

**Step 3: Add config management functions**

```bash
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
```

---

### Task 2: Relay list parsing and caching

**Files:**
- Modify: `mullvad-rotator.sh` (add parsing functions)

**Step 1: Add `refresh_cache()`**

Parses `mullvad relay list` text output. Country lines match `^[A-Z]` and the format `Country Name (cc)`. Extracts the two-letter code and full name.

```bash
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
```

**Step 2: Add `get_cached_countries()`**

Returns cached data if fresh (< CACHE_TTL), otherwise refreshes.

```bash
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
```

**Step 3: Add `load_country_arrays()`**

Populates global arrays from cache. Called before any country TUI display.

```bash
# Called before showing country selector
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
```

---

### Task 3: Connection status functions

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `get_status_json()`**

Wraps `mullvad status --json` with error handling.

```bash
get_status_json() {
    mullvad status --json 2>/dev/null || echo '{"state":"error"}'
}
```

**Step 2: `get_status_summary()`**

Extracts key info into global variables. Parses JSON with `grep`/`sed` (no jq dependency).

```bash
get_status_summary() {
    local json
    json=$(get_status_json)

    state=$(echo "$json" | grep '"state"' | sed 's/.*"state":[[:space:]]*"\(.*\)".*/\1/')
    hostname=$(echo "$json" | grep '"hostname"' | sed 's/.*"hostname":[[:space:]]*"\(.*\)".*/\1/')
    country=$(echo "$json" | grep '"country"' | sed 's/.*"country":[[:space:]]*"\(.*\)".*/\1/')
    city=$(echo "$json" | grep '"city"' | sed 's/.*"city":[[:space:]]*"\(.*\)".*/\1/')
    ipv4=$(echo "$json" | grep '"ipv4"' | sed 's/.*"ipv4":[[:space:]]*"\(.*\)".*/\1/')

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
```

---

### Task 4: Main TUI menu

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `show_main_menu()`**

Renders the main menu header and status, then dispatches.

```bash
show_main_menu() {
    local choice

    while true; do
        clear
        echo "┌────────────────────────────────────────────────┐"
        printf "│ ${BOLD}Mullvad Rotator v${VERSION}${NC}                      │\n"
        echo "├────────────────────────────────────────────────┤"
        printf "│  Status: "
        get_status_summary
        if [[ "$state" == "connected" ]]; then
            printf "${GREEN}%-8s${NC}" "$state"
        else
            printf "${YELLOW}%-8s${NC}" "$state"
        fi
        printf "                         │\n"
        printf "│  Relay: ${hostname}                              │\n"
        printf "│  Location: ${country}/${city}                          │\n"
        echo "├────────────────────────────────────────────────┤"
        echo "│                                                │"
        echo "│  1) Rotate connection                          │"
        echo "│  2) Rotate WireGuard key                       │"
        echo "│  3) Select countries                           │"
        echo "│  4) Show available countries                   │"
        echo "│  5) View detailed status                       │"
        echo "│  6) Set rotation interval                      │"
        echo "│  7) Install/remove daemon service              │"
        echo "│  8) Exit                                       │"
        echo "│                                                │"
        echo "└────────────────────────────────────────────────┘"
        echo ""
        read -p "Choose [1-8]: " choice

        case "$choice" in
            1) rotate_connection; press_enter ;;
            2) rotate_wireguard_key; press_enter ;;
            3) select_countries_tui; press_enter ;;
            4) show_country_list; press_enter ;;
            5) show_detailed_status; press_enter ;;
            6) set_rotation_interval; press_enter ;;
            7) daemon_menu; press_enter ;;
            8) exit 0 ;;
            *)  ;;
        esac
    done
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}
```

---

### Task 5: Country multi-select TUI

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `select_countries_tui()`**

Renders a numbered checklist. Tracks selection state in `selected[]` array. Accepts:
- `<num>` — toggle item
- `<from>-<to>` — toggle range
- `a` — select all
- `n` — select none
- `q` — cancel / back
- `<enter>` — confirm and save

```bash
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

    local input
    while true; do
        clear
        echo "Select countries — toggle by number, then confirm:"
        echo ""

        for ((i=0; i<${#countries_codes[@]}; i++)); do
            local idx=$((i + 1))
            local mark=" "
            [[ "${selected[$i]}" == "1" ]] && mark="${CHECK}"
            printf "%3d) [%s] %-25s (%s)\n" "$idx" "$mark" "${countries_names[$i]}" "${countries_codes[$i]}"
        done

        echo ""
        echo "Commands: <num> = toggle | <from-to> = toggle range | a = all | n = none | q = back | <enter> = confirm"
        echo -n "> "
        read -r input

        [[ -z "$input" ]] && break
        [[ "$input" == "q" ]] && return
        [[ "$input" == "a" ]] && { for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=1; done; continue; }
        [[ "$input" == "n" ]] && { for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=0; done; continue; }

        # Parse numbers/ranges: "1,3-5,7"
        local IFS=','
        for part in $input; do
            part="${part// /}"
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                for ((j=BASH_REMATCH[1]; j<=BASH_REMATCH[2]; j++)); do
                    local idx=$((j - 1))
                    (( idx >= 0 && idx < ${#selected[@]} )) && selected[$idx]=$(( 1 - selected[$idx] ))
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                local idx=$((part - 1))
                (( idx >= 0 && idx < ${#selected[@]} )) && selected[$idx]=$(( 1 - selected[$idx] ))
            fi
        done
    done

    # Save selection
    COUNTRIES=""
    local first=true
    for ((i=0; i<${#selected[@]}; i++)); do
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
```

**Step 2: `show_country_list()`**

Simple paginated list of parsed countries.

```bash
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
```

---

### Task 6: Core rotation functions

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `pick_random_country()`**

Selects a random country from the user's list (selection mode) or all countries (random mode).

```bash
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
```

**Step 2: `rotate_connection()`**

Sets the relay location and reconnects. Accepts `--dry-run` flag.

```bash
rotate_connection() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true

    local country
    country=$(pick_random_country)
    local country_name
    country_name=$(get_cached_countries | grep "^${country}|" | cut -d'|' -f2)
    country_name="${country_name:-$country}"

    info "Rotating to: ${country_name} (${country})"
    $dry_run && { info "[DRY RUN] Would set location: ${country}"; return; }

    if [[ "$state" != "connected" ]]; then
        info "Not connected. Connecting..."
        mullvad relay set location "$country" 2>/dev/null || die "Failed to set location"
        mullvad connect --wait 2>/dev/null || die "Failed to connect"
    else
        mullvad relay set location "$country" 2>/dev/null || die "Failed to set location"

        if confirm "Reconnect now?"; then
            info "Reconnecting..."
            mullvad reconnect --wait 2>/dev/null || {
                warn "Reconnect failed, trying fresh connect..."
                mullvad disconnect 2>/dev/null
                sleep 1
                mullvad connect --wait 2>/dev/null || die "Failed to connect"
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
```

**Step 3: `rotate_wireguard_key()`**

Rotates the WireGuard key and optionally reconnects.

```bash
rotate_wireguard_key() {
    info "Rotating WireGuard key..."
    if ! confirm "This will immediately invalidate the current key. Continue?"; then
        info "Cancelled."
        return
    fi

    mullvad tunnel set rotate-key 2>/dev/null || die "Failed to rotate key"

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
```

**Step 5: `show_detailed_status()`**

Rich formatted status display.

```bash
show_detailed_status() {
    clear
    echo "┌───────────────────────────────────────────┐"
    echo "│         Mullvad Connection Status         │"
    echo "├───────────────────────────────────────────┤"

    get_status_summary
    printf "│ State:     %-30s │\n" "$state"
    printf "│ Relay:     %-30s │\n" "${hostname:--}"
    printf "│ Location:  %-30s │\n" "${city}/${country}"
    printf "│ IPv4:      %-30s │\n" "${ipv4:--}"

    # Show current relay constraints
    echo "├───────────────────────────────────────────┤"
    local relay_config
    relay_config=$(mullvad relay get 2>/dev/null || echo "unavailable")
    while IFS= read -r line; do
        # trim leading space
        line="${line#"${line%%[![:space:]]*}"}"
        printf "│ %-41s │\n" "$line"
    done <<< "$relay_config"

    # Show tunnel info
    echo "├───────────────────────────────────────────┤"
    local tunnel_info
    tunnel_info=$(mullvad tunnel get 2>/dev/null || echo "unavailable")
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        printf "│ %-41s │\n" "$line"
    done <<< "$tunnel_info"

    echo "└───────────────────────────────────────────┘"
}
```

---

### Task 7: Rotation interval and daemon service

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `set_rotation_interval()`**

Prompts and saves interval. Offers daemon install if > 0.

```bash
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
    fi
}
```

**Step 2: `daemon_service_install()`**

Creates platform-specific service file (launchd on macOS, systemd on Linux).

```bash
daemon_service_install() {
    clear
    echo "Installing Mullvad Rotator daemon..."

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
```

**Step 3: `daemon_service_remove()`**

Removes the platform service file.

```bash
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
    clear
    echo "Daemon Service"
    echo ""
    echo "1) Install daemon"
    echo "2) Remove daemon"
    echo "3) Back"
    echo ""
    read -p "Choose [1-3]: " d_choice
    case "$d_choice" in
        1) daemon_service_install ;;
        2) daemon_service_remove ;;
        *) return ;;
    esac
}
```

**Step 4: `daemon_mode()`**

Runs one rotation cycle. Called by launchd/systemd timer.

```bash
daemon_mode() {
    load_config
    rotate_connection
    if [[ "$ROTATE_KEY" == "true" ]]; then
        mullvad tunnel set rotate-key 2>/dev/null || warn "Key rotation failed"
    fi
}
```

---

### Task 8: CLI argument parsing and main entry point

**Files:**
- Modify: `mullvad-rotator.sh`

**Step 1: `main()`**

Parses CLI args and dispatches.

```bash
main() {
    load_config

    case "${1:-}" in
        rotate|--rotate)
            load_country_arrays
            rotate_connection
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
        install)
            install_script
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
  $(basename "$0") rotate    Rotate to a random country
  $(basename "$0") rotate-key  Rotate WireGuard key
  $(basename "$0") status    Show detailed status
  $(basename "$0") daemon    Run one rotation cycle (for daemon service)
  $(basename "$0") --help    Show this help

Config: ~/.config/mullvad-rotator/config
EOF
}

main "$@"
```

---

### Task 9: Install helper script

**Files:**
- Create: `install.sh`

A simple script that symlinks `mullvad-rotator.sh` into `~/.local/bin/` and offers daemon setup.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/mullvad-rotator.sh"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/mullvad-rotator"

echo "Installing Mullvad Rotator..."
echo ""

# Check script exists
[[ -f "$SCRIPT" ]] || { echo "Error: mullvad-rotator.sh not found in $SCRIPT_DIR"; exit 1; }

# Create bin dir
mkdir -p "$BIN_DIR"

# Create symlink
ln -sf "$SCRIPT" "$BIN"
chmod +x "$SCRIPT"

echo "  ✓ Symlinked: ${BIN} -> ${SCRIPT}"

# Path check
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠  ${BIN_DIR} is not in your PATH."
    echo "     Add this to your ~/.bashrc or ~/.zshrc:"
    echo "       export PATH=\"\${HOME}/.local/bin:\${PATH}\""
fi

# Mullvad check
if ! command -v mullvad &>/dev/null; then
    echo ""
    echo "  ⚠  Mullvad CLI not found in PATH."
    echo "     Install Mullvad VPN first: https://mullvad.net/download"
fi

echo ""
echo "Installation complete."
echo "Run: mullvad-rotator"

# Daemon prompt
read -p "Install daemon service for auto-rotation? (y/N): " daemon_choice
if [[ "$daemon_choice" =~ ^[Yy] ]]; then
    read -p "Rotation interval in minutes [30]: " interval
    interval="${interval:-30}"
    export INTERVAL="$interval"
    "$SCRIPT" daemon-setup 2>/dev/null || {
        echo "Use the TUI menu to configure daemon: mullvad-rotator"
    }
fi
```

Add a `daemon-setup` subcommand to the main script (called by install.sh):

```bash
daemon_setup() {
    load_config
    INTERVAL="${INTERVAL:-30}"
    save_config
    daemon_service_install
}
```

Add to `main()`:
```bash
daemon-setup)
    daemon_setup
    ;;
```

---

## Task List Summary

| # | Task | Files | Est. Time |
|---|---|---|---|
| 1 | Project scaffold + config | `mullvad-rotator.sh` | 5 min |
| 2 | Relay parsing + caching | `mullvad-rotator.sh` | 5 min |
| 3 | Status functions | `mullvad-rotator.sh` | 5 min |
| 4 | Main TUI menu | `mullvad-rotator.sh` | 5 min |
| 5 | Country multi-select TUI | `mullvad-rotator.sh` | 10 min |
| 6 | Core rotation functions | `mullvad-rotator.sh` | 10 min |
| 7 | Rotation interval + daemon | `mullvad-rotator.sh` | 10 min |
| 8 | CLI args + main entry | `mullvad-rotator.sh` | 5 min |
| 9 | Install helper + verify | `install.sh` | 5 min |

---

## Verification

After implementation, verify with:

```bash
# Syntax check
bash -n mullvad-rotator.sh

# Dry-run rotation
./mullvad-rotator.sh rotate --dry-run

# Show status
./mullvad-rotator.sh status

# Interactive TUI
./mullvad-rotator.sh

# Install
./install.sh
```

---

## Plan complete and saved to `docs/plans/2026-06-12-mullvad-rotator.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch fresh subagent per task, review between tasks, fast iteration.

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints.

**Which approach?**
