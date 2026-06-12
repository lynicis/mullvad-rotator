# TUI Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the mullvad-rotator TUI more user-friendly by extracting shared helpers, adding arrow-key navigation to the main menu, fixing critical bugs, and improving visual consistency.

**Architecture:** Extract `read_key()`, `draw_box_line()`, and cursor helpers into a shared TUI primitives section. Rebuild `show_main_menu()` with arrow-key navigation. Patch `select_countries_tui()` to use shared helpers and fix the a/n search conflict. Add TUI-safe error handling.

**Tech Stack:** Bash, ANSI escape sequences, `read -rsn1`

**Verification:** `bash -n mullvad-rotator.sh` (syntax check — only available test)

---

### Task 1: Add shared TUI helpers

**Files:**
- Modify: `mullvad-rotator.sh:27-29` (after color definitions)

**Step 1: Add `BOX_WIDTH` constant and `strip_ansi()` helper**

Insert after line 29 (`CROSS="✗"`):

```bash
BOX_WIDTH=60

strip_ansi() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }
```

**Step 2: Add `draw_box_line()` and variants**

```bash
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
```

**Step 3: Add `read_key()`**

```bash
read_key() {
    KEY=""
    local byte
    IFS= read -rsn1 byte

    if [[ "$byte" == $'\x1b' ]]; then
        local ext=""
        read -rsn4 -t 0.05 ext || true
        case "$ext" in
            "[A")  KEY="up" ;;
            "[B")  KEY="down" ;;
            "[5~") KEY="pageup" ;;
            "[6~") KEY="pagedown" ;;
            "[H")  KEY="home" ;;
            "[F")  KEY="end" ;;
            "")    KEY="escape" ;;
            *)     KEY="unknown" ;;
        esac
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
```

**Step 4: Add `tui_cursor_hide()` / `tui_cursor_show()`**

```bash
tui_cursor_hide() { printf "\033[?25l"; trap 'printf "\033[?25h"' EXIT; }
tui_cursor_show() { printf "\033[?25h"; trap - EXIT; }
```

**Step 5: Add `tui_die()` helper**

```bash
tui_die() { error "$*"; [[ "${TUI_MODE:-false}" == "true" ]] && return 1 || exit 1; }
```

**Step 6: Verify syntax**

Run: `bash -n mullvad-rotator.sh`
Expected: no output (clean parse)

**Step 7: Commit**

```bash
git add mullvad-rotator.sh
git commit -m "refactor: add shared TUI helpers (read_key, draw_box_line, cursor)"
```

---

### Task 2: Refactor country selector to use `read_key()`

**Files:**
- Modify: `mullvad-rotator.sh:225-432` (`select_countries_tui`)

**Step 1: Hide/show cursor**

Replace `printf "\033[?25l"` and the trap on line 246-250 with:
```bash
tui_cursor_hide
```
Replace `printf "\033[?25h"` + trap restore on lines 405-406 with:
```bash
tui_cursor_show
```
Replace standalone `printf "\033[?25h"` at line 346 with:
```bash
tui_cursor_show
```

**Step 2: Replace key reading block**

Replace lines 330-401 with a `read_key` + `case "$KEY"` dispatch that includes:
- `up`/`down` — cursor movement
- `pageup`/`pagedown` — scroll by `window_size`
- `home`/`end` — jump to first/last
- `space` — toggle selection
- `enter` — confirm
- `escape` — clear filter if active, else warn + return
- `backspace` — delete filter char
- `a`/`A` — Select All (only when `filter_query` empty, else append to filter)
- `n`/`N` — Select None (only when `filter_query` empty, else append to filter)
- any other printable char — append to `filter_query`, reset cursor to 0

**Step 3: Update header**

Replace hardcoded box lines 292-297 with `draw_box_top`, `draw_box_line`, `draw_box_bottom`.

**Step 4: Replace separator lines**

Replace hardcoded `────` separators (303, 322) with `draw_box_line_plain`.

**Step 5: Update bottom status bar**

Line 327 — display `X countries | Y selected | PgUp/PgDn`.

**Step 6: Verify syntax**

Run: `bash -n mullvad-rotator.sh`

**Step 7: Commit**

```bash
git add mullvad-rotator.sh
git commit -m "fix: country selector search conflict, add PgUp/PgDn, escape feedback"
```

---

### Task 3: Main menu arrow-key navigation

**Files:**
- Modify: `mullvad-rotator.sh:39-44` (`confirm`)
- Modify: `mullvad-rotator.sh:161-222` (`print_status_line`, `show_main_menu`, `press_enter`)

**Step 1: Update `confirm()` prompt style**

Show `(Y/n)` or `(y/N)` based on default value.

**Step 2: Rewrite `show_main_menu()`**

Replace lines 171-217 with:
- Arrow-key navigation (wrapping top-to-bottom and bottom-to-top)
- Mode/interval info line between status and menu items
- Footer hint bar: `↑↓ Navigate  Enter Select`
- Number key shortcuts (1-8) still work invisibly
- Exit option (8) goes to `confirm "Exit?" "n"`
- Use `tui_cursor_hide`/`show`, `draw_box_*`, `read_key`

**Step 3: Verify syntax**

Run: `bash -n mullvad-rotator.sh`

**Step 4: Commit**

```bash
git add mullvad-rotator.sh
git commit -m "feat: main menu arrow-key navigation with mode/interval display"
```

---

### Task 4: Fix error handling, safety, and visual consistency

**Files:**
- Modify: `mullvad-rotator.sh:462-528` (`rotate_connection`, `rotate_wireguard_key`)
- Modify: `mullvad-rotator.sh:565-583` (`set_rotation_interval`)
- Modify: `mullvad-rotator.sh:530-562` (`show_detailed_status`)
- Modify: `mullvad-rotator.sh:678-692` (`daemon_menu`)
- Modify: `mullvad-rotator.sh:29` (remove unused `CROSS`)

**Step 1: Replace die calls in rotate functions**

In `rotate_connection` (lines 479, 480, 482, 495) and `rotate_wireguard_key` (line 516), replace `|| die "..."` with `|| tui_die "..."`.

**Step 2: Safe default for destructive key rotation**

Line 511: specify `"n"` as default for the confirm call.

**Step 3: Interval/daemon sync**

In `set_rotation_interval` (line 580/581), after setting to 0, check if daemon is installed and offer removal.

**Step 4: Consistent box widths for `show_detailed_status`**

Replace hardcoded box drawing with `draw_box_*` helpers.

**Step 5: Arrow-key daemon sub-menu**

Rewrite `daemon_menu` (lines 678-692) as a 3-item arrow-key menu using `read_key`.

**Step 6: Remove unused `CROSS`**

Delete line 29.

**Step 7: Verify syntax**

Run: `bash -n mullvad-rotator.sh`

**Step 8: Commit**

```bash
git add mullvad-rotator.sh
git commit -m "fix: TUI-safe errors, safe defaults, consistent box widths"
```

---

### Task 5: Final verification

**Step 1: Full syntax check**

Run: `bash -n mullvad-rotator.sh`

**Step 2: Manual smoke test**

- [ ] Arrow keys navigate main menu, Enter selects
- [ ] Mode/interval shown in header
- [ ] Country selector — type "panama", verify `a` appends to search
- [ ] Escape with no filter — see "Selection cancelled"
- [ ] PgUp/PgDn scroll in country selector
- [ ] WireGuard key rotation — Enter alone does NOT proceed
- [ ] Exit — asks "Exit? (y/N)"
- [ ] Number keys 1-8 still work in main menu

**Step 3: Commit**

```bash
git add mullvad-rotator.sh
git commit -m "chore: final cleanup after TUI polish"
```
