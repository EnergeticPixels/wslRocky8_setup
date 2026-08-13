#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

load_java_stack_env() {
	local script_dir env_file
	script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	env_file="$script_dir/../../.env"

	if [[ -f "$env_file" ]]; then
		# shellcheck source=/dev/null
		source "$env_file"
	fi

	# Backward compatibility for lowercase key names.
	if [[ -z "${JAVA_ENABLE:-}" && -n "${java_enable:-}" ]]; then
		JAVA_ENABLE="$java_enable"
	fi
	if [[ -z "${JAVA_VERSION:-}" && -n "${java_version:-}" ]]; then
		JAVA_VERSION="$java_version"
	fi
	if [[ -z "${JAVA_SERVER_MODE:-}" && -n "${java_server_mode:-}" ]]; then
		JAVA_SERVER_MODE="$java_server_mode"
	fi
	if [[ -z "${JAVA_DISTRO:-}" && -n "${java_distro:-}" ]]; then
		JAVA_DISTRO="$java_distro"
	fi
	if [[ -z "${JAVA_APP_JAR_PATH:-}" && -n "${java_app_jar_path:-}" ]]; then
		JAVA_APP_JAR_PATH="$java_app_jar_path"
	fi
	if [[ -z "${JAVA_APP_PORT:-}" && -n "${java_app_port:-}" ]]; then
		JAVA_APP_PORT="$java_app_port"
	fi
	if [[ -z "${JAVA_APP_ARGS:-}" && -n "${java_app_args:-}" ]]; then
		JAVA_APP_ARGS="$java_app_args"
	fi

	JAVA_ENABLE="${JAVA_ENABLE:-false}"
	JAVA_VERSION="${JAVA_VERSION:-8}"
	JAVA_SERVER_MODE="${JAVA_SERVER_MODE:-tomcat}"
	JAVA_DISTRO="${JAVA_DISTRO:-temurin}"
	JAVA_APP_JAR_PATH="${JAVA_APP_JAR_PATH:-}"
	JAVA_APP_PORT="${JAVA_APP_PORT:-8081}"
	JAVA_APP_ARGS="${JAVA_APP_ARGS:-}"

	case "$(printf '%s' "$JAVA_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			JAVA_ENABLE=true
			;;
		0|false|no|n|off)
			JAVA_ENABLE=false
			;;
		*)
			echo "Invalid JAVA_ENABLE '$JAVA_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	JAVA_SERVER_MODE="$(printf '%s' "$JAVA_SERVER_MODE" | tr '[:upper:]' '[:lower:]')"
	JAVA_DISTRO="$(printf '%s' "$JAVA_DISTRO" | tr '[:upper:]' '[:lower:]')"

	export JAVA_ENABLE
	export JAVA_VERSION
	export JAVA_SERVER_MODE
	export JAVA_DISTRO
	export JAVA_APP_JAR_PATH
	export JAVA_APP_PORT
	export JAVA_APP_ARGS
}

java_is_enabled() {
	[[ "$JAVA_ENABLE" == "true" ]]
}

validate_java_server_mode() {
	case "$JAVA_SERVER_MODE" in
		tomcat|jar)
			return 0
			;;
		*)
			echo "Invalid JAVA_SERVER_MODE '$JAVA_SERVER_MODE'. Supported values: tomcat, jar" >&2
			exit 1
			;;
	esac
}

validate_java_version() {
	case "$JAVA_VERSION" in
		8)
			return 0
			;;
		*)
			echo "Invalid JAVA_VERSION '$JAVA_VERSION'. Supported values currently: 8" >&2
			exit 1
			;;
	esac
}

validate_java_distro() {
	case "$JAVA_DISTRO" in
		temurin|openjdk)
			return 0
			;;
		*)
			echo "Invalid JAVA_DISTRO '$JAVA_DISTRO'. Supported values: temurin, openjdk" >&2
			exit 1
			;;
	esac
}

validate_jar_inputs() {
	if [[ -z "$JAVA_APP_JAR_PATH" ]]; then
		echo "JAVA_APP_JAR_PATH is required when JAVA_SERVER_MODE=jar" >&2
		exit 1
	fi

	if [[ ! -f "$JAVA_APP_JAR_PATH" ]]; then
		echo "JAVA_APP_JAR_PATH does not exist: $JAVA_APP_JAR_PATH" >&2
		exit 1
	fi

	if [[ ! "$JAVA_APP_PORT" =~ ^[0-9]+$ ]]; then
		echo "JAVA_APP_PORT must be numeric. Current value: '$JAVA_APP_PORT'" >&2
		exit 1
	fi
}

ensure_adoptium_repo() {
	local repo_file
	repo_file="/etc/yum.repos.d/adoptium.repo"

	if [[ ! -f "$repo_file" ]] || ! grep -q "packages.adoptium.net" "$repo_file"; then
		log "Adding Adoptium repository for Rocky 8."
		cat > "$repo_file" <<'EOF'
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/8/$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
	fi

	dnf makecache
}

install_java8_runtime() {
	local package_name

	validate_java_version
	validate_java_distro
	dnf makecache

	if [[ "$JAVA_DISTRO" == "openjdk" ]]; then
		package_name="java-1.8.0-openjdk-devel"
	else
		package_name="temurin-8-jdk"
		if ! dnf info "$package_name" >/dev/null 2>&1; then
			log "Package $package_name not found in current dnf sources. Configuring Adoptium repository."
			ensure_adoptium_repo
		fi
	fi

	log "Installing Java runtime package: $package_name"
	dnf install -y "$package_name"
}

configure_java_home_profile() {
	local java_binary java_home profile_file
	java_binary="$(command -v java || true)"

	if [[ -z "$java_binary" ]]; then
		echo "Java binary not found after installation." >&2
		exit 1
	fi

	java_home="$(dirname "$(dirname "$(readlink -f "$java_binary")")")"
	profile_file="/etc/profile.d/java_env.sh"

	cat > "$profile_file" <<EOF
export JAVA_HOME="$java_home"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF

	chmod 0644 "$profile_file"
	export JAVA_HOME="$java_home"
}
