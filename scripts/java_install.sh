#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/java_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JAVA_LIB="$SCRIPT_DIR/lib/java_stack.sh"
TOMCAT_INSTALL_SCRIPT="$SCRIPT_DIR/tomcat_install.sh"
JAVA_SERVICE_INSTALL_SCRIPT="$SCRIPT_DIR/java_service_install.sh"

if [[ ! -f "$JAVA_LIB" ]]; then
	echo "Missing helper library: $JAVA_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$JAVA_LIB"
load_java_stack_env

if ! java_is_enabled; then
	log "JAVA_ENABLE is false. Skipping Java provisioning."
	exit 0
fi

validate_java_server_mode
validate_java_version
validate_java_distro

case "$JAVA_SERVER_MODE" in
	tomcat)
		if [[ ! -f "$TOMCAT_INSTALL_SCRIPT" ]]; then
			echo "Missing installer script: $TOMCAT_INSTALL_SCRIPT" >&2
			exit 1
		fi

		log "Running Tomcat installer script."
		bash "$TOMCAT_INSTALL_SCRIPT"
		;;
	jar)
		if [[ ! -f "$JAVA_SERVICE_INSTALL_SCRIPT" ]]; then
			echo "Missing installer script: $JAVA_SERVICE_INSTALL_SCRIPT" >&2
			exit 1
		fi

		validate_jar_inputs
		log "Running standalone Java service installer script."
		bash "$JAVA_SERVICE_INSTALL_SCRIPT"
		;;
	esac

log "Java provisioning complete via mode: $JAVA_SERVER_MODE"
