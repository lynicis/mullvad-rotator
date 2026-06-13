#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/mullvad-rotator.sh"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/mullvad-rotator"

# OS detection
case "$(uname)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *)                     IS_WINDOWS=false ;;
esac

echo "Installing Mullvad Rotator..."
echo ""

# Check script exists
[[ -f "$SCRIPT" ]] || { echo "Error: mullvad-rotator.sh not found in $SCRIPT_DIR"; exit 1; }

# Create bin dir
mkdir -p "$BIN_DIR"

# Create symlink (or copy on Windows — NTFS symlinks require admin)
if $IS_WINDOWS; then
    cp "$SCRIPT" "$BIN"
    echo "  ✓ Copied: ${BIN} <- ${SCRIPT}"
else
    ln -sf "$SCRIPT" "$BIN"
    echo "  ✓ Symlinked: ${BIN} -> ${SCRIPT}"
fi
chmod +x "$SCRIPT"

# Path check
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠  ${BIN_DIR} is not in your PATH."
    if $IS_WINDOWS; then
        echo "     Add this to your ~/.bashrc (Git Bash):"
    else
        echo "     Add this to your ~/.bashrc or ~/.zshrc:"
    fi
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

