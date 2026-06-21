# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.5] - 2026-06-21
### Fixed
- Clean up legacy `com.user.mullvad-rotator` launchd agent on macOS when installing or removing the daemon.
- Update documentation references to point to the correct launch agent plist.

## [1.1.4] - 2026-06-21
### Added
- System-wide SOCKS5 proxy configuration support with manual toggle (TUI option 6) and automatic application on connection.

### Fixed
- Fix macOS daemon plist namespace and label to use `com.lynicis.mullvad-rotator`.

### Changed
- Optimize TUI main menu rendering performance and background CPU usage by caching configuration and daemon status loads between submenu actions, avoiding subshell forks in `refresh_cache` and `strip_ansi`, and increasing the keypress wait timeout to 5 seconds when an interval is active.

## [1.1.3] - 2026-06-21
### Added
- MIT License file.

### Fixed
- Remove the broken "rotate WireGuard key" feature due to an upstream Mullvad daemon bug.

## [1.1.2] - 2026-06-13
### Fixed
- Optimize TUI rendering performance and frame rate (snappy menu navigation and character filtering) by caching status queries, pre-rendering borders, and using pure Bash operations to avoid external command forks (`seq`, `sed`, `tr`).

## [1.1.1] - 2026-06-13
### Fixed
- Fix syntax error in generated Homebrew formula (missing closing `end` for the `Formula` class).

## [1.1.0] - 2026-06-13
### Added
- Complete support for Windows (Git Bash / MSYS2 / CYGWIN).
- Platform-aware config directories (using `$APPDATA` on Windows).
- Windows Task Scheduler integration (`schtasks.exe`) for auto-rotation daemon service.
- Copy installer fallback for Windows environments to avoid NTFS symlink privilege issues.

