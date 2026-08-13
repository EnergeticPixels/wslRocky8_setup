#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

load_database_env() {
	local script_dir env_file
	script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	env_file="$script_dir/../../.env"

	if [[ -f "$env_file" ]]; then
		# shellcheck source=/dev/null
		source "$env_file"
	fi

	# Backward compatibility for lowercase key names.
	if [[ -z "${DATABASE_TYPE:-}" && -n "${database_type:-}" ]]; then
		DATABASE_TYPE="$database_type"
	fi
	if [[ -z "${MARIADB_VERSION:-}" && -n "${mariadb_version:-}" ]]; then
		MARIADB_VERSION="$mariadb_version"
	fi
	if [[ -z "${POSTGRESQL_VERSION:-}" && -n "${postgresql_version:-}" ]]; then
		POSTGRESQL_VERSION="$postgresql_version"
	fi
	if [[ -z "${MONGODB_VERSION:-}" && -n "${mongodb_version:-}" ]]; then
		MONGODB_VERSION="$mongodb_version"
	fi
	if [[ -z "${DB_DEV_SETUP:-}" && -n "${db_dev_setup:-}" ]]; then
		DB_DEV_SETUP="$db_dev_setup"
	fi
	if [[ -z "${DB_DEV_DB_NAME:-}" && -n "${db_dev_db_name:-}" ]]; then
		DB_DEV_DB_NAME="$db_dev_db_name"
	fi
	if [[ -z "${DB_DEV_USER:-}" && -n "${db_dev_user:-}" ]]; then
		DB_DEV_USER="$db_dev_user"
	fi
	if [[ -z "${DB_DEV_PASSWORD:-}" && -n "${db_dev_password:-}" ]]; then
		DB_DEV_PASSWORD="$db_dev_password"
	fi
	if [[ -z "${DB_DEV_USER_HOST:-}" && -n "${db_dev_user_host:-}" ]]; then
		DB_DEV_USER_HOST="$db_dev_user_host"
	fi

	# Backward compatibility for legacy per-database dev setup keys.
	if [[ -z "${DB_DEV_SETUP:-}" ]]; then
		if [[ -n "${MYSQL_DEV_SETUP:-}" ]]; then
			DB_DEV_SETUP="$MYSQL_DEV_SETUP"
		elif [[ -n "${POSTGRES_DEV_SETUP:-}" ]]; then
			DB_DEV_SETUP="$POSTGRES_DEV_SETUP"
		elif [[ -n "${mysql_dev_setup:-}" ]]; then
			DB_DEV_SETUP="$mysql_dev_setup"
		elif [[ -n "${postgres_dev_setup:-}" ]]; then
			DB_DEV_SETUP="$postgres_dev_setup"
		fi
	fi
	if [[ -z "${DB_DEV_DB_NAME:-}" ]]; then
		if [[ -n "${MYSQL_DEV_DB_NAME:-}" ]]; then
			DB_DEV_DB_NAME="$MYSQL_DEV_DB_NAME"
		elif [[ -n "${POSTGRES_DEV_DB_NAME:-}" ]]; then
			DB_DEV_DB_NAME="$POSTGRES_DEV_DB_NAME"
		elif [[ -n "${mysql_dev_db_name:-}" ]]; then
			DB_DEV_DB_NAME="$mysql_dev_db_name"
		elif [[ -n "${postgres_dev_db_name:-}" ]]; then
			DB_DEV_DB_NAME="$postgres_dev_db_name"
		fi
	fi
	if [[ -z "${DB_DEV_USER:-}" ]]; then
		if [[ -n "${MYSQL_DEV_USER:-}" ]]; then
			DB_DEV_USER="$MYSQL_DEV_USER"
		elif [[ -n "${POSTGRES_DEV_USER:-}" ]]; then
			DB_DEV_USER="$POSTGRES_DEV_USER"
		elif [[ -n "${mysql_dev_user:-}" ]]; then
			DB_DEV_USER="$mysql_dev_user"
		elif [[ -n "${postgres_dev_user:-}" ]]; then
			DB_DEV_USER="$postgres_dev_user"
		fi
	fi
	if [[ -z "${DB_DEV_PASSWORD:-}" ]]; then
		if [[ -n "${MYSQL_DEV_PASSWORD:-}" ]]; then
			DB_DEV_PASSWORD="$MYSQL_DEV_PASSWORD"
		elif [[ -n "${POSTGRES_DEV_PASSWORD:-}" ]]; then
			DB_DEV_PASSWORD="$POSTGRES_DEV_PASSWORD"
		elif [[ -n "${mysql_dev_password:-}" ]]; then
			DB_DEV_PASSWORD="$mysql_dev_password"
		elif [[ -n "${postgres_dev_password:-}" ]]; then
			DB_DEV_PASSWORD="$postgres_dev_password"
		fi
	fi
	if [[ -z "${DB_DEV_USER_HOST:-}" ]]; then
		if [[ -n "${MYSQL_DEV_USER_HOST:-}" ]]; then
			DB_DEV_USER_HOST="$MYSQL_DEV_USER_HOST"
		elif [[ -n "${POSTGRES_DEV_USER_HOST:-}" ]]; then
			DB_DEV_USER_HOST="$POSTGRES_DEV_USER_HOST"
		elif [[ -n "${mysql_dev_user_host:-}" ]]; then
			DB_DEV_USER_HOST="$mysql_dev_user_host"
		elif [[ -n "${postgres_dev_user_host:-}" ]]; then
			DB_DEV_USER_HOST="$postgres_dev_user_host"
		fi
	fi

	DATABASE_TYPE="${DATABASE_TYPE:-none}"
	MARIADB_VERSION="${MARIADB_VERSION:-10.5}"
	POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-17}"
	MONGODB_VERSION="${MONGODB_VERSION:-8.0}"
	DB_DEV_SETUP="${DB_DEV_SETUP:-false}"
	DB_DEV_DB_NAME="${DB_DEV_DB_NAME:-dev_db}"
	DB_DEV_USER="${DB_DEV_USER:-dev_user}"
	DB_DEV_PASSWORD="${DB_DEV_PASSWORD:-dev_password}"
	DB_DEV_USER_HOST="${DB_DEV_USER_HOST:-localhost}"

	# Normalize DATABASE_TYPE to lowercase
	DATABASE_TYPE="$(printf '%s' "$DATABASE_TYPE" | tr '[:upper:]' '[:lower:]')"

	# Normalize boolean values for dev setup
	case "$(printf '%s' "$DB_DEV_SETUP" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			DB_DEV_SETUP=true
			;;
		0|false|no|n|off)
			DB_DEV_SETUP=false
			;;
		*)
			echo "Invalid DB_DEV_SETUP '$DB_DEV_SETUP'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	# Mirror unified DB_* values back to legacy names for compatibility.
	MYSQL_DEV_SETUP="$DB_DEV_SETUP"
	MYSQL_DEV_DB_NAME="$DB_DEV_DB_NAME"
	MYSQL_DEV_USER="$DB_DEV_USER"
	MYSQL_DEV_PASSWORD="$DB_DEV_PASSWORD"
	MYSQL_DEV_USER_HOST="$DB_DEV_USER_HOST"
	POSTGRES_DEV_SETUP="$DB_DEV_SETUP"
	POSTGRES_DEV_DB_NAME="$DB_DEV_DB_NAME"
	POSTGRES_DEV_USER="$DB_DEV_USER"
	POSTGRES_DEV_PASSWORD="$DB_DEV_PASSWORD"
	POSTGRES_DEV_USER_HOST="$DB_DEV_USER_HOST"

	export DATABASE_TYPE
	export MARIADB_VERSION
	export POSTGRESQL_VERSION
	export MONGODB_VERSION
	export DB_DEV_SETUP
	export DB_DEV_DB_NAME
	export DB_DEV_USER
	export DB_DEV_PASSWORD
	export DB_DEV_USER_HOST
	export MYSQL_DEV_SETUP
	export MYSQL_DEV_DB_NAME
	export MYSQL_DEV_USER
	export MYSQL_DEV_PASSWORD
	export MYSQL_DEV_USER_HOST
	export POSTGRES_DEV_SETUP
	export POSTGRES_DEV_DB_NAME
	export POSTGRES_DEV_USER
	export POSTGRES_DEV_PASSWORD
	export POSTGRES_DEV_USER_HOST
}

database_is_enabled() {
	[[ "$DATABASE_TYPE" != "none" ]]
}

validate_database_type() {
	case "$DATABASE_TYPE" in
		mysql|postgres|mongodb|none)
			return 0
			;;
		*)
			echo "Invalid DATABASE_TYPE '$DATABASE_TYPE'. Supported values: mysql, postgres, mongodb, none" >&2
			exit 1
			;;
	esac
}

validate_mariadb_version() {
	case "$MARIADB_VERSION" in
		10.5|10.6|10.7|10.8|10.9|10.10|10.11|11.0|11.1|11.2|11.3|11.4|11.5|11.6)
			return 0
			;;
		*)
			echo "Invalid MARIADB_VERSION '$MARIADB_VERSION'. Supported versions: 10.5-10.11, 11.0-11.6" >&2
			exit 1
			;;
	esac
}

validate_postgresql_version() {
	case "$POSTGRESQL_VERSION" in
		14|15|16|17)
			return 0
			;;
		*)
			echo "Invalid POSTGRESQL_VERSION '$POSTGRESQL_VERSION'. Supported versions: 14, 15, 16, 17" >&2
			exit 1
			;;
	esac
}

validate_mongodb_version() {
	case "$MONGODB_VERSION" in
		6.0|7.0|8.0)
			return 0
			;;
		*)
			echo "Invalid MONGODB_VERSION '$MONGODB_VERSION'. Supported versions: 6.0, 7.0, 8.0" >&2
			exit 1
			;;
	esac
}

mysql_dev_setup_is_enabled() {
	[[ "$DB_DEV_SETUP" == "true" ]]
}

postgres_dev_setup_is_enabled() {
	[[ "$DB_DEV_SETUP" == "true" ]]
}

db_dev_setup_is_enabled() {
	[[ "$DB_DEV_SETUP" == "true" ]]
}
