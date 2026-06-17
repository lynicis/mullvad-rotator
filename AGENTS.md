# Mullvad Rotator

Single bash script (`mullvad-rotator.sh`) with sourced config. TUI + CLI for
rotating Mullvad VPN relays and WireGuard keys.

## Quick start

```bash
./mullvad-rotator.sh          # TUI menu
./mullvad-rotator.sh rotate   # headless rotation
./mullvad-rotator.sh rotate --dry-run  # no-op test
./mullvad-rotator.sh status   # detailed status
./install.sh                  # symlink to ~/.local/bin
```

## Verification

```bash
bash -n mullvad-rotator.sh    # only test available (no test framework)
```

## Repo structure

| Path | Role |
|------|------|
| `mullvad-rotator.sh` | Single entrypoint. All logic in one file. |
| `install.sh` | Symlinks (or copies on Windows) script to `~/.local/bin/mullvad-rotator` |
| `docs/plans/` | Stale implementation plan (historic only) |

## Hard-won context

- **Only dependency:** `mullvad` CLI (must be installed + daemon running).
  On Windows, requires Git Bash or MSYS2 to run the bash script.
- **Config:** `~/.config/mullvad-rotator/config` (macOS/Linux) or
  `%APPDATA%\mullvad-rotator\config` (Windows) — auto-created on first run.
- **Cache:** `<config_dir>/countries.cache` (1-hour TTL). Refreshed
  via `mullvad relay list`.
- **Daemon log:** `<config_dir>/daemon.log`.
- **Daemon platform split:** macOS → launchd plist at
  `~/Library/LaunchAgents/com.user.mullvad-rotator.plist`. Linux → systemd
  user units at `~/.config/systemd/user/mullvad-rotator.{service,timer}`.
  Windows → Task Scheduler entry `MullvadRotator` via `schtasks.exe`.
- **Subcommands:** `daemon` (one rotation cycle, for the OS timer),
  `daemon-setup` (install + configure timer, called by `install.sh`).
- **No jq:** JSON parsed with `grep`/`sed`.
- **CLAUDE.md is a stale duplicate** of the GitNexus section below — delete or
  ignore it.

## CLI args (from `show_help`)

```
  ./mullvad-rotator.sh             Interactive TUI menu
  ./mullvad-rotator.sh rotate    Rotate to a random country (supports --dry-run)
  ./mullvad-rotator.sh status    Show detailed status
  ./mullvad-rotator.sh daemon      Run one rotation cycle (for launchd/systemd/Task Scheduler)
  ./mullvad-rotator.sh daemon-setup  Setup and install daemon service
```

## TUI country selector

The `select_countries_tui` function is keyboard-driven (not
numbered-input). Arrow keys to navigate, Space to toggle, type to
search/filter, Enter to confirm, `a`/`n` for all/none, Esc to clear search.

## TUI features

- `rotate_connection` asks to reconnect; `rotate_wireguard_key` asks to
  confirm — both need Y/n input.
- Interval set via TUI menu option 6. Daemon install offered when interval > 0.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **mullvad-rotator** (45 symbols, 39 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/mullvad-rotator/context` | Codebase overview, check index freshness |
| `gitnexus://repo/mullvad-rotator/clusters` | All functional areas |
| `gitnexus://repo/mullvad-rotator/processes` | All execution flows |
| `gitnexus://repo/mullvad-rotator/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
