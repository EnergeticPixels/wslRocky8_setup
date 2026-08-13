#!/usr/bin/env bash
set -euo pipefail

if ! command -v log >/dev/null 2>&1; then
	log() {
		printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
	}
fi

load_python_env() {
	local script_dir env_file
	script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
	env_file="$script_dir/../../.env"

	if [[ -f "$env_file" ]]; then
		# shellcheck source=/dev/null
		source "$env_file"
	fi

	# Backward compatibility for lowercase key names.
	if [[ -z "${PYTHON_ENABLE:-}" && -n "${python_enable:-}" ]]; then
		PYTHON_ENABLE="$python_enable"
	fi
	if [[ -z "${PYTHON_DATA_SCIENCE_STACK_ENABLE:-}" && -n "${python_data_science_stack_enable:-}" ]]; then
		PYTHON_DATA_SCIENCE_STACK_ENABLE="$python_data_science_stack_enable"
	fi
	if [[ -z "${PYTHON_DEV_MODE:-}" && -n "${python_dev_mode:-}" ]]; then
		PYTHON_DEV_MODE="$python_dev_mode"
	fi

	PYTHON_ENABLE="${PYTHON_ENABLE:-false}"
	PYTHON_DATA_SCIENCE_STACK_ENABLE="${PYTHON_DATA_SCIENCE_STACK_ENABLE:-false}"
	PYTHON_DEV_MODE="${PYTHON_DEV_MODE:-none}"

	# Normalize PYTHON_ENABLE to boolean
	case "$(printf '%s' "$PYTHON_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			PYTHON_ENABLE=true
			;;
		0|false|no|n|off)
			PYTHON_ENABLE=false
			;;
		*)
			echo "Invalid PYTHON_ENABLE '$PYTHON_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	# Normalize PYTHON_DATA_SCIENCE_STACK_ENABLE to boolean
	case "$(printf '%s' "$PYTHON_DATA_SCIENCE_STACK_ENABLE" | tr '[:upper:]' '[:lower:]')" in
		1|true|yes|y|on)
			PYTHON_DATA_SCIENCE_STACK_ENABLE=true
			;;
		0|false|no|n|off)
			PYTHON_DATA_SCIENCE_STACK_ENABLE=false
			;;
		*)
			echo "Invalid PYTHON_DATA_SCIENCE_STACK_ENABLE '$PYTHON_DATA_SCIENCE_STACK_ENABLE'. Supported values: true/false" >&2
			exit 1
			;;
	esac

	# Normalize PYTHON_DEV_MODE to lowercase
	PYTHON_DEV_MODE="$(printf '%s' "$PYTHON_DEV_MODE" | tr '[:upper:]' '[:lower:]')"

	export PYTHON_ENABLE
	export PYTHON_DATA_SCIENCE_STACK_ENABLE
	export PYTHON_DEV_MODE
}

python_is_enabled() {
	[[ "$PYTHON_ENABLE" == "true" ]]
}

validate_python_dev_mode() {
	case "$PYTHON_DEV_MODE" in
		reflex|flask|both|none)
			return 0
			;;
		*)
			echo "Invalid PYTHON_DEV_MODE '$PYTHON_DEV_MODE'. Supported values: reflex|flask|both|none" >&2
			exit 1
			;;
	esac
}

# Install a pip package with the latest version
# Usage: pip_install_latest package_name [package_name ...]
pip_install_latest() {
	local packages=("$@")
	
	if (( ${#packages[@]} == 0 )); then
		echo "Error: pip_install_latest requires at least one package name" >&2
		return 1
	fi

	log "Installing Python packages: ${packages[*]} (latest versions)"
	python3 -m pip install --upgrade "${packages[@]}"
}

# Verify a Python package can be imported
# Usage: verify_python_package module_name
verify_python_package() {
	local module="$1"
	
	if python3 -c "import $module" 2>/dev/null; then
		local version
		version=$(python3 -c "import $module; print(getattr($module, '__version__', 'unknown'))")
		log "✓ $module installed (version: $version)"
		return 0
	else
		log "✗ Failed to import $module"
		return 1
	fi
}

# Get the version of an installed pip package
# Usage: get_pip_package_version package_name
get_pip_package_version() {
	local package="$1"
	python3 -m pip show "$package" 2>/dev/null | grep "^Version:" | cut -d' ' -f2
}
