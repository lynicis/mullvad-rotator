<h1 align="center">Mullvad Rotator</h1>

<p align="center">
  <a href="https://github.com/lynicis/mullvad-rotator/releases"><img src="https://img.shields.io/github/v/release/lynicis/mullvad-rotator?style=flat&label=version" alt="Version"></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://github.com/lynicis/homebrew-tap"><img src="https://img.shields.io/badge/brew-lynicis%2Ftap-%23FBB040" alt="Homebrew"></a>
  <a href="https://github.com/lynicis/scoop-bucket"><img src="https://img.shields.io/badge/scoop-lynicis-brightgreen" alt="Scoop"></a>
  <br>
  <a href="https://github.com/lynicis/mullvad-rotator/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/lynicis/mullvad-rotator/release.yml?branch=main&label=release" alt="Release"></a>
</p>

<p align="center">
  Rotate Mullvad VPN relays and WireGuard keys — TUI and CLI.
</p>

## Table of Contents

- [Features](#features)
- [Installation](#installation)
  - [Homebrew](#homebrew)
  - [Scoop](#scoop)
  - [Manual](#manual)
- [Usage](#usage)
  - [CLI](#cli)
  - [TUI](#tui)
- [Daemon](#daemon)
- [Configuration](#configuration)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Relay rotation** — Switch to a random Mullvad relay (optionally filtered by country)
- **WireGuard key rotation** — Rotate your WireGuard key on demand
- **Country filtering** — Select specific countries via interactive multi-select TUI
- **Daemon mode** — Automatic rotation at configurable intervals (launchd / systemd)
- **Dual interface** — Full TUI menu + headless CLI for scripts and cron

## Installation

### Homebrew

```bash
brew tap lynicis/tap
brew install mullvad-rotator
```

### Scoop

```bash
scoop bucket add lynicis https://github.com/lynicis/scoop-bucket
scoop install mullvad-rotator
```

### Manual

```bash
curl -sSL https://github.com/lynicis/mullvad-rotator/releases/latest/download/mullvad-rotator.sh \
  -o /usr/local/bin/mullvad-rotator
chmod +x /usr/local/bin/mullvad-rotator
```

## Usage

### CLI

```bash
mullvad-rotator rotate              # Random relay
mullvad-rotator rotate --dry-run    # Preview only
mullvad-rotator rotate-key          # Rotate WireGuard key
mullvad-rotator status              # Detailed connection status
```

### TUI

```bash
mullvad-rotator
```

Menu options:

| # | Option |
|---|--------|
| 1 | Rotate connection |
| 2 | Rotate WireGuard key |
| 3 | Select countries |
| 4 | Show available countries |
| 5 | View detailed status |
| 6 | Set rotation interval |
| 7 | Install / remove daemon |
| 8 | Exit |

Country selector: Arrow keys to navigate, <kbd>Space</kbd> to toggle, type to filter, <kbd>Enter</kbd> to confirm, <kbd>a</kbd>/<kbd>n</kbd> for all/none, <kbd>Esc</kbd> to clear filter.

## Daemon

```bash
mullvad-rotator daemon-setup    # Interactive setup
mullvad-rotator daemon          # Run one cycle (for timer)
```

- **macOS**: Installs a launchd agent at `~/Library/LaunchAgents/com.user.mullvad-rotator.plist`
- **Linux**: Installs systemd user units at `~/.config/systemd/user/mullvad-rotator.{service,timer}`

Set interval via TUI menu option 6 or by editing the config file.

## Configuration

File: `~/.config/mullvad-rotator/config`

```ini
COUNTRIES="us de jp"    # Space-separated country codes (empty = all)
MODE="random"           # Rotation mode
INTERVAL=30             # Minutes between rotations (0 = disabled)
ROTATE_KEY=false        # Also rotate WireGuard key on each cycle
```

## Development

```bash
bash -n mullvad-rotator.sh    # Syntax check (only test available)
```

## Contributing

Issues and pull requests are welcome.

## License

MIT © Emre Sirmali
