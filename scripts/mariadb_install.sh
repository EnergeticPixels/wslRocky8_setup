#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/mariadb_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_LIB="$SCRIPT_DIR/lib/database.sh"

if [[ ! -f "$DATABASE_LIB" ]]; then
	echo "Missing helper library: $DATABASE_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$DATABASE_LIB"

mariadb_install_main() {
	load_database_env

	# Early exit if database is disabled
	if ! database_is_enabled; then
		log "Database provisioning is disabled (DATABASE_TYPE=none). Skipping."
		return 0
	fi

	# Check if MariaDB is already installed
	if command -v mariadb &>/dev/null; then
		log "MariaDB is already installed. Verifying installation..."
		current_version=$(mariadb -V 2>&1 | awk '{print $NF}' | sed 's/,//g')
		log "Installed MariaDB version: $current_version"
		log "Requested MARIADB_VERSION: $MARIADB_VERSION"
		log "Using existing MariaDB installation."
	else
		log "Installing MariaDB server (version $MARIADB_VERSION)..."
		apt-get update
		apt-get install -y mariadb-server mariadb-client

		log "Enabling and starting MariaDB service..."
		systemctl daemon-reload
		systemctl enable mariadb
		systemctl start mariadb

		log "MariaDB installation complete."
	fi

	# Optional: Setup development database and user
	if mysql_dev_setup_is_enabled; then
		log "Setting up development database and user..."
		setup_mysql_dev_environment
	else
		log "Development setup is disabled (DB_DEV_SETUP=false)."
		log "To enable, set DB_DEV_SETUP=true in .env and re-run this script."
	fi
}

setup_mysql_dev_environment() {
	log "Creating development database: $DB_DEV_DB_NAME"
	mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`$DB_DEV_DB_NAME\`;"

	log "Creating development user: $DB_DEV_USER@$DB_DEV_USER_HOST"
	mariadb -u root -e "CREATE USER IF NOT EXISTS '$DB_DEV_USER'@'$DB_DEV_USER_HOST' IDENTIFIED BY '$DB_DEV_PASSWORD';"

	log "Granting privileges to development user..."
	mariadb -u root -e "GRANT ALL PRIVILEGES ON \`$DB_DEV_DB_NAME\`.* TO '$DB_DEV_USER'@'$DB_DEV_USER_HOST';"
	mariadb -u root -e "FLUSH PRIVILEGES;"

	log "Development environment setup complete!"
	log "Connection details:"
	log "  - Database: $DB_DEV_DB_NAME"
	log "  - User: $DB_DEV_USER"
	log "  - Host: $DB_DEV_USER_HOST"
	log "  - Password: (stored in .env as DB_DEV_PASSWORD)"
	log ""
	log "To connect as root:"
	log "  mariadb -u root"
	log ""
	log "To connect as development user:"
	log "  mariadb -u $DB_DEV_USER -p -h $DB_DEV_USER_HOST $DB_DEV_DB_NAME"
	log "(You will be prompted for the password: $DB_DEV_PASSWORD)"
}

mariadb_install_main
