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
# SSH login shells source ~/.profile (login) and then ~/.bashrc (non-login),
# so older auto-enter hooks can live in either file. On upgrade we must find
# and disable them all; otherwise SSH would keep jumping into the *old* Codex
# session instead of the newest one.
install_login_hook() {
    local f="" line in_block=0 found_old=0
    local target="" rc=""
    local -a scan=() out=()
    for rc in "$HOME/.profile" "$HOME/.bash_profile"; do
        if [ -f "$rc" ]; then target="$rc"; break; fi
    done
    [ -n "$target" ] || target="$HOME/.profile"
    scan=("$target")
    [ -f "$HOME/.bashrc" ] && scan+=("$HOME/.bashrc")

    # 1) disable any older codex auto-enter hooks in every rc file
    for f in "${scan[@]}"; do
        if grep -q 'codex-luncher: SSH 交互登录显示' "$f" 2>/dev/null; then
            continue  # this file already carries the canonical hook
        fi
        out=(); found_old=0; in_block=0
        while IFS= read -r line; do
            case "$line" in
                *'codex-luncher:'*)
                    in_block=1; found_old=1
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
        done < "$f" 2>/dev/null || true
        if [ "$found_old" = 1 ]; then
            cp -a "$f" "$f.bak-install-$(date +%Y%m%d-%H%M%S)"
            printf '%s\n' "${out[@]}" > "$f"
            echo "codex-luncher: disabled old ssh hooks in $f (backup saved)"
        fi
    done

    # 2) make sure the canonical hook is active in the login rc file
    if grep -q 'codex-luncher: SSH 交互登录显示' "$target" 2>/dev/null; then
        echo "codex-luncher: ssh login hook already active in $target"
        return 0
    fi
    if [ -f "$target" ]; then
        cp -a "$target" "$target.bak-install-$(date +%Y%m%d-%H%M%S)"
        echo "codex-luncher: backed up $target"
    fi
    cat >> "$target" <<'EOF'

# codex-luncher: SSH 交互登录显示最近会话选择菜单（detach 或退出后回到 shell；CODEX_SKIP=1 可跳过）
if [ -n "$SSH_CONNECTION" ] && [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$CODEX_SKIP" ]; then
    codex-provider recent || true
fi
EOF
    echo "codex-luncher: ssh login hook enabled in $target"
}

# Informational: plain-codex history that will now appear in the picker.
detect_legacy_homes() {
    local h
    for h in $(printf '%s\n' "${CODEX_HOME:-}" "$HOME/.codex" | sed '/^$/d' | sort -u); do
        if [ -d "$h/sessions" ] && find "$h/sessions" -name '*.jsonl' 2>/dev/null | grep -q .; then
            echo "codex-luncher: existing Codex history detected at $h; its sessions are offered in 'codex-provider recent'"
        fi
    done
}

install_login_hook
detect_legacy_homes
