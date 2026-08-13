#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/vim_install.sh" >&2
	exit 1
fi

log "Ensuring vim is installed"
apt-get install -y vim

log "Setting vim as the system default editor"
update-alternatives --set editor /usr/bin/vim.basic 2>/dev/null || \
	update-alternatives --install /usr/bin/editor editor /usr/bin/vim 50

# Persist EDITOR and VISUAL for login shells system-wide.
PROFILE_FILE="/etc/profile.d/editor.sh"
cat > "$PROFILE_FILE" <<'EOF'
export EDITOR=vim
export VISUAL=vim
EOF
chmod 644 "$PROFILE_FILE"

log "Vim set as default editor (EDITOR=vim, VISUAL=vim)"
