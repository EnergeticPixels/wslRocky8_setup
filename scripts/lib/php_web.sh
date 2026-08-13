#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

load_web_stack_env() {
	local script_dir env_file
	script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	env_file="$script_dir/../../.env"

	if [[ -f "$env_file" ]]; then
		# shellcheck source=/dev/null
		source "$env_file"
	fi

	# Backward compatibility for lowercase key names.
	if [[ -z "${WEB_SERVER:-}" && -n "${web_server:-}" ]]; then
		WEB_SERVER="$web_server"
	fi
	if [[ -z "${PHP_ENABLE:-}" && -n "${php_enable:-}" ]]; then
		PHP_ENABLE="$php_enable"
	fi
	if [[ -z "${PHP_VERSION:-}" && -n "${php_version:-}" ]]; then
		PHP_VERSION="$php_version"
	fi
	if [[ -z "${PHP_EXTENSIONS_BASELINE:-}" && -n "${php_extensions_baseline:-}" ]]; then
		PHP_EXTENSIONS_BASELINE="$php_extensions_baseline"
	fi
	if [[ -z "${PHP_EXTENSIONS_EXTRA:-}" && -n "${php_extensions_extra:-}" ]]; then
		PHP_EXTENSIONS_EXTRA="$php_extensions_extra"
	fi
	if [[ -z "${PHP_EXTENSIONS_STRICT:-}" && -n "${php_extensions_strict:-}" ]]; then
		PHP_EXTENSIONS_STRICT="$php_extensions_strict"
	fi
	if [[ -z "${DATABASE_TYPE:-}" && -n "${database_type:-}" ]]; then
		DATABASE_TYPE="$database_type"
	fi
	if [[ -z "${PHP_DB_DRIVER_MODE:-}" && -n "${php_db_driver_mode:-}" ]]; then
		PHP_DB_DRIVER_MODE="$php_db_driver_mode"
	fi
	if [[ -z "${WEB_SSL_ENABLE:-}" && -n "${web_ssl_enable:-}" ]]; then
		WEB_SSL_ENABLE="$web_ssl_enable"
	fi
	if [[ -z "${WEB_SSL_BASE_DOMAIN:-}" && -n "${web_ssl_base_domain:-}" ]]; then
		WEB_SSL_BASE_DOMAIN="$web_ssl_base_domain"
	fi
	if [[ -z "${WEB_SSL_CERT_EXPIRY:-}" && -n "${web_ssl_cert_expiry:-}" ]]; then
		WEB_SSL_CERT_EXPIRY="$web_ssl_cert_expiry"
	fi
	if [[ -z "${WEB_SSL_FORCE_HTTPS_REDIRECT:-}" && -n "${web_ssl_force_https_redirect:-}" ]]; then
		WEB_SSL_FORCE_HTTPS_REDIRECT="$web_ssl_force_https_redirect"
	fi

	PHP_ENABLE="${PHP_ENABLE:-false}"
	PHP_VERSION="${PHP_VERSION:-7.4}"
	PHP_EXTENSIONS_BASELINE="${PHP_EXTENSIONS_BASELINE:-common}"
	PHP_EXTENSIONS_EXTRA="${PHP_EXTENSIONS_EXTRA:-}"
	PHP_EXTENSIONS_STRICT="${PHP_EXTENSIONS_STRICT:-true}"
	DATABASE_TYPE="${DATABASE_TYPE:-none}"
	PHP_DB_DRIVER_MODE="${PHP_DB_DRIVER_MODE:-auto}"
	WEB_SSL_ENABLE="${WEB_SSL_ENABLE:-false}"
	WEB_SSL_BASE_DOMAIN="${WEB_SSL_BASE_DOMAIN:-app.local}"
	WEB_SSL_CERT_EXPIRY="${WEB_SSL_CERT_EXPIRY:-1y}"
	WEB_SSL_FORCE_HTTPS_REDIRECT="${WEB_SSL_FORCE_HTTPS_REDIRECT:-true}"

	case "$(printf '%s' "$PHP_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			PHP_ENABLE=true
			;;
		0|false|no|n|off)
			PHP_ENABLE=false
			;;
		*)
			echo "Invalid PHP_ENABLE '$PHP_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	case "$(printf '%s' "$PHP_EXTENSIONS_STRICT" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			PHP_EXTENSIONS_STRICT=true
			;;
		0|false|no|n|off)
			PHP_EXTENSIONS_STRICT=false
			;;
		*)
			echo "Invalid PHP_EXTENSIONS_STRICT '$PHP_EXTENSIONS_STRICT'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	case "$(printf '%s' "$WEB_SSL_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			WEB_SSL_ENABLE=true
			;;
		0|false|no|n|off)
			WEB_SSL_ENABLE=false
			;;
		*)
			echo "Invalid WEB_SSL_ENABLE '$WEB_SSL_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	case "$(printf '%s' "$WEB_SSL_FORCE_HTTPS_REDIRECT" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			WEB_SSL_FORCE_HTTPS_REDIRECT=true
			;;
		0|false|no|n|off)
			WEB_SSL_FORCE_HTTPS_REDIRECT=false
			;;
		*)
			echo "Invalid WEB_SSL_FORCE_HTTPS_REDIRECT '$WEB_SSL_FORCE_HTTPS_REDIRECT'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	DATABASE_TYPE="$(printf '%s' "$DATABASE_TYPE" | tr '[:upper:]' '[:lower:]')"
	PHP_DB_DRIVER_MODE="$(printf '%s' "$PHP_DB_DRIVER_MODE" | tr '[:upper:]' '[:lower:]')"
	WEB_SSL_BASE_DOMAIN="$(printf '%s' "$WEB_SSL_BASE_DOMAIN" | tr '[:upper:]' '[:lower:]')"

	case "$PHP_DB_DRIVER_MODE" in
		auto|none|mysql|postgres)
			;;
		*)
			echo "Invalid PHP_DB_DRIVER_MODE '$PHP_DB_DRIVER_MODE'. Supported values: auto, none, mysql, postgres" >&2
			exit 1
			;;
	esac

	export WEB_SERVER
	export PHP_ENABLE
	export PHP_VERSION
	export PHP_EXTENSIONS_BASELINE
	export PHP_EXTENSIONS_EXTRA
	export PHP_EXTENSIONS_STRICT
	export DATABASE_TYPE
	export PHP_DB_DRIVER_MODE
	export WEB_SSL_ENABLE
	export WEB_SSL_BASE_DOMAIN
	export WEB_SSL_CERT_EXPIRY
	export WEB_SSL_FORCE_HTTPS_REDIRECT
}

web_ssl_is_enabled() {
	[[ "$WEB_SSL_ENABLE" == "true" ]]
}

web_ssl_force_https_redirect_is_enabled() {
	[[ "$WEB_SSL_FORCE_HTTPS_REDIRECT" == "true" ]]
}

validate_php_version() {
	case "$PHP_VERSION" in
		7.4|8.0|8.1|8.2|8.3)
			return 0
			;;
		*)
			echo "Invalid PHP_VERSION '$PHP_VERSION'. Supported values: 7.4, 8.0, 8.1, 8.2, 8.3" >&2
			exit 1
			;;
	esac
}

validate_php_extensions_baseline() {
	case "$PHP_EXTENSIONS_BASELINE" in
		common|none)
			return 0
			;;
		*)
			echo "Invalid PHP_EXTENSIONS_BASELINE '$PHP_EXTENSIONS_BASELINE'. Supported values: common, none" >&2
			exit 1
			;;
	esac
}

validate_php_extension_name() {
	local extension_name
	extension_name="$1"

	if [[ ! "$extension_name" =~ ^[a-z0-9_+-]+$ ]]; then
		echo "Invalid PHP extension name '$extension_name'. Use lowercase letters, numbers, underscores, plus, or hyphen." >&2
		exit 1
	fi
}

get_php_baseline_extensions() {
	case "$PHP_EXTENSIONS_BASELINE" in
		common)
			echo "mbstring xml curl zip intl gd bcmath opcache readline"
			;;
		none)
			echo ""
			;;
	esac
}

get_php_database_driver_extensions() {
	local effective_mode
	effective_mode="$(get_effective_php_db_driver_mode)"

	case "$effective_mode" in
		mysql)
			echo "mysql"
			;;
		postgres)
			echo "pgsql"
			;;
		none)
			echo ""
			;;
	esac
}

get_effective_php_db_driver_mode() {
	if [[ "$PHP_DB_DRIVER_MODE" != "auto" ]]; then
		printf '%s' "$PHP_DB_DRIVER_MODE"
		return 0
	fi

	case "$DATABASE_TYPE" in
		mysql)
			echo "mysql"
			;;
		postgres)
			echo "postgres"
			;;
		*)
			echo "none"
			;;
	esac
}

trim_whitespace() {
	local input
	input="$1"

	input="${input#"${input%%[![:space:]]*}"}"
	input="${input%"${input##*[![:space:]]}"}"
	printf '%s' "$input"
}

build_php_extension_package_list() {
	local baseline_names db_driver_names baseline_name db_driver_name extra_name candidate extension_package
	local -a baseline_array extra_array combined
	declare -A seen=()

	validate_php_extensions_baseline

	baseline_names="$(get_php_baseline_extensions)"
	read -r -a baseline_array <<< "$baseline_names"
	db_driver_names="$(get_php_database_driver_extensions)"

	for baseline_name in "${baseline_array[@]}"; do
		if [[ -n "$baseline_name" ]]; then
			combined+=("$baseline_name")
		fi
	done

	for db_driver_name in $db_driver_names; do
		if [[ -n "$db_driver_name" ]]; then
			combined+=("$db_driver_name")
		fi
	done

	if [[ -n "$PHP_EXTENSIONS_EXTRA" ]]; then
		IFS=',' read -r -a extra_array <<< "$PHP_EXTENSIONS_EXTRA"
		for extra_name in "${extra_array[@]}"; do
			candidate="$(trim_whitespace "$extra_name")"
			if [[ -n "$candidate" ]]; then
				combined+=("$candidate")
			fi
		done
	fi

	PHP_EXTENSION_NAMES=()
	PHP_EXTENSION_PACKAGES=()

	for candidate in "${combined[@]}"; do
		validate_php_extension_name "$candidate"
		if [[ -z "${seen[$candidate]:-}" ]]; then
			seen[$candidate]=1
			PHP_EXTENSION_NAMES+=("$candidate")
			extension_package="php${PHP_VERSION}-${candidate}"
			PHP_EXTENSION_PACKAGES+=("$extension_package")
		fi
	done
}

filter_php_extension_packages_by_availability() {
	local package_name candidate extension_name
	local -a installable_packages=() installable_extensions=() missing_packages=() missing_extensions=()

	for package_name in "${PHP_EXTENSION_PACKAGES[@]}"; do
		candidate="$(apt-cache policy "$package_name" | awk '/Candidate:/ {print $2}')"
		extension_name="${package_name#php${PHP_VERSION}-}"

		if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
			missing_packages+=("$package_name")
			missing_extensions+=("$extension_name")
		else
			installable_packages+=("$package_name")
			installable_extensions+=("$extension_name")
		fi
	done

	if (( ${#missing_packages[@]} > 0 )); then
		if [[ "$PHP_EXTENSIONS_STRICT" == "true" ]]; then
			echo "Requested PHP extension packages are unavailable for PHP_VERSION=$PHP_VERSION: ${missing_packages[*]}" >&2
			echo "Adjust PHP_EXTENSIONS_EXTRA/PHP_EXTENSIONS_BASELINE or choose another PHP_VERSION." >&2
			exit 1
		fi

		log "Skipping unavailable PHP extension packages (PHP_EXTENSIONS_STRICT=false): ${missing_packages[*]}"
	fi

	PHP_EXTENSION_PACKAGES=("${installable_packages[@]}")
	PHP_EXTENSION_NAMES=("${installable_extensions[@]}")
}

resolve_php_extension_packages() {
	local effective_mode
	effective_mode="$(get_effective_php_db_driver_mode)"
	log "PHP DB driver selection: mode=$PHP_DB_DRIVER_MODE, database_type=$DATABASE_TYPE, effective_driver=$effective_mode"
	build_php_extension_package_list
	filter_php_extension_packages_by_availability
}

install_versioned_php_extensions() {
	if (( ${#PHP_EXTENSION_PACKAGES[@]} == 0 )); then
		log "No installable PHP extension packages selected."
		return 0
	fi

	apt-get install -y "${PHP_EXTENSION_PACKAGES[@]}"
}

php_is_enabled() {
	[[ "$PHP_ENABLE" == "true" ]]
}

ensure_sury_php_repo() {
	local keyring repo_file codename
	keyring="/usr/share/keyrings/debsuryorg-archive-keyring.gpg"
	repo_file="/etc/apt/sources.list.d/php.list"
	codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

	if [[ -z "$codename" ]]; then
		echo "Unable to determine Debian codename for Sury repository setup." >&2
		exit 1
	fi

	if [[ ! -f "$keyring" ]]; then
		log "Installing Sury PHP repository keyring."
		apt-get install -y ca-certificates curl gnupg2
		mkdir -p /usr/share/keyrings
		curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o "$keyring"
	fi

	if [[ ! -f "$repo_file" ]] || ! grep -q "packages.sury.org/php" "$repo_file"; then
		log "Adding Sury PHP repository for Debian codename: $codename"
		echo "deb [signed-by=$keyring] https://packages.sury.org/php/ $codename main" > "$repo_file"
	fi

	apt-get update
}

ensure_php_package_source() {
	local package_name candidate
	package_name="php${PHP_VERSION}-fpm"
	apt-get update
	candidate="$(apt-cache policy "$package_name" | awk '/Candidate:/ {print $2}')"

	if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
		log "Package $package_name not found in current apt sources. Falling back to Sury PHP repository."
		ensure_sury_php_repo
		candidate="$(apt-cache policy "$package_name" | awk '/Candidate:/ {print $2}')"
	fi

	if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
		echo "Unable to find package $package_name after configuring repositories." >&2
		exit 1
	fi
}

install_versioned_php_packages() {
	local version_prefix
	version_prefix="php${PHP_VERSION}"

	apt-get install -y \
		"${version_prefix}-fpm" \
		"${version_prefix}-cli" \
		"${version_prefix}-common"
}
