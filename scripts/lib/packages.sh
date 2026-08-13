#!/usr/bin/env bash

# Shared package manager abstraction for Rocky 8 orchestrator flows.

if [[ -z "${SP_OS_ID:-}" ]]; then
	# shellcheck disable=SC1091
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/platform.sh"
fi

sp_pkg_manager() {
	echo "dnf"
}

sp_pkg_refresh_cache() {
	dnf makecache
}

sp_pkg_upgrade_refresh() {
	dnf upgrade --refresh -y
}

sp_pkg_install() {
	if [[ "$#" -eq 0 ]]; then
		echo "Error: sp_pkg_install requires at least one package." >&2
		return 1
	fi

	dnf install -y "$@"
}

sp_pkg_is_installed() {
	local pkg
	pkg="$1"
	rpm -q "$pkg" >/dev/null 2>&1
}

sp_pkg_info() {
	local pkg
	pkg="$1"
	dnf info "$pkg"
}
