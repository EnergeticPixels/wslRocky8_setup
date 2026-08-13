#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

TMUX_CONFIG_NAME=".tmux.conf"

# Load TMUX_CONFIG_URL from the .env file alongside begin_here.sh.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
	# shellcheck source=/dev/null
	source "$ENV_FILE"
fi

# Backward compatibility: allow lowercase key names in older/local .env files.
if [[ -z "${TMUX_CONFIG_URL:-}" && -n "${tmux_config_url:-}" ]]; then
	TMUX_CONFIG_URL="$tmux_config_url"
fi

if [[ -z "${TMUX_CONFIG_URL:-}" ]]; then
	if [[ "${PROVISIONING_NONINTERACTIVE:-false}" == "true" ]]; then
		log "No TMUX_CONFIG_URL configured in non-interactive provisioning mode. Skipping tmux setup."
		exit 0
	fi

	if [[ -t 0 ]]; then
		log "No TMUX_CONFIG_URL found in .env."
		read -r -p "Enter raw gist URL for .tmux.conf (leave empty to skip tmux setup): " user_tmux_url
		if [[ -n "$user_tmux_url" ]]; then
			TMUX_CONFIG_URL="$user_tmux_url"
			if [[ -f "$ENV_FILE" ]]; then
				printf '\nTMUX_CONFIG_URL=%s\n' "$TMUX_CONFIG_URL" >> "$ENV_FILE"
				log "Saved TMUX_CONFIG_URL to $ENV_FILE for future runs."
			fi
		fi
	else
		log "No TMUX_CONFIG_URL configured and no interactive terminal available. Skipping tmux setup."
		exit 0
	fi
fi

if [[ -z "${TMUX_CONFIG_URL:-}" ]]; then
	log "No tmux config URL provided. Skipping tmux installation and configuration."
	exit 0
fi

TMUX_GIST_URL="$TMUX_CONFIG_URL"

# Resolve the target user's home directory.
# When run via `sudo bash begin_here.sh`, SUDO_USER is the invoking user.
resolve_target_home() {
	local target_user="${SUDO_USER:-}"
	if [[ -n "$target_user" ]]; then
		getent passwd "$target_user" | cut -d: -f6
	else
		echo "$HOME"
	fi
}

log "Installing tmux..."
apt-get install -y tmux
log "tmux installation complete."

# --- tmux configuration ---
TARGET_HOME="$(resolve_target_home)"
TMUX_CONFIG_PATH="$TARGET_HOME/$TMUX_CONFIG_NAME"

log "Fetching tmux configuration from Gist..."
if ! curl -fsSL -L "$TMUX_GIST_URL" -o "$TMUX_CONFIG_PATH"; then
	log "ERROR: Failed to download tmux configuration from $TMUX_GIST_URL"
	exit 1
fi

# Ensure ownership belongs to the target user, not root.
if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
	chown "$SUDO_USER:$SUDO_USER" "$TMUX_CONFIG_PATH"
fi

log "tmux configuration installed to $TMUX_CONFIG_PATH"
