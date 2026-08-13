#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/database_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MARIADB_SCRIPT="$SCRIPT_DIR/mariadb_install.sh"
POSTGRESQL_SCRIPT="$SCRIPT_DIR/postgresql_install.sh"
MONGODB_SCRIPT="$SCRIPT_DIR/mongodb_install.sh"
DATABASE_LIB="$SCRIPT_DIR/lib/database.sh"

if [[ ! -f "$DATABASE_LIB" ]]; then
	echo "Missing helper library: $DATABASE_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$DATABASE_LIB"
load_database_env
validate_database_type

if [[ "$DATABASE_TYPE" == "none" ]]; then
	log "DATABASE_TYPE is set to 'none'. Skipping database installation."
	exit 0
fi

database_choice="$(printf '%s' "$DATABASE_TYPE" | tr '[:upper:]' '[:lower:]')"

case "$database_choice" in
	mysql)
		if [[ ! -f "$MARIADB_SCRIPT" ]]; then
			echo "Missing installer script: $MARIADB_SCRIPT" >&2
			exit 1
		fi

		validate_mariadb_version
		log "Running MariaDB installer script (version $MARIADB_VERSION)."
		bash "$MARIADB_SCRIPT"
		;;
	postgres)
		if [[ ! -f "$POSTGRESQL_SCRIPT" ]]; then
			echo "Missing installer script: $POSTGRESQL_SCRIPT" >&2
			exit 1
		fi

		validate_postgresql_version
		log "Running PostgreSQL installer script (version $POSTGRESQL_VERSION)."
		bash "$POSTGRESQL_SCRIPT"
		;;
	mongodb)
		if [[ ! -f "$MONGODB_SCRIPT" ]]; then
			echo "Missing installer script: $MONGODB_SCRIPT" >&2
			exit 1
		fi

		validate_mongodb_version
		log "Running MongoDB installer script (version $MONGODB_VERSION)."
		bash "$MONGODB_SCRIPT"
		;;
	*)
		echo "Unexpected DATABASE_TYPE '$database_choice'" >&2
		exit 1
		;;
esac
