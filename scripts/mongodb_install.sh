#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/mongodb_install.sh" >&2
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

service_start() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl daemon-reload || true
		systemctl enable mongod || true
		systemctl start mongod
	else
		service mongod start
	fi
}

service_status() {
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl status mongod --no-pager || true
	else
		service mongod status || true
	fi
}

wait_for_mongodb_ready() {
	local max_attempts attempt delay
	max_attempts="${MONGODB_START_MAX_ATTEMPTS:-30}"
	delay="${MONGODB_START_RETRY_DELAY_SECONDS:-1}"

	log "Waiting for MongoDB to accept connections on 127.0.0.1:27017."

	for ((attempt = 1; attempt <= max_attempts; attempt++)); do
		if mongosh --quiet --host 127.0.0.1 --port 27017 --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
			log "MongoDB is reachable (attempt $attempt/$max_attempts)."
			return 0
		fi

		sleep "$delay"
	done

	log "MongoDB did not become ready after ${max_attempts} attempts."
	log "Service diagnostics:"
	service_status

	if command -v journalctl >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		log "Recent mongod logs:"
		journalctl -u mongod -n 60 --no-pager || true
	fi

	return 1
}

mongodb_server_installed() {
	dpkg-query -W -f='${Status}' mongodb-org 2>/dev/null | grep -q "install ok installed"
}

resolve_mongodb_repo_codename() {
	local os_codename
	os_codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"

	case "$os_codename" in
		bookworm|bullseye)
			printf '%s' "$os_codename"
			;;
		trixie)
			log "Debian codename '$os_codename' detected. Using MongoDB bookworm repository compatibility fallback." >&2
			printf '%s' "bookworm"
			;;
		*)
			log "Unknown Debian codename '$os_codename'. Using MongoDB bookworm repository compatibility fallback." >&2
			printf '%s' "bookworm"
			;;
	esac
}

configure_mongodb_apt_repo() {
	local keyring_path repo_codename source_list
	keyring_path="/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg"
	source_list="/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list"
	repo_codename="$(resolve_mongodb_repo_codename)"

	# Clear any stale/invalid MongoDB source file from prior failed runs before refreshing apt indexes.
	rm -f "$source_list"

	apt-get update
	apt-get install -y curl gnupg ca-certificates

	curl -fsSL "https://pgp.mongodb.com/server-${MONGODB_VERSION}.asc" | \
		gpg --dearmor -o "$keyring_path"

	cat > "$source_list" <<EOF
deb [signed-by=$keyring_path] https://repo.mongodb.org/apt/debian ${repo_codename}/mongodb-org/${MONGODB_VERSION} main
EOF
}

install_mongodb_packages() {
	configure_mongodb_apt_repo
	apt-get update
	apt-get install -y mongodb-org
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

setup_mongodb_dev_environment() {
	local db_name_json user_json password_json

	db_name_json="$(json_escape "$DB_DEV_DB_NAME")"
	user_json="$(json_escape "$DB_DEV_USER")"
	password_json="$(json_escape "$DB_DEV_PASSWORD")"

	log "Creating MongoDB development database and user."

	mongosh --quiet admin --eval "
const dbName = \"${db_name_json}\";
const userName = \"${user_json}\";
const userPassword = \"${password_json}\";
const appDb = db.getSiblingDB(dbName);
const provisioningCollection = appDb.getCollection('__provisioning');

provisioningCollection.insertOne({createdAt: new Date()});
provisioningCollection.deleteMany({});

const existingUser = appDb.getUser(userName);
if (existingUser) {
  appDb.updateUser(userName, { pwd: userPassword, roles: [{ role: 'readWrite', db: dbName }] });
} else {
  appDb.createUser({ user: userName, pwd: userPassword, roles: [{ role: 'readWrite', db: dbName }] });
}
" >/dev/null

	log "MongoDB development environment setup complete."
	log "Connection details:"
	log "  - Database: $DB_DEV_DB_NAME"
	log "  - User: $DB_DEV_USER"
	log "  - Password: (stored in .env as DB_DEV_PASSWORD)"
	log ""
	log "To connect with mongosh:"
	log "  mongosh \"mongodb://$DB_DEV_USER:$DB_DEV_PASSWORD@localhost:27017/$DB_DEV_DB_NAME?authSource=$DB_DEV_DB_NAME\""
}

mongodb_install_main() {
	load_database_env
	validate_mongodb_version

	if ! database_is_enabled; then
		log "Database provisioning is disabled (DATABASE_TYPE=none). Skipping."
		return 0
	fi

	if [[ "$DATABASE_TYPE" != "mongodb" ]]; then
		log "DATABASE_TYPE is '$DATABASE_TYPE'; skipping MongoDB provisioning."
		return 0
	fi

	if mongodb_server_installed; then
		log "MongoDB server package is already installed."
	else
		log "Installing MongoDB (requested version: $MONGODB_VERSION)."
		install_mongodb_packages
	fi

	mongosh --version || true

	log "Ensuring MongoDB service is running..."
	service_start
	wait_for_mongodb_ready

	if db_dev_setup_is_enabled; then
		setup_mongodb_dev_environment
	else
		log "Development setup is disabled (DB_DEV_SETUP=false)."
		log "To enable, set DB_DEV_SETUP=true in .env and re-run this script."
	fi

	log "MongoDB provisioning complete."
	service_status
}

mongodb_install_main
