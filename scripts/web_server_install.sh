#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/web_server_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APACHE_SCRIPT="$SCRIPT_DIR/web_server_apache_install.sh"
NGINX_SCRIPT="$SCRIPT_DIR/web_server_nginx_install.sh"
PHP_WEB_LIB="$SCRIPT_DIR/lib/php_web.sh"

if [[ ! -f "$PHP_WEB_LIB" ]]; then
	echo "Missing helper library: $PHP_WEB_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$PHP_WEB_LIB"
load_web_stack_env

if [[ -z "${WEB_SERVER:-}" ]]; then
	log "WEB_SERVER is not set in .env. Skipping web server installation."
	exit 0
fi

if php_is_enabled; then
	validate_php_version
	log "PHP provisioning is enabled with requested version $PHP_VERSION."
else
	log "PHP provisioning is disabled (PHP_ENABLE=false)."
fi

web_server_choice="$(printf '%s' "$WEB_SERVER" | tr '[:upper:]' '[:lower:]')"

case "$web_server_choice" in
	apache)
		if [[ ! -f "$APACHE_SCRIPT" ]]; then
			echo "Missing installer script: $APACHE_SCRIPT" >&2
			exit 1
		fi

		log "Running Apache installer script."
		bash "$APACHE_SCRIPT"
		;;
	nginx)
		if [[ ! -f "$NGINX_SCRIPT" ]]; then
			echo "Missing installer script: $NGINX_SCRIPT" >&2
			exit 1
		fi

		log "Running Nginx installer script."
		bash "$NGINX_SCRIPT"
		;;
	*)
		echo "Invalid WEB_SERVER '$WEB_SERVER'. Supported values: apache, nginx" >&2
		exit 1
		;;
esac

log "Web server provisioning complete via installer: $web_server_choice"