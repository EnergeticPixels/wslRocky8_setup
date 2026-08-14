#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/web_server_nginx_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PHP_WEB_LIB="$SCRIPT_DIR/lib/php_web.sh"
NGINX_SSL_LIB="$SCRIPT_DIR/lib/nginx_ssl.sh"

if [[ ! -f "$PHP_WEB_LIB" ]]; then
	echo "Missing helper library: $PHP_WEB_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$PHP_WEB_LIB"
load_web_stack_env

if [[ ! -f "$NGINX_SSL_LIB" ]]; then
	echo "Missing helper library: $NGINX_SSL_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$NGINX_SSL_LIB"

PLATFORM_LIB="$SCRIPT_DIR/lib/platform.sh"
if [[ -f "$PLATFORM_LIB" ]]; then
	# shellcheck source=/dev/null
	source "$PLATFORM_LIB"
	sp_require_rocky8
fi

systemd_is_available() {
	command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

start_nginx() {
	if systemd_is_available; then
		systemctl enable --now nginx
		return 0
	fi

	if command -v nginx >/dev/null 2>&1; then
		if pgrep -x nginx >/dev/null 2>&1; then
			nginx -s reload || true
		else
			nginx
		fi
		log "Started Nginx via direct nginx command because systemd is unavailable in this session."
		return 0
	fi

	echo "Unable to start Nginx automatically: neither active systemd nor nginx command is available." >&2
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

stop_conflicting_apache() {
	if ! pgrep -x httpd >/dev/null 2>&1; then
		return 0
	fi

	log "Detected running Apache (httpd); stopping it to avoid port 80/443 conflict with Nginx."

	if systemd_is_available; then
		systemctl stop httpd || true
		systemctl disable httpd || true
		return 0
	fi

	if command -v httpd >/dev/null 2>&1; then
		httpd -k stop || true
	fi

	pkill -x httpd >/dev/null 2>&1 || true
}

configure_nginx_php_fpm() {
	local php_socket snippet_file default_d_file
	php_socket="$PHP_FPM_SOCKET"
	snippet_file="/etc/nginx/snippets/php-fpm.conf"
	default_d_file="/etc/nginx/default.d/php-fpm.conf"

	mkdir -p /etc/nginx/snippets /etc/nginx/default.d
	cat > "$snippet_file" <<EOF
location ~ \.php$ {
	include fastcgi_params;
	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	fastcgi_index index.php;
    fastcgi_pass unix:${php_socket};
}

location ~ /\.ht {
    deny all;
}
EOF

	cat > "$default_d_file" <<EOF
include snippets/php-fpm.conf;
EOF
}

log "Installing Nginx web server (nginx)."
dnf install -y nginx

restart_nginx=false

if php_is_enabled; then
	validate_php_version
	ensure_php_package_source
	install_versioned_php_packages
	resolve_php_extension_packages
	install_versioned_php_extensions
	configure_nginx_php_fpm

	log "Configuring Nginx for php-fpm version $PHP_VERSION."
	start_php_fpm
	restart_nginx=true
	log "Nginx configured with php-fpm version $PHP_VERSION."
else
	log "PHP installation disabled by PHP_ENABLE=false."
fi

if web_ssl_is_enabled; then
	log "WEB_SSL_ENABLE=true. Configuring Nginx SSL via mkcert for base domain: $WEB_SSL_BASE_DOMAIN"
	nginx_ssl_setup "$WEB_SSL_BASE_DOMAIN"
	restart_nginx=true
	log "Nginx SSL provisioning complete."
else
	log "Nginx SSL provisioning disabled by WEB_SSL_ENABLE=false."
fi

if [[ "$restart_nginx" == "true" ]]; then
	nginx -t
	stop_conflicting_apache
	if systemd_is_available; then
		systemctl enable nginx || true
		systemctl restart nginx
	else
		start_nginx
	fi
	log "Nginx service restarted with current configuration."
fi

if [[ "$restart_nginx" != "true" ]]; then
	stop_conflicting_apache
	start_nginx || true
fi

log "Nginx installation complete."