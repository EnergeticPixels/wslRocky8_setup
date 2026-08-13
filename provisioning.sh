#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_SAMPLE_PATH="$ROOT_DIR/.env.sample"
ENV_PATH="$ROOT_DIR/.env"
SCRIPTS_DIR="$ROOT_DIR/scripts"

BASE_PACKAGES=(
	ca-certificates
	apt-transport-https
	curl
	gnupg2
	lsb-release
	git
	wget
	build-essential
	libssl-dev
	ripgrep
)

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage:
  provisioning.sh init
  provisioning.sh wizard
  provisioning.sh config show
  provisioning.sh config get KEY
  provisioning.sh config set KEY=VALUE [KEY=VALUE...]
  provisioning.sh config unset KEY [KEY...]
  provisioning.sh validate
  provisioning.sh plan
  provisioning.sh run [--dry-run]
  provisioning.sh run --only <component> [--dry-run]
  provisioning.sh logs
  provisioning.sh help

Components for --only:
  tmux | vim | web | db | redis | java | node | python | ssh | gpg | git
EOF
}

require_env_file() {
	if [[ ! -f "$ENV_PATH" ]]; then
		fail "Missing .env at $ENV_PATH. Run './provisioning.sh init' first."
	fi
}

validate_env_key() {
	local key
	key="$1"

	if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
		fail "Invalid environment key '$key'."
	fi
}

quote_env_value() {
	local value
	value="$1"

	if [[ -z "$value" ]]; then
		printf ''
		return 0
	fi

	if [[ "$value" =~ ^[A-Za-z0-9_./:@,+%-]+$ ]]; then
		printf '%s' "$value"
		return 0
	fi

	value="${value//\'/\'\"\'\"\'}"
	printf "'%s'" "$value"
}

set_env_key() {
	local key value formatted_value temp_file
	key="$1"
	value="$2"

	validate_env_key "$key"
	require_env_file

	formatted_value="$(quote_env_value "$value")"
	temp_file="$(mktemp)"

	awk -v key="$key" -v value="$formatted_value" '
	BEGIN { found = 0 }
	$0 ~ "^[[:space:]]*" key "=" {
		if (found == 0) {
			print key "=" value
			found = 1
		}
		next
	}
	{ print }
	END {
		if (found == 0) {
			print key "=" value
		}
	}
	' "$ENV_PATH" > "$temp_file"

	mv "$temp_file" "$ENV_PATH"
}

unset_env_key() {
	local key temp_file
	key="$1"

	validate_env_key "$key"
	require_env_file

	temp_file="$(mktemp)"
	awk -v key="$key" '$0 !~ "^[[:space:]]*" key "=" { print }' "$ENV_PATH" > "$temp_file"
	mv "$temp_file" "$ENV_PATH"
}

get_env_key() {
	local key
	key="$1"
	validate_env_key "$key"
	require_env_file
	grep -E "^[[:space:]]*$key=" "$ENV_PATH" | head -n 1 || true
}

load_env_file() {
	require_env_file
	set -a
	# shellcheck disable=SC1090
	source "$ENV_PATH"
	set +a
}

parse_expiry_to_seconds_local() {
	local value num unit
	value="${1:-0}"

	if [[ "$value" =~ ^([0-9]+)([ymwdYMWD])$ ]]; then
		num="${BASH_REMATCH[1]}"
		unit="${BASH_REMATCH[2],,}"
		case "$unit" in
			y) echo $(( num * 365 * 86400 )) ;;
			m) echo $(( num * 30 * 86400 )) ;;
			w) echo $(( num * 7 * 86400 )) ;;
			d) echo $(( num * 86400 )) ;;
			*) echo 0 ;;
		esac
	elif [[ "$value" =~ ^[0-9]+$ ]]; then
		echo $(( value * 86400 ))
	else
		echo 0
	fi
}

normalize_bool_local() {
	local value normalized
	value="$1"
	normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

	case "$normalized" in
		1|true|yes|y|on)
			printf 'true'
			return 0
			;;
		0|false|no|n|off)
			printf 'false'
			return 0
			;;
		*)
			return 1
			;;
	esac
}

is_valid_local_base_domain() {
	local domain normalized
	domain="$1"
	normalized="$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"

	if [[ -z "$normalized" ]]; then
		return 1
	fi

	if [[ "$normalized" == *" "* || "$normalized" == *"*"* ]]; then
		return 1
	fi

	if [[ "$normalized" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.local$ ]]; then
		return 0
	fi

	return 1
}

init_env_file() {
	if [[ -f "$ENV_PATH" ]]; then
		log ".env already exists at $ENV_PATH"
		return 0
	fi

	if [[ ! -f "$ENV_SAMPLE_PATH" ]]; then
		fail "Missing .env.sample at $ENV_SAMPLE_PATH"
	fi

	cp "$ENV_SAMPLE_PATH" "$ENV_PATH"
	log "Created .env from .env.sample"
}

read_with_default() {
	local prompt default input
	prompt="$1"
	default="$2"

	read -r -p "$prompt [$default]: " input
	if [[ -z "$input" ]]; then
		printf '%s' "$default"
	else
		printf '%s' "$input"
	fi
}

read_optional() {
	local prompt input
	prompt="$1"

	read -r -p "$prompt (leave empty to skip): " input
	printf '%s' "$input"
}

read_bool() {
	local prompt default input normalized_default normalized
	prompt="$1"
	default="$2"
	normalized_default="$(printf '%s' "$default" | tr '[:upper:]' '[:lower:]')"

	while true; do
		read -r -p "$prompt [$normalized_default]: " input
		input="${input:-$normalized_default}"
		normalized="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

		case "$normalized" in
			1|true|yes|y|on)
				printf 'true'
				return 0
				;;
			0|false|no|n|off)
				printf 'false'
				return 0
				;;
			*)
				echo "Please enter true/false (or yes/no)."
				;;
		esac
	done
}

read_choice() {
	local prompt default allowed_csv input normalized allowed_token found
	local -a allowed_tokens
	prompt="$1"
	default="$2"
	allowed_csv="$3"
	normalized="$(printf '%s' "$default" | tr '[:upper:]' '[:lower:]')"

	while true; do
		read -r -p "$prompt [$default]: " input
		input="${input:-$default}"
		normalized="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
		found=0

		IFS=',' read -r -a allowed_tokens <<< "$allowed_csv"
		for allowed_token in "${allowed_tokens[@]}"; do
			if [[ "$normalized" == "$allowed_token" ]]; then
				found=1
				break
			fi
		done

		if [[ "$found" -eq 1 ]]; then
			printf '%s' "$normalized"
			return 0
		fi

		echo "Invalid value. Allowed: $allowed_csv"
	done
}

ensure_interactive_terminal() {
	if [[ ! -t 0 ]]; then
		fail "Wizard requires an interactive terminal."
	fi
}

wizard() {
	local value selected_web_server selected_database_type selected_java_mode git_name_default git_email_default gpg_exp_default ssh_exp_default
	local tmux_default web_server_default php_enable_default php_version_default php_baseline_default
	local php_extra_default php_strict_default php_db_mode_default database_type_default db_setup_default
	local mariadb_version_default postgresql_version_default mongodb_version_default
	local db_name_default db_user_default db_password_default db_host_default redis_enable_default
	local redis_version_default java_enable_default java_version_default java_mode_default java_distro_default
	local java_jar_default java_port_default java_args_default node_enable_default
	local node_default_version_default node_versions_default node_nvm_version_default node_global_packages_default
	local python_enable_default python_ds_default python_dev_mode_default
	local ssl_enable_default ssl_base_domain_default ssl_cert_expiry_default ssl_redirect_default ssl_enable_choice

	ensure_interactive_terminal
	init_env_file
	load_env_file
	log "Wizard starting with plain prompts."

	git_name_default="${GIT_NAME:-Elmer Humperdinck}"
	git_email_default="${GIT_EMAIL:-somebody@somewhere.us}"
	gpg_exp_default="${GPG_EXPIRATION:-1y}"
	ssh_exp_default="${SSH_KEY_EXPIRATION:-1y}"
	tmux_default="${TMUX_CONFIG_URL:-}"
	web_server_default="${WEB_SERVER:-apache}"
	ssl_enable_default="${WEB_SSL_ENABLE:-false}"
	ssl_base_domain_default="${WEB_SSL_BASE_DOMAIN:-app.local}"
	ssl_cert_expiry_default="${WEB_SSL_CERT_EXPIRY:-1y}"
	ssl_redirect_default="${WEB_SSL_FORCE_HTTPS_REDIRECT:-true}"
	php_enable_default="${PHP_ENABLE:-false}"
	php_version_default="${PHP_VERSION:-7.4}"
	php_baseline_default="${PHP_EXTENSIONS_BASELINE:-common}"
	php_extra_default="${PHP_EXTENSIONS_EXTRA:-}"
	php_strict_default="${PHP_EXTENSIONS_STRICT:-true}"
	php_db_mode_default="${PHP_DB_DRIVER_MODE:-auto}"
	database_type_default="${DATABASE_TYPE:-none}"
	mariadb_version_default="${MARIADB_VERSION:-10.5}"
	postgresql_version_default="${POSTGRESQL_VERSION:-17}"
	mongodb_version_default="${MONGODB_VERSION:-8.0}"
	db_setup_default="${DB_DEV_SETUP:-false}"
	db_name_default="${DB_DEV_DB_NAME:-dev_db}"
	db_user_default="${DB_DEV_USER:-dev_user}"
	db_password_default="${DB_DEV_PASSWORD:-dev_password}"
	db_host_default="${DB_DEV_USER_HOST:-localhost}"
	redis_enable_default="${REDIS_ENABLE:-false}"
	redis_version_default="${REDIS_VERSION:-7.0}"
	java_enable_default="${JAVA_ENABLE:-false}"
	java_version_default="${JAVA_VERSION:-8}"
	java_mode_default="${JAVA_SERVER_MODE:-tomcat}"
	java_distro_default="${JAVA_DISTRO:-temurin}"
	java_jar_default="${JAVA_APP_JAR_PATH:-}"
	java_port_default="${JAVA_APP_PORT:-8081}"
	java_args_default="${JAVA_APP_ARGS:-}"
	node_enable_default="${NODE_ENABLE:-false}"
	node_default_version_default="${NODE_DEFAULT_VERSION:-22}"
	node_versions_default="${NODE_VERSIONS:-22}"
	node_nvm_version_default="${NODE_NVM_VERSION:-v0.40.3}"
	node_global_packages_default="${NODE_GLOBAL_PACKAGES:-}"
	python_enable_default="${PYTHON_ENABLE:-false}"
	python_ds_default="${PYTHON_DATA_SCIENCE_STACK_ENABLE:-false}"
	python_dev_mode_default="${PYTHON_DEV_MODE:-none}"

	echo "=== Provisioning Wizard ==="

	value="$(read_with_default 'GIT_NAME' "$git_name_default")"
	set_env_key "GIT_NAME" "$value"
	value="$(read_with_default 'GIT_EMAIL' "$git_email_default")"
	set_env_key "GIT_EMAIL" "$value"
	value="$(read_with_default 'GPG_EXPIRATION' "$gpg_exp_default")"
	set_env_key "GPG_EXPIRATION" "$value"
	value="$(read_with_default 'SSH_KEY_EXPIRATION' "$ssh_exp_default")"
	set_env_key "SSH_KEY_EXPIRATION" "$value"

	if [[ -n "$tmux_default" ]]; then
		value="$(read_optional "TMUX_CONFIG_URL (raw gist URL, current: $tmux_default)")"
	else
		value="$(read_optional 'TMUX_CONFIG_URL (raw gist URL)')"
	fi
	if [[ -n "$value" ]]; then
		set_env_key "TMUX_CONFIG_URL" "$value"
	elif [[ -n "$tmux_default" ]]; then
		set_env_key "TMUX_CONFIG_URL" "$tmux_default"
	else
		unset_env_key "TMUX_CONFIG_URL"
	fi

	selected_web_server="$(read_choice 'WEB_SERVER (apache/nginx/skip)' "$web_server_default" 'apache,nginx,skip')"
	if [[ "$selected_web_server" == "skip" ]]; then
		unset_env_key "WEB_SERVER"
		set_env_key "WEB_SSL_ENABLE" "false"
		unset_env_key "WEB_SSL_BASE_DOMAIN"
		set_env_key "WEB_SSL_CERT_EXPIRY" "$ssl_cert_expiry_default"
		set_env_key "WEB_SSL_FORCE_HTTPS_REDIRECT" "$ssl_redirect_default"
	else
		set_env_key "WEB_SERVER" "$selected_web_server"
		value="$(read_bool 'WEB_SSL_ENABLE (true/false)' "$ssl_enable_default")"
		set_env_key "WEB_SSL_ENABLE" "$value"
		ssl_enable_choice="$value"
		set_env_key "WEB_SSL_CERT_EXPIRY" "$ssl_cert_expiry_default"
		value="$(read_bool 'WEB_SSL_FORCE_HTTPS_REDIRECT (true/false)' "$ssl_redirect_default")"
		set_env_key "WEB_SSL_FORCE_HTTPS_REDIRECT" "$value"
		if [[ "$ssl_enable_choice" == "true" ]]; then
			while true; do
				value="$(read_with_default 'WEB_SSL_BASE_DOMAIN (must end in .local, example: app.local)' "$ssl_base_domain_default")"
				if is_valid_local_base_domain "$value"; then
					break
				fi
				echo "Invalid WEB_SSL_BASE_DOMAIN. Use a base domain like app.local (must end in .local, no wildcard)."
			done
			set_env_key "WEB_SSL_BASE_DOMAIN" "$value"
		else
			unset_env_key "WEB_SSL_BASE_DOMAIN"
		fi
	fi

	if [[ "$selected_web_server" != "skip" ]]; then
		value="$(read_bool 'PHP_ENABLE (true/false)' "$php_enable_default")"
		set_env_key "PHP_ENABLE" "$value"
		if [[ "$value" == "true" ]]; then
			value="$(read_choice 'PHP_VERSION' "$php_version_default" '7.4,8.0,8.1,8.2,8.3')"
			set_env_key "PHP_VERSION" "$value"
			value="$(read_choice 'PHP_EXTENSIONS_BASELINE (common/none)' "$php_baseline_default" 'common,none')"
			set_env_key "PHP_EXTENSIONS_BASELINE" "$value"
			value="$(read_with_default 'PHP_EXTENSIONS_EXTRA (comma-separated)' "$php_extra_default")"
			set_env_key "PHP_EXTENSIONS_EXTRA" "$value"
			value="$(read_bool 'PHP_EXTENSIONS_STRICT (true/false)' "$php_strict_default")"
			set_env_key "PHP_EXTENSIONS_STRICT" "$value"
			value="$(read_choice 'PHP_DB_DRIVER_MODE (auto/mysql/postgres/none)' "$php_db_mode_default" 'auto,mysql,postgres,none')"
			set_env_key "PHP_DB_DRIVER_MODE" "$value"
		fi
	fi

	value="$(read_bool 'JAVA_ENABLE (true/false)' "$java_enable_default")"
	set_env_key "JAVA_ENABLE" "$value"
	if [[ "$value" == "true" ]]; then
		value="$(read_with_default 'JAVA_VERSION' "$java_version_default")"
		set_env_key "JAVA_VERSION" "$value"
		value="$(read_choice 'JAVA_SERVER_MODE (tomcat/jar)' "$java_mode_default" 'tomcat,jar')"
		selected_java_mode="$value"
		set_env_key "JAVA_SERVER_MODE" "$selected_java_mode"
		value="$(read_choice 'JAVA_DISTRO (temurin/openjdk)' "$java_distro_default" 'temurin,openjdk')"
		set_env_key "JAVA_DISTRO" "$value"
		if [[ "$selected_java_mode" == "jar" ]]; then
			value="$(read_with_default 'JAVA_APP_JAR_PATH' "$java_jar_default")"
			set_env_key "JAVA_APP_JAR_PATH" "$value"
			value="$(read_with_default 'JAVA_APP_PORT' "$java_port_default")"
			set_env_key "JAVA_APP_PORT" "$value"
			value="$(read_with_default 'JAVA_APP_ARGS' "$java_args_default")"
			set_env_key "JAVA_APP_ARGS" "$value"
		fi
	fi

	value="$(read_bool 'NODE_ENABLE (true/false)' "$node_enable_default")"
	set_env_key "NODE_ENABLE" "$value"
	if [[ "$value" == "true" ]]; then
		value="$(read_with_default 'NODE_DEFAULT_VERSION' "$node_default_version_default")"
		set_env_key "NODE_DEFAULT_VERSION" "$value"
		value="$(read_with_default 'NODE_VERSIONS (comma-separated)' "$node_versions_default")"
		set_env_key "NODE_VERSIONS" "$value"
		value="$(read_with_default 'NODE_NVM_VERSION' "$node_nvm_version_default")"
		set_env_key "NODE_NVM_VERSION" "$value"
		value="$(read_with_default 'NODE_GLOBAL_PACKAGES (comma-separated)' "$node_global_packages_default")"
		set_env_key "NODE_GLOBAL_PACKAGES" "$value"
	fi

	value="$(read_bool 'PYTHON_ENABLE (true/false)' "$python_enable_default")"
	set_env_key "PYTHON_ENABLE" "$value"
	if [[ "$value" == "true" ]]; then
		value="$(read_bool 'PYTHON_DATA_SCIENCE_STACK_ENABLE (true/false)' "$python_ds_default")"
		set_env_key "PYTHON_DATA_SCIENCE_STACK_ENABLE" "$value"
		value="$(read_choice 'PYTHON_DEV_MODE (none/flask/reflex/both)' "$python_dev_mode_default" 'none,flask,reflex,both')"
		set_env_key "PYTHON_DEV_MODE" "$value"
	fi

	selected_database_type="$(read_choice 'DATABASE_TYPE (none/mysql/postgres/mongodb)' "$database_type_default" 'none,mysql,postgres,mongodb')"
	set_env_key "DATABASE_TYPE" "$selected_database_type"
	case "$selected_database_type" in
		mysql)
			value="$(read_with_default 'MARIADB_VERSION' "$mariadb_version_default")"
			set_env_key "MARIADB_VERSION" "$value"
			;;
		postgres)
			value="$(read_with_default 'POSTGRESQL_VERSION' "$postgresql_version_default")"
			set_env_key "POSTGRESQL_VERSION" "$value"
			;;
		mongodb)
			value="$(read_with_default 'MONGODB_VERSION' "$mongodb_version_default")"
			set_env_key "MONGODB_VERSION" "$value"
			;;
	esac

	if [[ "$selected_database_type" != "none" ]]; then
		value="$(read_bool 'DB_DEV_SETUP (true/false)' "$db_setup_default")"
		set_env_key "DB_DEV_SETUP" "$value"
		if [[ "$value" == "true" ]]; then
			value="$(read_with_default 'DB_DEV_DB_NAME' "$db_name_default")"
			set_env_key "DB_DEV_DB_NAME" "$value"
			value="$(read_with_default 'DB_DEV_USER' "$db_user_default")"
			set_env_key "DB_DEV_USER" "$value"
			value="$(read_with_default 'DB_DEV_PASSWORD' "$db_password_default")"
			set_env_key "DB_DEV_PASSWORD" "$value"
			value="$(read_with_default 'DB_DEV_USER_HOST' "$db_host_default")"
			set_env_key "DB_DEV_USER_HOST" "$value"
		fi
	else
		set_env_key "DB_DEV_SETUP" "false"
	fi

	value="$(read_bool 'REDIS_ENABLE (true/false)' "$redis_enable_default")"
	set_env_key "REDIS_ENABLE" "$value"
	if [[ "$value" == "true" ]]; then
		value="$(read_with_default 'REDIS_VERSION' "$redis_version_default")"
		set_env_key "REDIS_VERSION" "$value"
	else
		set_env_key "REDIS_VERSION" "$redis_version_default"
	fi

	echo ""
	log "Wizard configuration saved."
}

wizard_command() {
	local proceed

	while true; do
		wizard
		echo ""
		plan_command
		echo ""
		proceed="$(read_bool 'Proceed with provisioning?' 'true')"

		if [[ "$proceed" == "true" ]]; then
			if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
				run_command
			else
				sudo bash "$ROOT_DIR/provisioning.sh" run
			fi
			return 0
		fi

		log "Plan rejected. Restarting wizard."
		echo ""
	done
}

validate_node_env() {
	local node_enable node_default_version node_versions node_nvm_version token
	local -a node_tokens

	load_env_file

	node_enable="${NODE_ENABLE:-false}"
	node_default_version="${NODE_DEFAULT_VERSION:-22}"
	node_versions="${NODE_VERSIONS:-22}"
	node_nvm_version="${NODE_NVM_VERSION:-v0.40.3}"

	case "$(printf '%s' "$node_enable" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on) node_enable=true ;;
		0|false|no|n|off) node_enable=false ;;
		*) fail "Invalid NODE_ENABLE '$node_enable'. Supported values: true/false" ;;
	esac

	if [[ "$node_enable" != "true" ]]; then
		return 0
	fi

	if [[ ! "$node_nvm_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		fail "Invalid NODE_NVM_VERSION '$node_nvm_version'. Expected format like v0.40.3"
	fi

	if [[ ! "$node_default_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
		fail "Invalid NODE_DEFAULT_VERSION '$node_default_version'."
	fi

	IFS=',' read -r -a node_tokens <<< "$node_versions"
	if (( ${#node_tokens[@]} == 0 )); then
		fail "NODE_VERSIONS must include at least one value."
	fi

	for token in "${node_tokens[@]}"; do
		token="${token#"${token%%[![:space:]]*}"}"
		token="${token%"${token##*[![:space:]]}"}"
		if [[ -z "$token" ]]; then
			continue
		fi
		if [[ ! "$token" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
			fail "Invalid Node version '$token' in NODE_VERSIONS."
		fi
	done
}

validate_core_identity_env() {
	local gpg_exp ssh_exp seconds
	load_env_file

	if [[ -z "${GIT_NAME:-}" ]]; then
		fail "GIT_NAME is required."
	fi
	if [[ -z "${GIT_EMAIL:-}" ]]; then
		fail "GIT_EMAIL is required."
	fi

	gpg_exp="${GPG_EXPIRATION:-1y}"
	ssh_exp="${SSH_KEY_EXPIRATION:-$gpg_exp}"

	seconds="$(parse_expiry_to_seconds_local "$gpg_exp")"
	if [[ "$seconds" -le 0 ]]; then
		fail "Invalid GPG_EXPIRATION '$gpg_exp'."
	fi

	seconds="$(parse_expiry_to_seconds_local "$ssh_exp")"
	if [[ "$seconds" -le 0 ]]; then
		fail "Invalid SSH_KEY_EXPIRATION '$ssh_exp'."
	fi
}

validate_web_ssl_env() {
	local web_server web_ssl_enable web_ssl_base_domain web_ssl_cert_expiry web_ssl_force_https_redirect normalized_ssl normalized_redirect

	web_server="${WEB_SERVER:-}"
	web_ssl_enable="${WEB_SSL_ENABLE:-false}"
	web_ssl_base_domain="${WEB_SSL_BASE_DOMAIN:-}"
	web_ssl_cert_expiry="${WEB_SSL_CERT_EXPIRY:-1y}"
	web_ssl_force_https_redirect="${WEB_SSL_FORCE_HTTPS_REDIRECT:-true}"

	if ! normalized_ssl="$(normalize_bool_local "$web_ssl_enable")"; then
		fail "Invalid WEB_SSL_ENABLE '$web_ssl_enable'. Supported values: true/false"
	fi
	WEB_SSL_ENABLE="$normalized_ssl"

	if ! normalized_redirect="$(normalize_bool_local "$web_ssl_force_https_redirect")"; then
		fail "Invalid WEB_SSL_FORCE_HTTPS_REDIRECT '$web_ssl_force_https_redirect'. Supported values: true/false"
	fi
	WEB_SSL_FORCE_HTTPS_REDIRECT="$normalized_redirect"

	if [[ "$WEB_SSL_ENABLE" == "true" ]]; then
		if [[ -z "$web_server" ]]; then
			fail "WEB_SSL_ENABLE=true requires WEB_SERVER to be set to apache or nginx."
		fi

		if ! is_valid_local_base_domain "$web_ssl_base_domain"; then
			fail "Invalid WEB_SSL_BASE_DOMAIN '$web_ssl_base_domain'. Use a base domain like app.local (must end in .local, no wildcard)."
		fi

		if [[ "$web_ssl_cert_expiry" != "1y" ]]; then
			fail "WEB_SSL_CERT_EXPIRY must be '1y' for this phase. Current value: '$web_ssl_cert_expiry'."
		fi
	fi
}

validate_with_libs() {
	validate_core_identity_env

	# shellcheck source=/dev/null
	source "$SCRIPTS_DIR/lib/php_web.sh"
	load_web_stack_env
	if [[ -n "${WEB_SERVER:-}" ]]; then
		case "$WEB_SERVER" in
			apache|nginx) ;;
			*) fail "Invalid WEB_SERVER '$WEB_SERVER'. Supported values: apache, nginx" ;;
		esac
	fi
	validate_web_ssl_env
	if php_is_enabled; then
		validate_php_version
		validate_php_extensions_baseline
	fi

	# shellcheck source=/dev/null
	source "$SCRIPTS_DIR/lib/database.sh"
	load_database_env
	validate_database_type
	case "$DATABASE_TYPE" in
		mysql) validate_mariadb_version ;;
		postgres) validate_postgresql_version ;;
		mongodb) validate_mongodb_version ;;
	esac

	# shellcheck source=/dev/null
	source "$SCRIPTS_DIR/lib/redis.sh"
	load_redis_env
	validate_redis_version

	# shellcheck source=/dev/null
	source "$SCRIPTS_DIR/lib/java_stack.sh"
	load_java_stack_env
	if java_is_enabled; then
		validate_java_server_mode
		validate_java_version
		validate_java_distro
		if [[ "$JAVA_SERVER_MODE" == "jar" ]]; then
			validate_jar_inputs
		fi
	fi

	# shellcheck source=/dev/null
	source "$SCRIPTS_DIR/lib/python.sh"
	load_python_env
	validate_python_dev_mode

	validate_node_env
}

validate_command() {
	require_env_file
	validate_with_libs
	log "Validation succeeded."
}

plan_command() {
	local web_summary web_ssl_enable web_ssl_base_domain web_ssl_redirect

	require_env_file
	validate_with_libs
	load_env_file

	web_ssl_enable="${WEB_SSL_ENABLE:-false}"
	web_ssl_base_domain="${WEB_SSL_BASE_DOMAIN:-unset}"
	web_ssl_redirect="${WEB_SSL_FORCE_HTTPS_REDIRECT:-true}"

	if [[ -n "${WEB_SERVER:-}" ]]; then
		web_summary="will run (WEB_SERVER=${WEB_SERVER}"
		if [[ "$web_ssl_enable" == "true" ]]; then
			web_summary+="; SSL=true; base_domain=${web_ssl_base_domain}; force_https_redirect=${web_ssl_redirect}; ssl_execution=active)"
		else
			web_summary+="; SSL=false)"
		fi
	else
		web_summary="skip (WEB_SERVER not set)"
	fi

	echo "Provisioning plan:"
	echo "- tmux: $(if [[ -n "${TMUX_CONFIG_URL:-}" ]]; then echo "will run (TMUX_CONFIG_URL set)"; else echo "skip (TMUX_CONFIG_URL not set)"; fi)"
	echo "- vim: will run"
	echo "- web: $web_summary"
	echo "- database: $(if [[ "${DATABASE_TYPE:-none}" != "none" ]]; then echo "will run (DATABASE_TYPE=${DATABASE_TYPE})"; else echo "skip (DATABASE_TYPE=none)"; fi)"
	echo "- redis: $(if [[ "${REDIS_ENABLE:-false}" == "true" ]]; then echo "will run"; else echo "skip (REDIS_ENABLE=false)"; fi)"
	echo "- java: $(if [[ "${JAVA_ENABLE:-false}" == "true" ]]; then echo "will run (mode=${JAVA_SERVER_MODE:-tomcat})"; else echo "skip (JAVA_ENABLE=false)"; fi)"
	echo "- node: $(if [[ "${NODE_ENABLE:-false}" == "true" ]]; then echo "will run (default=${NODE_DEFAULT_VERSION:-22})"; else echo "skip (NODE_ENABLE=false)"; fi)"
	echo "- python: $(if [[ "${PYTHON_ENABLE:-false}" == "true" ]]; then echo "will run (mode=${PYTHON_DEV_MODE:-none})"; else echo "skip (PYTHON_ENABLE=false)"; fi)"
	echo "- ssh/gpg/git: will run"
}

require_root() {
	if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
		fail "This command must run as root. Use: sudo bash provisioning.sh ..."
	fi
}

bootstrap_env_file() {
	if [[ ! -f "$ENV_PATH" && -f "$ENV_SAMPLE_PATH" ]]; then
		cp "$ENV_SAMPLE_PATH" "$ENV_PATH"
		log "Created $ENV_PATH from .env.sample. Update values before key generation if needed."
	fi
}

setup_logging() {
	local target_user target_home log_dir timestamp log_file_name latest_log_path

	target_user="${SUDO_USER:-}"
	target_home="$HOME"

	if [[ -n "$target_user" ]]; then
		target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
	fi

	if [[ -z "$target_home" ]]; then
		target_home="$HOME"
	fi

	log_dir="$target_home/.debian_build/logs"
	timestamp="$(date +'%Y%m%d_%H%M%S')"
	LOG_FILE="$log_dir/provision_${timestamp}.log"
	log_file_name="$(basename "$LOG_FILE")"
	latest_log_path="$log_dir/latest.log"

	mkdir -p "$log_dir"
	touch "$LOG_FILE"
	ln -sfn "$log_file_name" "$latest_log_path"

	if [[ "${EUID:-$(id -u)}" -eq 0 && -n "$target_user" ]]; then
		chown "$target_user:$target_user" "$log_dir" "$LOG_FILE" "$latest_log_path" 2>/dev/null || true
	fi

	exec > >(tee -a "$LOG_FILE") 2>&1
	log "Writing detailed log to $LOG_FILE"
}

show_public_keys() {
	local target_user target_home gpg_email ssh_pub

	target_user="${SUDO_USER:-}"
	target_home="$HOME"

	if [[ -n "$target_user" ]]; then
		target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
		[[ -z "$target_home" ]] && target_home="$HOME"
	fi

	load_env_file
	gpg_email="${GIT_EMAIL:-}"
	ssh_pub="$target_home/.ssh/id_github.pub"

	echo ""
	echo "======================================================="
	echo "  PROVISIONING COMPLETE - PUBLIC KEYS"
	echo "  Copy and paste these into GitHub Settings."
	echo "======================================================="

	echo ""
	echo "--- GPG PUBLIC KEY (GitHub Settings > SSH and GPG keys > New GPG key) ---"
	if [[ -n "$gpg_email" ]] && gpg --armor --export "$gpg_email" 2>/dev/null | grep -q 'BEGIN PGP'; then
		gpg --armor --export "$gpg_email"
	else
		echo "(No GPG key found for $gpg_email)"
	fi

	echo ""
	echo "--- SSH PUBLIC KEY (GitHub Settings > SSH and GPG keys > New SSH key) ---"
	if [[ -f "$ssh_pub" ]]; then
		cat "$ssh_pub"
	else
		echo "(No SSH public key found at $ssh_pub)"
	fi

	echo ""
	echo "======================================================="
	read -rp "Press [Enter] once you have added the keys above to GitHub..."
	echo "======================================================="
	echo ""
}

run_core_script() {
	local script_path script_name
	script_path="$1"
	script_name="$(basename "$script_path")"

	if [[ ! -f "$script_path" ]]; then
		fail "Missing script: $script_path"
	fi

	log "Running $script_name"

	if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
		case "$script_name" in
			ssh_gen.sh|gpg_gen.sh|git-config.sh|node_install.sh)
				sudo -u "$SUDO_USER" -H bash "$script_path"
				return 0
				;;
		esac
	fi

	if [[ "$script_name" == "tmux_install.sh" ]]; then
		PROVISIONING_NONINTERACTIVE=true bash "$script_path"
		return 0
	fi

	bash "$script_path"
}

run_only_component() {
	local component dry_run script_path
	component="$1"
	dry_run="$2"

	case "$component" in
		tmux) script_path="$SCRIPTS_DIR/tmux_install.sh" ;;
		vim) script_path="$SCRIPTS_DIR/vim_install.sh" ;;
		web) script_path="$SCRIPTS_DIR/web_server_install.sh" ;;
		db) script_path="$SCRIPTS_DIR/database_install.sh" ;;
		redis) script_path="$SCRIPTS_DIR/redis_install.sh" ;;
		java) script_path="$SCRIPTS_DIR/java_install.sh" ;;
		node) script_path="$SCRIPTS_DIR/node_install.sh" ;;
		python) script_path="$SCRIPTS_DIR/python_install.sh" ;;
		ssh) script_path="$SCRIPTS_DIR/ssh_gen.sh" ;;
		gpg) script_path="$SCRIPTS_DIR/gpg_gen.sh" ;;
		git) script_path="$SCRIPTS_DIR/git-config.sh" ;;
		*) fail "Unknown component '$component'." ;;
	esac

	if [[ "$dry_run" == "true" ]]; then
		echo "Would run: $script_path"
		return 0
	fi

	run_core_script "$script_path"
}

run_full_provisioning() {
	local keys_changed_flag

	export DEBIAN_FRONTEND=noninteractive
	setup_logging

	log "Starting Debian provisioning"
	apt-get update
	# apt-get dist-upgrade -y
	apt-get install -y "${BASE_PACKAGES[@]}"

	bootstrap_env_file
	log "Starting multiplexer setup (tmux)"
	run_core_script "$SCRIPTS_DIR/tmux_install.sh"
	log "Completed multiplexer setup (tmux)"
	log "Starting editor setup (vim)"
	run_core_script "$SCRIPTS_DIR/vim_install.sh"
	log "Completed editor setup (vim)"
	log "Starting web server setup"
	run_core_script "$SCRIPTS_DIR/web_server_install.sh"
	log "Completed web server setup"
	log "Starting database setup"
	run_core_script "$SCRIPTS_DIR/database_install.sh"
	log "Completed database setup"
	log "Starting Redis cache setup"
	run_core_script "$SCRIPTS_DIR/redis_install.sh"
	log "Completed Redis cache setup"
	log "Starting Java server setup"
	run_core_script "$SCRIPTS_DIR/java_install.sh"
	log "Completed Java server setup"
	log "Starting Node.js setup"
	run_core_script "$SCRIPTS_DIR/node_install.sh"
	log "Completed Node.js setup"
	log "Starting Python setup"
	run_core_script "$SCRIPTS_DIR/python_install.sh"
	log "Completed Python setup"

	# Export a temp file path so child key scripts can signal that keys changed.
	keys_changed_flag="$(mktemp)"
	KEYS_CHANGED_FLAG="$keys_changed_flag"
	export KEYS_CHANGED_FLAG
	rm -f "$KEYS_CHANGED_FLAG"

	run_core_script "$SCRIPTS_DIR/ssh_gen.sh"
	run_core_script "$SCRIPTS_DIR/gpg_gen.sh"
	run_core_script "$SCRIPTS_DIR/git-config.sh"

	if [[ -f "$KEYS_CHANGED_FLAG" ]]; then
		rm -f "$KEYS_CHANGED_FLAG"
		show_public_keys
	else
		log "SSH and GPG keys unchanged; skipping public key display."
	fi

	log "Provisioning complete"
}

run_command() {
	local only_component="" dry_run=false arg
	require_env_file
	validate_with_libs

	while (($# > 0)); do
		arg="$1"
		case "$arg" in
			--only)
				shift
				[[ $# -gt 0 ]] || fail "Missing component after --only"
				only_component="$1"
				;;
			--dry-run)
				dry_run=true
				;;
			*)
				fail "Unknown argument '$arg' for run command."
				;;
		esac
		shift
	done

	require_root

	if [[ "$dry_run" == "true" ]]; then
		log "Dry run enabled."
	fi

	if [[ -n "$only_component" ]]; then
		run_only_component "$only_component" "$dry_run"
		return 0
	fi

	if [[ "$dry_run" == "true" ]]; then
		echo "Would run full provisioning via: $ROOT_DIR/provisioning.sh run"
		return 0
	fi

	PROVISIONING_NONINTERACTIVE=true run_full_provisioning
}

logs_command() {
	local target_user target_home log_path

	target_user="${SUDO_USER:-${USER:-}}"
	target_home="$HOME"

	if [[ -n "$target_user" ]]; then
		target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
		if [[ -z "$target_home" ]]; then
			target_home="$HOME"
		fi
	fi

	log_path="$target_home/.debian_build/logs/latest.log"
	if [[ ! -f "$log_path" ]]; then
		fail "No log found at $log_path"
	fi

	tail -n 120 "$log_path"
}

config_command() {
	local subcommand key_value_pair key value key_name
	subcommand="${1:-}"
	shift || true

	case "$subcommand" in
		show)
			require_env_file
			cat "$ENV_PATH"
			;;
		get)
			key_name="${1:-}"
			[[ -n "$key_name" ]] || fail "Missing key for config get."
			get_env_key "$key_name"
			;;
		set)
			(($# > 0)) || fail "Provide at least one KEY=VALUE pair."
			for key_value_pair in "$@"; do
				if [[ "$key_value_pair" != *=* ]]; then
					fail "Invalid assignment '$key_value_pair'. Expected KEY=VALUE."
				fi
				key="${key_value_pair%%=*}"
				value="${key_value_pair#*=}"
				set_env_key "$key" "$value"
			done
			;;
		unset)
			(($# > 0)) || fail "Provide at least one key to unset."
			for key_name in "$@"; do
				unset_env_key "$key_name"
			done
			;;
		*)
			fail "Unknown config subcommand '$subcommand'."
			;;
	esac
}

main() {
	local command
	command="${1:-help}"
	shift || true

	case "$command" in
		init) init_env_file ;;
		wizard) wizard_command ;;
		config) config_command "$@" ;;
		validate) validate_command ;;
		plan) plan_command ;;
		run) run_command "$@" ;;
		logs) logs_command ;;
		help|-h|--help) usage ;;
		*) fail "Unknown command '$command'. Run './provisioning.sh help'." ;;
	esac
}

main "$@"
