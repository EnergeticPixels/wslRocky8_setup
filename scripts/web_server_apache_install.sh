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

systemd_is_available() {
	command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

ensure_mod_ssl_default_certificates() {
	local cert_file key_file

	if [[ ! -f /etc/httpd/conf.d/ssl.conf ]]; then
		return 0
	fi

	cert_file="/etc/pki/tls/certs/localhost.crt"
	key_file="/etc/pki/tls/private/localhost.key"

	if [[ -s "$cert_file" && -s "$key_file" ]]; then
		return 0
	fi

	mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
	openssl req -x509 -nodes -newkey rsa:2048 \
		-keyout "$key_file" \
		-out "$cert_file" \
		-days 365 \
		-subj "/CN=localhost" >/dev/null 2>&1
	chmod 600 "$key_file"
	chmod 644 "$cert_file"
	log "Created fallback localhost TLS cert/key for Apache mod_ssl default config."
}

start_httpd() {
	ensure_mod_ssl_default_certificates

	if systemd_is_available; then
		systemctl enable --now httpd
		return 0
	fi

	if command -v httpd >/dev/null 2>&1; then
		if pgrep -x httpd >/dev/null 2>&1; then
			httpd -k graceful || true
		else
			httpd -k start
		fi
		log "Started httpd via direct httpd command because systemd is unavailable in this session."
		return 0
	fi

	echo "Unable to start httpd automatically: neither active systemd nor httpd command is available." >&2
	return 1
}

start_php_fpm() {
	if systemd_is_available; then
		systemctl enable --now "$PHP_FPM_SERVICE_NAME"
		return 0
	fi

	log "Skipping automatic php-fpm service start because systemd is unavailable in this session."
	return 0
}

stop_conflicting_nginx() {
	if ! pgrep -x nginx >/dev/null 2>&1; then
		return 0
	fi

	log "Detected running Nginx; stopping it to avoid port 80/443 conflict with Apache."

	if systemd_is_available; then
		systemctl stop nginx || true
		systemctl disable nginx || true
		return 0
	fi

	if command -v nginx >/dev/null 2>&1; then
		nginx -s quit || true
	fi

	pkill -x nginx >/dev/null 2>&1 || true
}

configure_apache_php_fpm() {
	local php_socket conf_file
	php_socket="$PHP_FPM_SOCKET"
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
	start_php_fpm
	stop_conflicting_nginx
	start_httpd
	if systemd_is_available; then
		systemctl restart httpd
	fi
	log "Apache configured with php-fpm version $PHP_VERSION."
else
	log "PHP installation disabled by PHP_ENABLE=false."
fi

if web_ssl_is_enabled; then
	log "WEB_SSL_ENABLE=true. Configuring Apache SSL via mkcert for base domain: $WEB_SSL_BASE_DOMAIN"
	apache_ssl_setup "$WEB_SSL_BASE_DOMAIN"
	if systemd_is_available; then
		systemctl restart httpd
	else
		httpd -k graceful || httpd -k start
	fi
	log "Apache SSL provisioning complete."
else
	log "Apache SSL provisioning disabled by WEB_SSL_ENABLE=false."
fi

if ! php_is_enabled; then
	stop_conflicting_nginx
	start_httpd || true
fi

log "Apache installation complete."