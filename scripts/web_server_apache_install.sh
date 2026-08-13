#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/web_server_apache_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHP_WEB_LIB="$SCRIPT_DIR/lib/php_web.sh"
APACHE_SSL_LIB="$SCRIPT_DIR/lib/apache_ssl.sh"

if [[ ! -f "$PHP_WEB_LIB" ]]; then
	echo "Missing helper library: $PHP_WEB_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$PHP_WEB_LIB"
load_web_stack_env

if [[ ! -f "$APACHE_SSL_LIB" ]]; then
	echo "Missing helper library: $APACHE_SSL_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$APACHE_SSL_LIB"

PLATFORM_LIB="$SCRIPT_DIR/lib/platform.sh"
if [[ -f "$PLATFORM_LIB" ]]; then
	# shellcheck source=/dev/null
	source "$PLATFORM_LIB"
	sp_require_rocky8
fi

configure_apache_php_fpm() {
	local php_socket conf_file
	php_socket="/run/php-fpm/www.sock"
	conf_file="/etc/httpd/conf.d/php-fpm.conf"

	cat > "$conf_file" <<EOF
<FilesMatch \.php$>
    SetHandler "proxy:unix:${php_socket}|fcgi://localhost"
</FilesMatch>

DirectoryIndex index.php index.html
EOF
}

log "Installing Apache web server (httpd)."
dnf install -y httpd mod_ssl

if php_is_enabled; then
	validate_php_version
	ensure_php_package_source
	install_versioned_php_packages
	resolve_php_extension_packages
	install_versioned_php_extensions
	configure_apache_php_fpm

	log "Configuring Apache for php-fpm version $PHP_VERSION."
	systemctl enable --now "$PHP_FPM_SERVICE_NAME"
	systemctl enable --now httpd
	systemctl restart httpd
	log "Apache configured with php-fpm version $PHP_VERSION."
else
	log "PHP installation disabled by PHP_ENABLE=false."
fi

if web_ssl_is_enabled; then
	log "WEB_SSL_ENABLE=true. Configuring Apache SSL via mkcert for base domain: $WEB_SSL_BASE_DOMAIN"
	apache_ssl_setup "$WEB_SSL_BASE_DOMAIN"
	systemctl restart httpd
	log "Apache SSL provisioning complete."
else
	log "Apache SSL provisioning disabled by WEB_SSL_ENABLE=false."
fi

if ! php_is_enabled; then
	systemctl enable --now httpd || true
fi

log "Apache installation complete."