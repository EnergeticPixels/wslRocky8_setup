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

configure_nginx_php_fpm() {
	local php_socket snippet_file default_site
	php_socket="/run/php/php${PHP_VERSION}-fpm.sock"
	snippet_file="/etc/nginx/snippets/php-fpm.conf"
	default_site="/etc/nginx/sites-available/default"

	mkdir -p /etc/nginx/snippets
	cat > "$snippet_file" <<EOF
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:${php_socket};
}

location ~ /\.ht {
    deny all;
}
EOF

	if [[ -f "$default_site" ]] && ! grep -q "include snippets/php-fpm.conf;" "$default_site"; then
		sed -i '/^[[:space:]]*index /a \    include snippets/php-fpm.conf;' "$default_site"
	fi
}

log "Installing Nginx web server (nginx)."
apt-get install -y nginx

restart_nginx=false

if php_is_enabled; then
	validate_php_version
	ensure_php_package_source
	install_versioned_php_packages
	resolve_php_extension_packages
	install_versioned_php_extensions
	configure_nginx_php_fpm

	log "Configuring Nginx for php-fpm version $PHP_VERSION."
	systemctl enable --now "php${PHP_VERSION}-fpm"
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
	systemctl restart nginx
	log "Nginx service restarted with current configuration."
fi

log "Nginx installation complete."