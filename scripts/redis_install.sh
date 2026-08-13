#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/redis_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REDIS_LIB="$SCRIPT_DIR/lib/redis.sh"

if [[ ! -f "$REDIS_LIB" ]]; then
	echo "Missing helper library: $REDIS_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$REDIS_LIB"

install_redis_packages() {
	apt-get update
	apt-get install -y redis-server redis-tools
}

redis_install_main() {
	load_redis_env
	validate_redis_version

	if ! redis_is_enabled; then
		log "REDIS_ENABLE is false. Skipping Redis provisioning."
		return 0
	fi

	if redis_server_installed; then
		log "Redis server package is already installed."
	else
		log "Installing Redis server (requested version: $REDIS_VERSION)."
		install_redis_packages
	fi

	if command -v redis-server >/dev/null 2>&1; then
		installed_redis_version="$(redis-server --version 2>/dev/null | awk '{print $3}' | sed 's/^v=//')"
		if [[ -n "$installed_redis_version" ]]; then
			log "Installed redis-server version: $installed_redis_version"
		fi
	fi

	if [[ -n "$REDIS_VERSION" && -n "${installed_redis_version:-}" && "$installed_redis_version" != "$REDIS_VERSION" ]]; then
		log "Requested REDIS_VERSION=$REDIS_VERSION differs from installed version=$installed_redis_version (apt repository availability determines installable version)."
	fi

	log "Ensuring Redis service is running..."
	start_redis_service

	if grep -qi microsoft /proc/version 2>/dev/null && [[ ! -d /run/systemd/system ]]; then
		log "WSL detected without systemd. You may need to start Redis manually in new sessions: sudo service redis-server start"
	fi

	if command -v redis-cli >/dev/null 2>&1; then
		redis_ping_output="$(redis-cli ping 2>/dev/null || true)"
		if [[ "$redis_ping_output" == "PONG" ]]; then
			log "Redis smoke test passed (redis-cli ping -> PONG)."
		else
			log "Redis smoke test did not return PONG. Check service logs if you expected Redis to be running."
		fi
	fi

	log "Redis provisioning complete."
	show_redis_service_status
}

redis_install_main
