#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/usr/local}"
TARGET="$PREFIX/bin/codex-provider"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO=""
RAW_BASE="${CODEX_PROVIDER_RAW_BASE:-https://raw.githubusercontent.com/driftbottle61/Codex-luncher/main}"

SOURCE="$ROOT/bin/codex-provider"
if [ ! -f "$SOURCE" ]; then
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required when installing via curl | bash" >&2
    exit 1
  }
  SOURCE="$(mktemp)"
  trap 'rm -f "$SOURCE"' EXIT
  curl -fsSL "$RAW_BASE/bin/codex-provider" -o "$SOURCE"
fi

if ! command -v tmux >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    [ "$(id -u)" -eq 0 ] || SUDO=sudo
    $SUDO apt-get update
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y tmux
  elif command -v dnf >/dev/null 2>&1; then
    [ "$(id -u)" -eq 0 ] || SUDO=sudo
    $SUDO dnf install -y tmux
  elif command -v apk >/dev/null 2>&1; then
    [ "$(id -u)" -eq 0 ] || SUDO=sudo
    $SUDO apk add tmux
  else
    echo "tmux is required; install it with your OS package manager" >&2
    exit 1
  fi
fi

command -v codex >/dev/null 2>&1 || {
  echo "codex is required; install @openai/codex first" >&2
  echo "Example: npm install -g @openai/codex" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || SUDO=sudo

$SUDO install -Dm755 "$SOURCE" "$TARGET"
echo "Installed $TARGET"
