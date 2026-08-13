#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

load_redis_env() {
	local script_dir env_file
	script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	env_file="$script_dir/../../.env"

	if [[ -f "$env_file" ]]; then
		# shellcheck source=/dev/null
		source "$env_file"
	fi

	# Backward compatibility for lowercase keys.
	if [[ -z "${REDIS_ENABLE:-}" && -n "${redis_enable:-}" ]]; then
		REDIS_ENABLE="$redis_enable"
	fi
	if [[ -z "${REDIS_VERSION:-}" && -n "${redis_version:-}" ]]; then
		REDIS_VERSION="$redis_version"
	fi

	REDIS_ENABLE="${REDIS_ENABLE:-false}"
	REDIS_VERSION="${REDIS_VERSION:-7.0}"

	case "$(printf '%s' "$REDIS_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			REDIS_ENABLE=true
			;;
		0|false|no|n|off)
			REDIS_ENABLE=false
			;;
		*)
			echo "Invalid REDIS_ENABLE '$REDIS_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	export REDIS_ENABLE
	export REDIS_VERSION
}

validate_redis_version() {
	if [[ ! "$REDIS_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
		echo "Invalid REDIS_VERSION '$REDIS_VERSION'. Use MAJOR.MINOR or MAJOR.MINOR.PATCH (for example: 7.0 or 7.0.15)." >&2
		exit 1
	fi
}

redis_is_enabled() {
	[[ "$REDIS_ENABLE" == "true" ]]
}

redis_server_installed() {
	dpkg-query -W -f='${Status}' redis-server 2>/dev/null | grep -q "install ok installed"
}

start_redis_service() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl daemon-reload || true
		systemctl enable redis-server || true
		systemctl start redis-server
	else
		service redis-server start
	fi
}

show_redis_service_status() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl status redis-server --no-pager || true
	else
		service redis-server status || true
	fi
}
