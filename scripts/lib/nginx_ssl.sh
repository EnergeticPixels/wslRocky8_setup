#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

NGINX_SSL_DIR="/etc/nginx/ssl"
NGINX_SSL_CERT_FILE="$NGINX_SSL_DIR/serverprovo-local.crt"
NGINX_SSL_KEY_FILE="$NGINX_SSL_DIR/serverprovo-local.key"
NGINX_SSL_DOMAINS_FILE="$NGINX_SSL_DIR/serverprovo-domains.txt"
NGINX_SSL_SITE_FILE="/etc/nginx/sites-available/serverprovo-ssl.conf"
NGINX_SSL_ENABLED_FILE="/etc/nginx/sites-enabled/serverprovo-ssl.conf"
NGINX_SSL_RENEW_THRESHOLD_SECONDS=$((30 * 86400))

normalize_domain_local() {
	local domain
	domain="$1"
	domain="$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"
	printf '%s' "$domain"
}

is_valid_local_base_domain_runtime() {
	local domain
	domain="$(normalize_domain_local "$1")"

	if [[ -z "$domain" ]]; then
		return 1
	fi

	if [[ "$domain" == *" "* || "$domain" == *"*"* ]]; then
		return 1
	fi

	if [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.local$ ]]; then
		return 0
	fi

	return 1
}

nginx_ssl_domains_san_string() {
	local base
	base="$(normalize_domain_local "$1")"
	printf '%s,%s' "$base" "*.$base"
}

nginx_ssl_mkcert_domains_array() {
	local base
	base="$(normalize_domain_local "$1")"
	printf '%s\n%s\n' "$base" "*.$base"
}

nginx_ssl_install_mkcert_if_needed() {
	if command -v mkcert >/dev/null 2>&1; then
		return 0
	fi

	log "Installing mkcert for local development certificates."
	apt-get update
	apt-get install -y mkcert
}

nginx_ssl_backup_existing_artifacts() {
	local timestamp
	timestamp="$(date +%Y%m%d%H%M%S)"

	if [[ -f "$NGINX_SSL_CERT_FILE" ]]; then
		cp -f "$NGINX_SSL_CERT_FILE" "${NGINX_SSL_CERT_FILE}.${timestamp}.bak"
	fi
	if [[ -f "$NGINX_SSL_KEY_FILE" ]]; then
		cp -f "$NGINX_SSL_KEY_FILE" "${NGINX_SSL_KEY_FILE}.${timestamp}.bak"
	fi
	if [[ -f "$NGINX_SSL_DOMAINS_FILE" ]]; then
		cp -f "$NGINX_SSL_DOMAINS_FILE" "${NGINX_SSL_DOMAINS_FILE}.${timestamp}.bak"
	fi
}

nginx_ssl_seconds_until_expiry() {
	local cert_path expiry_line expiry_raw expiry_epoch now_epoch
	cert_path="$1"

	if [[ ! -f "$cert_path" ]]; then
		echo 0
		return 0
	fi

	expiry_line="$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null || true)"
	if [[ -z "$expiry_line" || "$expiry_line" != notAfter=* ]]; then
		echo 0
		return 0
	fi

	expiry_raw="${expiry_line#notAfter=}"
	expiry_epoch="$(date -d "$expiry_raw" +%s 2>/dev/null || true)"
	now_epoch="$(date +%s)"

	if [[ -z "$expiry_epoch" ]]; then
		echo 0
		return 0
	fi

	echo $(( expiry_epoch - now_epoch ))
}

nginx_ssl_should_regenerate() {
	local base_domain expected_domains existing_domains seconds_remaining
	base_domain="$(normalize_domain_local "$1")"
	expected_domains="$(nginx_ssl_domains_san_string "$base_domain")"

	if [[ ! -f "$NGINX_SSL_CERT_FILE" || ! -f "$NGINX_SSL_KEY_FILE" || ! -f "$NGINX_SSL_DOMAINS_FILE" ]]; then
		return 0
	fi

	existing_domains="$(cat "$NGINX_SSL_DOMAINS_FILE" 2>/dev/null || true)"
	if [[ "$existing_domains" != "$expected_domains" ]]; then
		return 0
	fi

	seconds_remaining="$(nginx_ssl_seconds_until_expiry "$NGINX_SSL_CERT_FILE")"
	if [[ "$seconds_remaining" -le "$NGINX_SSL_RENEW_THRESHOLD_SECONDS" ]]; then
		return 0
	fi

	return 1
}

nginx_ssl_generate_certificate() {
	local base_domain
	local -a mkcert_domains
	base_domain="$(normalize_domain_local "$1")"

	if ! is_valid_local_base_domain_runtime "$base_domain"; then
		echo "Invalid WEB_SSL_BASE_DOMAIN '$base_domain'. Use a base domain like app.local." >&2
		exit 1
	fi

	mkdir -p "$NGINX_SSL_DIR"

	if nginx_ssl_should_regenerate "$base_domain"; then
		log "Generating mkcert certificate for $base_domain and *.$base_domain"
		nginx_ssl_backup_existing_artifacts
		mapfile -t mkcert_domains < <(nginx_ssl_mkcert_domains_array "$base_domain")
		mkcert -install
		mkcert -cert-file "$NGINX_SSL_CERT_FILE" -key-file "$NGINX_SSL_KEY_FILE" "${mkcert_domains[@]}"
		chmod 640 "$NGINX_SSL_CERT_FILE" "$NGINX_SSL_KEY_FILE"
		chown root:www-data "$NGINX_SSL_CERT_FILE" "$NGINX_SSL_KEY_FILE"
		nginx_ssl_domains_san_string "$base_domain" > "$NGINX_SSL_DOMAINS_FILE"
		chmod 640 "$NGINX_SSL_DOMAINS_FILE"
		chown root:www-data "$NGINX_SSL_DOMAINS_FILE"
	else
		log "Existing Nginx SSL certificate is still valid and matches configured domains; skipping regeneration."
	fi
}

nginx_ssl_write_server_block() {
	local base_domain force_https_redirect
	base_domain="$(normalize_domain_local "$1")"
	force_https_redirect="${WEB_SSL_FORCE_HTTPS_REDIRECT:-true}"

	if [[ -f "/etc/nginx/snippets/php-fpm.conf" ]]; then
		if [[ "$force_https_redirect" == "true" ]]; then
			cat > "$NGINX_SSL_SITE_FILE" <<EOF
server {
	listen 80;
	listen [::]:80;
	server_name $base_domain *.$base_domain;

	return 301 https://\$host\$request_uri;
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	http2 on;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.php index.html index.htm index.nginx-debian.html;

	ssl_certificate $NGINX_SSL_CERT_FILE;
	ssl_certificate_key $NGINX_SSL_KEY_FILE;

	location / {
		try_files \$uri \$uri/ =404;
	}

	include snippets/php-fpm.conf;
}
EOF
		else
			cat > "$NGINX_SSL_SITE_FILE" <<EOF
server {
	listen 80;
	listen [::]:80;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.php index.html index.htm index.nginx-debian.html;

	location / {
		try_files \$uri \$uri/ =404;
	}

	include snippets/php-fpm.conf;
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	http2 on;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.php index.html index.htm index.nginx-debian.html;

	ssl_certificate $NGINX_SSL_CERT_FILE;
	ssl_certificate_key $NGINX_SSL_KEY_FILE;

	location / {
		try_files \$uri \$uri/ =404;
	}

	include snippets/php-fpm.conf;
}
EOF
		fi
	else
		if [[ "$force_https_redirect" == "true" ]]; then
			cat > "$NGINX_SSL_SITE_FILE" <<EOF
server {
	listen 80;
	listen [::]:80;
	server_name $base_domain *.$base_domain;

	return 301 https://\$host\$request_uri;
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	http2 on;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.html index.htm index.nginx-debian.html;

	ssl_certificate $NGINX_SSL_CERT_FILE;
	ssl_certificate_key $NGINX_SSL_KEY_FILE;

	location / {
		try_files \$uri \$uri/ =404;
	}
}
EOF
		else
			cat > "$NGINX_SSL_SITE_FILE" <<EOF
server {
	listen 80;
	listen [::]:80;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.html index.htm index.nginx-debian.html;

	location / {
		try_files \$uri \$uri/ =404;
	}
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	http2 on;
	server_name $base_domain *.$base_domain;

	root /var/www/html;
	index index.html index.htm index.nginx-debian.html;

	ssl_certificate $NGINX_SSL_CERT_FILE;
	ssl_certificate_key $NGINX_SSL_KEY_FILE;

	location / {
		try_files \$uri \$uri/ =404;
	}
}
EOF
		fi
	fi
}

nginx_ssl_enable_in_nginx() {
	ln -sfn "$NGINX_SSL_SITE_FILE" "$NGINX_SSL_ENABLED_FILE"
	nginx -t
}

nginx_ssl_setup() {
	local base_domain
	base_domain="$1"

	nginx_ssl_install_mkcert_if_needed
	nginx_ssl_generate_certificate "$base_domain"
	nginx_ssl_write_server_block "$base_domain"
	nginx_ssl_enable_in_nginx
}
