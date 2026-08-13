#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

APACHE_SSL_DIR="/etc/apache2/ssl"
APACHE_SSL_CERT_FILE="$APACHE_SSL_DIR/serverprovo-local.crt"
APACHE_SSL_KEY_FILE="$APACHE_SSL_DIR/serverprovo-local.key"
APACHE_SSL_DOMAINS_FILE="$APACHE_SSL_DIR/serverprovo-domains.txt"
APACHE_SSL_SITE_FILE="/etc/apache2/sites-available/serverprovo-ssl.conf"
APACHE_SSL_RENEW_THRESHOLD_SECONDS=$((30 * 86400))

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

apache_ssl_domains_san_string() {
	local base
	base="$(normalize_domain_local "$1")"
	printf '%s,%s' "$base" "*.$base"
}

apache_ssl_mkcert_domains_array() {
	local base
	base="$(normalize_domain_local "$1")"
	printf '%s\n%s\n' "$base" "*.$base"
}

apache_ssl_install_mkcert_if_needed() {
	if command -v mkcert >/dev/null 2>&1; then
		return 0
	fi

	log "Installing mkcert for local development certificates."
	apt-get update
	apt-get install -y mkcert
}

apache_ssl_backup_existing_artifacts() {
	local timestamp
	timestamp="$(date +%Y%m%d%H%M%S)"

	if [[ -f "$APACHE_SSL_CERT_FILE" ]]; then
		cp -f "$APACHE_SSL_CERT_FILE" "${APACHE_SSL_CERT_FILE}.${timestamp}.bak"
	fi
	if [[ -f "$APACHE_SSL_KEY_FILE" ]]; then
		cp -f "$APACHE_SSL_KEY_FILE" "${APACHE_SSL_KEY_FILE}.${timestamp}.bak"
	fi
	if [[ -f "$APACHE_SSL_DOMAINS_FILE" ]]; then
		cp -f "$APACHE_SSL_DOMAINS_FILE" "${APACHE_SSL_DOMAINS_FILE}.${timestamp}.bak"
	fi
}

apache_ssl_seconds_until_expiry() {
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

apache_ssl_should_regenerate() {
	local base_domain expected_domains existing_domains seconds_remaining
	base_domain="$(normalize_domain_local "$1")"
	expected_domains="$(apache_ssl_domains_san_string "$base_domain")"

	if [[ ! -f "$APACHE_SSL_CERT_FILE" || ! -f "$APACHE_SSL_KEY_FILE" || ! -f "$APACHE_SSL_DOMAINS_FILE" ]]; then
		return 0
	fi

	existing_domains="$(cat "$APACHE_SSL_DOMAINS_FILE" 2>/dev/null || true)"
	if [[ "$existing_domains" != "$expected_domains" ]]; then
		return 0
	fi

	seconds_remaining="$(apache_ssl_seconds_until_expiry "$APACHE_SSL_CERT_FILE")"
	if [[ "$seconds_remaining" -le "$APACHE_SSL_RENEW_THRESHOLD_SECONDS" ]]; then
		return 0
	fi

	return 1
}

apache_ssl_generate_certificate() {
	local base_domain
	local -a mkcert_domains
	base_domain="$(normalize_domain_local "$1")"

	if ! is_valid_local_base_domain_runtime "$base_domain"; then
		echo "Invalid WEB_SSL_BASE_DOMAIN '$base_domain'. Use a base domain like app.local." >&2
		exit 1
	fi

	mkdir -p "$APACHE_SSL_DIR"

	if apache_ssl_should_regenerate "$base_domain"; then
		log "Generating mkcert certificate for $base_domain and *.$base_domain"
		apache_ssl_backup_existing_artifacts
		mapfile -t mkcert_domains < <(apache_ssl_mkcert_domains_array "$base_domain")
		mkcert -install
		mkcert -cert-file "$APACHE_SSL_CERT_FILE" -key-file "$APACHE_SSL_KEY_FILE" "${mkcert_domains[@]}"
		chmod 640 "$APACHE_SSL_CERT_FILE" "$APACHE_SSL_KEY_FILE"
		chown root:www-data "$APACHE_SSL_CERT_FILE" "$APACHE_SSL_KEY_FILE"
		apache_ssl_domains_san_string "$base_domain" > "$APACHE_SSL_DOMAINS_FILE"
		chmod 640 "$APACHE_SSL_DOMAINS_FILE"
		chown root:www-data "$APACHE_SSL_DOMAINS_FILE"
	else
		log "Existing Apache SSL certificate is still valid and matches configured domains; skipping regeneration."
	fi
}

apache_ssl_write_vhost() {
	local base_domain
	base_domain="$(normalize_domain_local "$1")"

	cat > "$APACHE_SSL_SITE_FILE" <<EOF
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName $base_domain
        ServerAlias *.$base_domain

        DocumentRoot /var/www/html

        SSLEngine on
        SSLCertificateFile $APACHE_SSL_CERT_FILE
        SSLCertificateKeyFile $APACHE_SSL_KEY_FILE

		ErrorLog \${APACHE_LOG_DIR}/serverprovo-ssl-error.log
		CustomLog \${APACHE_LOG_DIR}/serverprovo-ssl-access.log combined
    </VirtualHost>
</IfModule>
EOF
}

apache_ssl_enable_in_apache() {
	a2enmod ssl >/dev/null
	a2ensite serverprovo-ssl >/dev/null
	apache2ctl configtest
}

apache_ssl_setup() {
	local base_domain
	base_domain="$1"

	apache_ssl_install_mkcert_if_needed
	apache_ssl_generate_certificate "$base_domain"
	apache_ssl_write_vhost "$base_domain"
	apache_ssl_enable_in_apache
}
