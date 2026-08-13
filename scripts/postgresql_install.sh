#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/postgresql_install.sh" >&2
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

PLATFORM_LIB="$SCRIPT_DIR/lib/platform.sh"
if [[ -f "$PLATFORM_LIB" ]]; then
	# shellcheck source=/dev/null
	source "$PLATFORM_LIB"
	sp_require_rocky8
fi

POSTGRES_SERVICE_NAME="postgresql"

service_start() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl daemon-reload || true
		systemctl enable "$POSTGRES_SERVICE_NAME" || true
		systemctl start "$POSTGRES_SERVICE_NAME"
	else
		service "$POSTGRES_SERVICE_NAME" start
	fi
}

service_status() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl status "$POSTGRES_SERVICE_NAME" --no-pager || true
	else
		service "$POSTGRES_SERVICE_NAME" status || true
	fi
}

postgresql_server_installed() {
	rpm -q "postgresql${POSTGRESQL_VERSION}-server" >/dev/null 2>&1 || rpm -q postgresql-server >/dev/null 2>&1
}

configure_postgresql_repo_if_needed() {
	if rpm -q pgdg-redhat-repo >/dev/null 2>&1; then
		return 0
	fi

	log "Installing PGDG repository for versioned PostgreSQL packages."
	dnf install -y "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
	dnf -qy module disable postgresql || true
}

install_postgresql_packages() {
	local versioned_server_pkg versioned_client_pkg
	versioned_server_pkg="postgresql${POSTGRESQL_VERSION}-server"
	versioned_client_pkg="postgresql${POSTGRESQL_VERSION}"

	dnf makecache

	configure_postgresql_repo_if_needed

	if dnf info "$versioned_server_pkg" >/dev/null 2>&1; then
		log "Installing PostgreSQL packages: $versioned_server_pkg, $versioned_client_pkg"
		dnf install -y "$versioned_server_pkg" "$versioned_client_pkg"
		POSTGRES_SERVICE_NAME="postgresql-${POSTGRESQL_VERSION}"

		if [[ -x "/usr/pgsql-${POSTGRESQL_VERSION}/bin/postgresql-${POSTGRESQL_VERSION}-setup" ]]; then
			"/usr/pgsql-${POSTGRESQL_VERSION}/bin/postgresql-${POSTGRESQL_VERSION}-setup" initdb || true
		fi
	else
		log "Package $versioned_server_pkg not found in current dnf sources. Installing default PostgreSQL packages instead."
		dnf install -y postgresql-server postgresql
		POSTGRES_SERVICE_NAME="postgresql"
		postgresql-setup --initdb || true
	fi
}

setup_postgres_dev_environment() {
	log "Creating PostgreSQL development database and role."

	# Create role if missing; update password either way to keep reruns idempotent.
	sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DO \
	\$\$BEGIN \
	IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '$DB_DEV_USER') THEN \
		CREATE ROLE \"$DB_DEV_USER\" LOGIN PASSWORD '$DB_DEV_PASSWORD'; \
	ELSE \
		ALTER ROLE \"$DB_DEV_USER\" WITH LOGIN PASSWORD '$DB_DEV_PASSWORD'; \
	END IF; \
	END\$\$;"

	# Create database if missing and assign ownership to the dev role.
	sudo -u postgres psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_DEV_DB_NAME'" | grep -q 1 || \
		sudo -u postgres createdb -O "$DB_DEV_USER" "$DB_DEV_DB_NAME"

	# Ensure ownership and privileges are aligned on reruns.
	sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER DATABASE \"$DB_DEV_DB_NAME\" OWNER TO \"$DB_DEV_USER\";"
	sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_DEV_DB_NAME\" TO \"$DB_DEV_USER\";"

	log "PostgreSQL development environment setup complete!"
	log "Connection details:"
	log "  - Database: $DB_DEV_DB_NAME"
	log "  - User: $DB_DEV_USER"
	log "  - Host: $DB_DEV_USER_HOST"
	log "  - Password: (stored in .env as DB_DEV_PASSWORD)"
	log ""
	log "To connect as postgres superuser:"
	log "  sudo -u postgres psql"
	log ""
	log "To connect as development user:"
	log "  psql \"host=$DB_DEV_USER_HOST dbname=$DB_DEV_DB_NAME user=$DB_DEV_USER password=$DB_DEV_PASSWORD\""
}

postgresql_install_main() {
	load_database_env
	validate_postgresql_version

	# Early exit if database is disabled
	if ! database_is_enabled; then
		log "Database provisioning is disabled (DATABASE_TYPE=none). Skipping."
		return 0
	fi

	if [[ "$DATABASE_TYPE" != "postgres" ]]; then
		log "DATABASE_TYPE is '$DATABASE_TYPE'; skipping PostgreSQL provisioning."
		return 0
	fi

	if postgresql_server_installed; then
		log "PostgreSQL server package is already installed."
	else
		log "Installing PostgreSQL (requested version: $POSTGRESQL_VERSION)."
		install_postgresql_packages
	fi

	psql --version || true

	log "Ensuring PostgreSQL service is running..."
	service_start

	if db_dev_setup_is_enabled; then
		setup_postgres_dev_environment
	else
		log "Development setup is disabled (DB_DEV_SETUP=false)."
		log "To enable, set DB_DEV_SETUP=true in .env and re-run this script."
	fi

	log "PostgreSQL provisioning complete."
	service_status
}

postgresql_install_main
