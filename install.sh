#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/usr/local}"
TARGET="$PREFIX/bin/codex-provider"
SUDO=""
RAW_BASE="${CODEX_PROVIDER_RAW_BASE:-https://raw.githubusercontent.com/driftbottle61/Codex-luncher/main}"

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  ROOT="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SOURCE="$ROOT/bin/codex-provider"
else
  ROOT=""
  SOURCE="$ROOT/bin/codex-provider"
fi
if [ ! -f "$SOURCE" ]; then
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required when installing via curl | bash" >&2
    exit 1
  }
  SOURCE="$(mktemp)"
  trap 'rm -f "$SOURCE"' EXIT
  if ! curl -fsSL "$RAW_BASE/bin/codex-provider" -o "$SOURCE"; then
    echo "failed to download $RAW_BASE/bin/codex-provider" >&2
    exit 1
  fi
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


# ---- ssh login hook management --------------------------------------------
# On machines where Codex was already used over SSH (plain `codex`, or an older
# codex-luncher hook that auto-entered the previous session), that old hook
# would keep winning after an upgrade and land on an old session. Detect such
# hooks in the login rc file, disable them (with a backup) and install the
# canonical "recent sessions" hook so SSH resumes the *newest* session.
install_login_hook() {
    local rc="" line in_block=0 found_old=0 has_new=0
    local -a out=()
    for rc in "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc" ]; then break; fi
        rc=""
    done
    [ -n "$rc" ] || rc="$HOME/.profile"

    # Already managed by this version? (marker text differs from old hooks)
    while IFS= read -r line; do
        case "$line" in
            *'codex-luncher: SSH 交互登录显示'*) has_new=1 ;;
        esac
    done < "$rc" 2>/dev/null || true
    if [ "$has_new" = 1 ]; then
        echo "codex-luncher: ssh login hook already installed in $rc"
        return 0
    fi

    while IFS= read -r line; do
        case "$line" in
            *'codex-luncher:'*)
                in_block=1
                found_old=1
                out+=("# codex-luncher: disabled old auto-enter hook: $line")
                continue
                ;;
        esac
        if [ "$in_block" = 1 ]; then
            out+=("# codex-luncher: disabled old auto-enter hook: $line")
            case "$line" in
                *fi*) in_block=0 ;;
            esac
            continue
        fi
        case "$line" in
            \#*) out+=("$line"); continue ;;  # keep unrelated comments
        esac
        if [[ "$line" =~ (^|[;&|[:space:]])(exec[[:space:]]+)?codex(-provider)?([[:space:]]|$) ]] \
           || [[ "$line" =~ codex-provider[[:space:]]+(go|recent|resume|menu) ]]; then
            out+=("# codex-luncher: disabled old ssh codex hook: $line")
            found_old=1
            continue
        fi
        out+=("$line")
    done < "$rc" 2>/dev/null || true

    if [ "$found_old" = 1 ] || [ ! -s "$rc" ]; then
        if [ -f "$rc" ]; then
            cp -a "$rc" "$rc.bak-install-$(date +%Y%m%d-%H%M%S)"
            echo "codex-luncher: backed up $rc"
        fi
        [ "$found_old" = 1 ] && printf '%s\n' "${out[@]}" > "$rc"
        cat >> "$rc" <<'EOF'

# codex-luncher: SSH 交互登录显示最近会话选择菜单（detach 或退出后回到 shell；CODEX_SKIP=1 可跳过）
if [ -n "$SSH_CONNECTION" ] && [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$CODEX_SKIP" ]; then
    codex-provider recent || true
fi
EOF
        echo "codex-luncher: ssh login hook installed in $rc (old hooks disabled)"
    else
        echo "codex-luncher: no previous ssh codex hook found in $rc; not enabling auto-resume."
        echo "  To enable: add to $rc:"
        echo '  if [ -n "$SSH_CONNECTION" ] && [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$CODEX_SKIP" ]; then codex-provider recent || true; fi'
    fi
}

# Informational: plain-codex history that will now appear in the picker.
detect_legacy_homes() {
    local h
    for h in "${CODEX_HOME:-}" "$HOME/.codex"; do
        [ -n "$h" ] || continue
        if [ -d "$h/sessions" ] && find "$h/sessions" -name '*.jsonl' 2>/dev/null | grep -q .; then
            echo "codex-luncher: existing Codex history detected at $h; its sessions are offered in 'codex-provider recent'"
        fi
    done
}

install_login_hook
detect_legacy_homes
