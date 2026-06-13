# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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

