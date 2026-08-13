#!/usr/bin/env bash

# Shared platform detection and contract checks for orchestrator scripts.

sp_load_os_release() {
	if [[ ! -f /etc/os-release ]]; then
		echo "Error: /etc/os-release not found; cannot detect operating system." >&2
		return 1
	fi

	# shellcheck disable=SC1091
	source /etc/os-release

	SP_OS_ID="${ID:-unknown}"
	SP_OS_VERSION_ID="${VERSION_ID:-unknown}"
	SP_OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
}

sp_require_rocky8() {
	sp_load_os_release || return 1

	if [[ "$SP_OS_ID" != "rocky" ]]; then
		echo "Error: Unsupported distro '$SP_OS_ID'. This project currently supports Rocky Linux 8 only." >&2
		return 1
	fi

	if [[ ! "$SP_OS_VERSION_ID" =~ ^8(\.|$) ]]; then
		echo "Error: Unsupported Rocky version '$SP_OS_VERSION_ID'. This project currently supports Rocky Linux 8 only." >&2
		return 1
	fi
}

sp_is_wsl() {
	grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}
