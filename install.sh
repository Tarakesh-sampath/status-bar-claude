#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

install_pkg() {
  local pkg=$1
  if command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y "$pkg"
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y "$pkg"
  elif command -v yum &>/dev/null; then
    sudo yum install -y "$pkg"
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm "$pkg"
  elif command -v apk &>/dev/null; then
    sudo apk add "$pkg"
  elif command -v brew &>/dev/null; then
    brew install "$pkg"
  else
    err "No supported package manager found. Install $pkg manually."
    exit 1
  fi
}

for dep in jq git bash; do
  if ! command -v "$dep" &>/dev/null; then
    warn "Missing: $dep — attempting to install..."
    install_pkg "$dep"
    if ! command -v "$dep" &>/dev/null; then
      err "Failed to install $dep. Install it manually."
      exit 1
    fi
    ok "Installed $dep"
  fi
done
ok "All dependencies found"

REPO="${STATUSLINE_REPO:-Tarakesh-sampath/status-bar-claude}"
BRANCH="${STATUSLINE_BRANCH:-main}"
RAW_URL="${STATUSLINE_URL:-https://raw.githubusercontent.com/$REPO/$BRANCH/statusline-command.sh}"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
SOURCE="$SCRIPT_DIR/statusline-command.sh"
DEST_DIR="$HOME/.claude"
DEST="$DEST_DIR/statusline-command.sh"
SETTINGS="$DEST_DIR/settings.json"

mkdir -p "$DEST_DIR"

if [[ -f "$SOURCE" ]]; then
    cp "$SOURCE" "$DEST"
else
    # Piped from curl / no local checkout — fetch the script from GitHub.
    warn "No local statusline-command.sh — fetching $RAW_URL"
    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 10 --max-time 60 "$RAW_URL" -o "$DEST.tmp"
    elif command -v wget &>/dev/null; then
        wget -qT 60 -O "$DEST.tmp" "$RAW_URL"
    else
        err "Need curl or wget to download statusline-command.sh"
        exit 1
    fi
    [[ -s "$DEST.tmp" ]] || { err "Download failed or empty: $RAW_URL"; rm -f "$DEST.tmp"; exit 1; }
    bash -n "$DEST.tmp" || { err "Downloaded script failed syntax check"; rm -f "$DEST.tmp"; exit 1; }
    mv "$DEST.tmp" "$DEST"
fi

chmod +x "$DEST"
ok "Installed $DEST"

if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
    warn "Created $SETTINGS"
fi

UPDATED="$(jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh", "refreshInterval": 1}}' "$SETTINGS")"
echo "$UPDATED" > "$SETTINGS"
ok "Updated $SETTINGS"

printf "\n${GREEN}Installation complete.${NC} Restart Claude Code to activate the status bar.\n"
