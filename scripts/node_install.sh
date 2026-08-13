#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

load_node_env() {
	if [[ -f "$ENV_FILE" ]]; then
		# shellcheck source=/dev/null
		source "$ENV_FILE"
	fi

	if [[ -z "${NODE_ENABLE:-}" && -n "${node_enable:-}" ]]; then
		NODE_ENABLE="$node_enable"
	fi
	if [[ -z "${NODE_DEFAULT_VERSION:-}" && -n "${node_default_version:-}" ]]; then
		NODE_DEFAULT_VERSION="$node_default_version"
	fi
	if [[ -z "${NODE_VERSIONS:-}" && -n "${node_versions:-}" ]]; then
		NODE_VERSIONS="$node_versions"
	fi
	if [[ -z "${NODE_NVM_VERSION:-}" && -n "${node_nvm_version:-}" ]]; then
		NODE_NVM_VERSION="$node_nvm_version"
	fi
	if [[ -z "${NODE_GLOBAL_PACKAGES:-}" && -n "${node_global_packages:-}" ]]; then
		NODE_GLOBAL_PACKAGES="$node_global_packages"
	fi

	NODE_ENABLE="${NODE_ENABLE:-false}"
	NODE_DEFAULT_VERSION="${NODE_DEFAULT_VERSION:-22}"
	NODE_VERSIONS="${NODE_VERSIONS:-22}"
	NODE_NVM_VERSION="${NODE_NVM_VERSION:-v0.40.3}"
	NODE_GLOBAL_PACKAGES="${NODE_GLOBAL_PACKAGES:-}"

	case "$(printf '%s' "$NODE_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			NODE_ENABLE=true
			;;
		0|false|no|n|off)
			NODE_ENABLE=false
			;;
		*)
			echo "Invalid NODE_ENABLE '$NODE_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	export NODE_ENABLE
	export NODE_DEFAULT_VERSION
	export NODE_VERSIONS
	export NODE_NVM_VERSION
	export NODE_GLOBAL_PACKAGES
}

trim_whitespace() {
	local input
	input="$1"
	input="${input#"${input%%[![:space:]]*}"}"
	input="${input%"${input##*[![:space:]]}"}"
	printf '%s' "$input"
}

validate_node_nvm_version() {
	if [[ ! "$NODE_NVM_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "Invalid NODE_NVM_VERSION '$NODE_NVM_VERSION'. Expected format like v0.40.3" >&2
		exit 1
	fi
}

validate_node_version_token() {
	local token
	token="$1"

	if [[ ! "$token" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
		echo "Invalid Node version '$token'. Use values like 22, 22.15, or 22.15.0" >&2
		exit 1
	fi
}

parse_node_versions() {
	local raw_token token
	local -a raw_list
	declare -A seen=()

	NODE_VERSION_LIST=()
	IFS=',' read -r -a raw_list <<< "$NODE_VERSIONS"

	for raw_token in "${raw_list[@]}"; do
		token="$(trim_whitespace "$raw_token")"
		if [[ -z "$token" ]]; then
			continue
		fi
		validate_node_version_token "$token"
		if [[ -z "${seen[$token]:-}" ]]; then
			seen[$token]=1
			NODE_VERSION_LIST+=("$token")
		fi
	done

	if (( ${#NODE_VERSION_LIST[@]} == 0 )); then
		echo "NODE_VERSIONS is empty after parsing. Provide at least one version." >&2
		exit 1
	fi
}

ensure_default_version_in_list() {
	local token found=0

	validate_node_version_token "$NODE_DEFAULT_VERSION"

	for token in "${NODE_VERSION_LIST[@]}"; do
		if [[ "$token" == "$NODE_DEFAULT_VERSION" ]]; then
			found=1
			break
		fi
	done

	if (( found == 0 )); then
		NODE_VERSION_LIST+=("$NODE_DEFAULT_VERSION")
	fi
}

resolve_target_user() {
	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		if [[ -z "${SUDO_USER:-}" || "${SUDO_USER:-}" == "root" ]]; then
			echo "Run this script via sudo from a normal user so Node can be installed in that user profile." >&2
			exit 1
		fi

		TARGET_USER="$SUDO_USER"
		TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
		if [[ -z "$TARGET_HOME" ]]; then
			echo "Unable to determine home directory for user $TARGET_USER" >&2
			exit 1
		fi
	else
		TARGET_USER="$(id -un)"
		TARGET_HOME="$HOME"
	fi

	export TARGET_USER
	export TARGET_HOME
}

run_as_target_user() {
	local command
	command="$1"

	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		sudo -u "$TARGET_USER" -H bash -lc "$command"
	else
		bash -lc "$command"
	fi
}

run_nvm_command() {
	local command
	command="$1"
	run_as_target_user "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; $command"
}

ensure_nvm_installed() {
	if [[ -s "$TARGET_HOME/.nvm/nvm.sh" ]]; then
		log "NVM already installed at $TARGET_HOME/.nvm"
		return
	fi

	log "Installing NVM version $NODE_NVM_VERSION for user $TARGET_USER"
	run_as_target_user "export PROFILE=/dev/null; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/$NODE_NVM_VERSION/install.sh | bash"
}

ensure_nvm_shell_init() {
	local bashrc
	bashrc="$TARGET_HOME/.bashrc"
	touch "$bashrc"

	if ! grep -Fq 'export NVM_DIR="$HOME/.nvm"' "$bashrc"; then
		echo 'export NVM_DIR="$HOME/.nvm"' >> "$bashrc"
	fi

	if ! grep -Fq '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$bashrc"; then
		echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> "$bashrc"
	fi

	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		chown "$TARGET_USER:$TARGET_USER" "$bashrc"
	fi
}

install_node_versions() {
	local version

	for version in "${NODE_VERSION_LIST[@]}"; do
		log "Installing Node.js version $version via NVM"
		run_nvm_command "nvm install $version"
	done

	run_nvm_command "nvm alias default $NODE_DEFAULT_VERSION"
	run_nvm_command "nvm use default >/dev/null"
}

print_node_summary() {
	local node_version npm_version
	node_version="$(run_nvm_command 'node -v')"
	npm_version="$(run_nvm_command 'npm -v')"

	log "Node.js provisioning complete for user $TARGET_USER"
	log "Installed/managed Node versions: ${NODE_VERSION_LIST[*]}"
	log "NVM default alias set to: $NODE_DEFAULT_VERSION"
	log "Active node version: $node_version"
	log "Active npm version: $npm_version"
}

main() {
	load_node_env

	if [[ "$NODE_ENABLE" != "true" ]]; then
		log "NODE_ENABLE is false. Skipping Node.js provisioning."
		exit 0
	fi

	validate_node_nvm_version
	parse_node_versions
	ensure_default_version_in_list
	resolve_target_user

	if ! command -v curl >/dev/null 2>&1; then
		echo "curl is required for NVM installation but was not found." >&2
		exit 1
	fi

	ensure_nvm_installed
	ensure_nvm_shell_init
	install_node_versions
	print_node_summary
}

main "$@"
