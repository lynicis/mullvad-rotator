# Release Automation: Homebrew, Scoop, GitHub Release & README

**Date:** 2026-06-12

## Goal

Her `v*` tag push'inde:
- GitHub Release oluştur + `mullvad-rotator.sh` asset
- `lynicis/homebrew-tap` → Formula güncelle
- `lynicis/scoop-bucket` → Manifest güncelle
- `README.md` awesome-readme standardında

## Files to modify/create

| File | Action |
|------|--------|
| `mullvad-rotator.sh` | Modify: `--version` flag ekle |
| `CHANGELOG.md` | Create: template (içerik workflow dolduracak) |
| `.github/workflows/release.yml` | Create: release pipeline |
| `README.md` | Create: awesome-readme standardı |

## Step 1: `--version` flag

**File:** `mullvad-rotator.sh` (~line 730)

Insert before existing `--help|-h)` case:

```bash
--version|-v)
    echo "mullvad-rotator v${VERSION}"
    exit 0
    ;;
```

**Why:** Homebrew `test do` block needs `--version` output.

## Step 2: `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
      sha256_sh: ${{ steps.hash.outputs.sha256_sh }}
      sha256_tar: ${{ steps.hash.outputs.sha256_tar }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Extract version
        id: version
        run: echo "version=${GITHUB_REF#refs/tags/v}" >> "$GITHUB_OUTPUT"

      - name: Compute checksums
        id: hash
        run: |
          echo "sha256_sh=$(sha256sum mullvad-rotator.sh | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"
          curl -sL "${{ github.server_url }}/${{ github.repository }}/archive/refs/tags/${{ github.ref_name }}.tar.gz" -o /tmp/repo.tar.gz
          echo "sha256_tar=$(sha256sum /tmp/repo.tar.gz | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"

      - name: Generate release notes
        id: notes
        run: |
          prev_tag=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
          if [ -n "$prev_tag" ]; then
            echo "## Changes since $prev_tag" > /tmp/release-notes.md
            git log "$prev_tag..HEAD" --oneline --no-decorate >> /tmp/release-notes.md
          else
            echo "Initial release v${{ steps.version.outputs.version }}" > /tmp/release-notes.md
          fi

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          name: Mullvad Rotator v${{ steps.version.outputs.version }}
          body_path: /tmp/release-notes.md
          files: mullvad-rotator.sh

  homebrew:
    needs: release
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: lynicis/homebrew-tap
          token: ${{ secrets.GITHUB_PAT }}

      - name: Write formula
        run: |
          cat > Formula/mullvad-rotator.rb << RUBY
          class MullvadRotator < Formula
            desc "Rotate Mullvad VPN relays and WireGuard keys"
            homepage "https://github.com/lynicis/mullvad-rotator"
            url "https://github.com/lynicis/mullvad-rotator/archive/refs/tags/v${{ needs.release.outputs.version }}.tar.gz"
            sha256 "${{ needs.release.outputs.sha256_tar }}"
            license "MIT"

            depends_on "mullvad" => :run

            def install
              bin.install "mullvad-rotator.sh" => "mullvad-rotator"
            end

            test do
              assert_match version.to_s, shell_output("#{bin}/mullvad-rotator --version 2>&1")
            end
          end
          RUBY

      - name: Commit & push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Formula/mullvad-rotator.rb
          git commit -m "mullvad-rotator v${{ needs.release.outputs.version }}"
          git push

  scoop:
    needs: release
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: lynicis/scoop-bucket
          token: ${{ secrets.GITHUB_PAT }}

      - name: Write manifest
        run: |
          cat > mullvad-rotator.json << JSON
          {
            "version": "${{ needs.release.outputs.version }}",
            "architecture": {
              "64bit": {
                "url": "https://github.com/lynicis/mullvad-rotator/releases/download/v${{ needs.release.outputs.version }}/mullvad-rotator.sh",
                "bin": ["mullvad-rotator.sh"],
                "hash": "${{ needs.release.outputs.sha256_sh }}"
              }
            },
            "homepage": "https://github.com/lynicis/mullvad-rotator",
            "license": "MIT",
            "description": "Rotate Mullvad VPN relays and WireGuard keys"
          }
          JSON

      - name: Commit & push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add mullvad-rotator.json
          git commit -m "mullvad-rotator v${{ needs.release.outputs.version }}"
          git push
```

## Step 3: `CHANGELOG.md`

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).
```

## Step 4: `README.md` (awesome-readme standard)

```markdown
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
```

## Dependency

| Item | Required? | Notes |
|------|-----------|-------|
| `GITHUB_PAT` secret | **Yes** | `repo` scope, push access to homebrew-tap + scoop-bucket |

## Verification

```bash
bash -n mullvad-rotator.sh
# Create a test tag (dry-run):
git tag v1.0.0-test && git push origin v1.0.0-test
# Check:
# - GitHub Release created
# - homebrew-tap/Formula/mullvad-rotator.rb exists
# - scoop-bucket/mullvad-rotator.json exists
# Then delete test tag locally + remote
```
