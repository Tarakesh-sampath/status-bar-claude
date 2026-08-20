#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

# Resolve how (or whether) we can escalate for a package install. Only ever
# called when a dependency is actually missing — the common path needs no root.
SUDO=""
resolve_sudo() {
  [[ $(id -u) -eq 0 ]] && { SUDO=""; return 0; }          # already root
  command -v sudo &>/dev/null || return 1                  # no sudo on this box
  sudo -n true &>/dev/null && { SUDO="sudo"; return 0; }   # cached/passwordless
  # A password is needed: sudo reads it from /dev/tty, which curl | bash lacks.
  [[ -r /dev/tty ]] || return 1
  SUDO="sudo"
  return 0
}

manual_hint() {
  local pkg=$1
  if   command -v apt    &>/dev/null; then echo "sudo apt install -y $pkg"
  elif command -v dnf    &>/dev/null; then echo "sudo dnf install -y $pkg"
  elif command -v yum    &>/dev/null; then echo "sudo yum install -y $pkg"
  elif command -v pacman &>/dev/null; then echo "sudo pacman -S $pkg"
  elif command -v apk    &>/dev/null; then echo "sudo apk add $pkg"
  elif command -v brew   &>/dev/null; then echo "brew install $pkg"
  else echo "(install $pkg with your package manager)"
  fi
}

install_pkg() {
  local pkg=$1
  # Homebrew must never run under sudo.
  if command -v brew &>/dev/null && ! command -v apt &>/dev/null; then
    brew install "$pkg"
    return
  fi
  if ! resolve_sudo; then
    err "$pkg is missing and this installer cannot get root."
    err "Install it yourself, then re-run:  $(manual_hint "$pkg")"
    exit 1
  fi
  [[ -n "$SUDO" ]] && warn "Installing $pkg needs root — sudo may prompt for your password."
  if command -v apt &>/dev/null; then
    $SUDO apt update && $SUDO apt install -y "$pkg"
  elif command -v dnf &>/dev/null; then
    $SUDO dnf install -y "$pkg"
  elif command -v yum &>/dev/null; then
    $SUDO yum install -y "$pkg"
  elif command -v pacman &>/dev/null; then
    $SUDO pacman -S --noconfirm "$pkg"
  elif command -v apk &>/dev/null; then
    $SUDO apk add "$pkg"
  else
    err "No supported package manager found. Install $pkg manually."
    exit 1
  fi
}

missing=()
for dep in jq git bash; do
  command -v "$dep" &>/dev/null || missing+=("$dep")
done

if (( ${#missing[@]} )) && [[ -n "${STATUSLINE_SKIP_DEPS:-}" ]]; then
  warn "STATUSLINE_SKIP_DEPS set — not installing: ${missing[*]}"
elif (( ${#missing[@]} )); then
  for dep in "${missing[@]}"; do
    warn "Missing: $dep — attempting to install..."
    install_pkg "$dep"
    if ! command -v "$dep" &>/dev/null; then
      err "Failed to install $dep. Install it manually:  $(manual_hint "$dep")"
      exit 1
    fi
    ok "Installed $dep"
  done
else
  ok "All dependencies found"
fi

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

STATUSLINE_JSON='{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh",
    "refreshInterval": 1
  }
}'

if command -v jq &>/dev/null; then
    if [[ ! -f "$SETTINGS" ]]; then
        echo '{}' > "$SETTINGS"
        warn "Created $SETTINGS"
    fi
    UPDATED="$(jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh", "refreshInterval": 1}}' "$SETTINGS")"
    echo "$UPDATED" > "$SETTINGS"
    ok "Updated $SETTINGS"
elif [[ ! -s "$SETTINGS" ]] || [[ "$(tr -d '[:space:]' < "$SETTINGS")" == "{}" ]]; then
    # No jq, but nothing to preserve either — write the config wholesale.
    printf '%s\n' "$STATUSLINE_JSON" > "$SETTINGS"
    warn "jq not found — wrote $SETTINGS directly"
else
    # No jq and real settings on disk: refuse to clobber them.
    err "jq not found and $SETTINGS already has content — not overwriting it."
    err "Add this statusLine block to $SETTINGS by hand:"
    printf '%s\n' "$STATUSLINE_JSON" >&2
    exit 1
fi

printf "\n${GREEN}Installation complete.${NC} Restart Claude Code to activate the status bar.\n"
