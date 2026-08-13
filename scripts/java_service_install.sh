#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/java_service_install.sh" >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JAVA_LIB="$SCRIPT_DIR/lib/java_stack.sh"

if [[ ! -f "$JAVA_LIB" ]]; then
	echo "Missing helper library: $JAVA_LIB" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$JAVA_LIB"
load_java_stack_env
validate_java_version
validate_java_distro
validate_jar_inputs

install_java8_runtime
configure_java_home_profile

SERVICE_USER="javaapp"
SERVICE_GROUP="javaapp"
SERVICE_NAME="java-app"
LOG_DIR="/var/log/java-app"
RUNTIME_DIR="/var/lib/java-app"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
	groupadd --system "$SERVICE_GROUP"
fi

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
	useradd --system --gid "$SERVICE_GROUP" --create-home --home-dir /var/lib/java-app --shell /usr/sbin/nologin "$SERVICE_USER"
fi

mkdir -p "$LOG_DIR" "$RUNTIME_DIR"
chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$LOG_DIR" "$RUNTIME_DIR"
chmod 0750 "$LOG_DIR" "$RUNTIME_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Standalone Java Application Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$RUNTIME_DIR
Environment=JAVA_HOME=$JAVA_HOME
Environment=JAVA_APP_PORT=$JAVA_APP_PORT
ExecStart=$JAVA_HOME/bin/java -jar $JAVA_APP_JAR_PATH $JAVA_APP_ARGS
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/application.log
StandardError=append:$LOG_DIR/application.err.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

if command -v systemctl >/dev/null 2>&1; then
	systemctl daemon-reload
	systemctl enable --now "$SERVICE_NAME" || true
	if systemctl is-active --quiet "$SERVICE_NAME"; then
		log "Java service is active: $SERVICE_NAME"
	else
		log "Java service did not become active yet. Check with: systemctl status $SERVICE_NAME"
	fi
else
	log "systemctl is unavailable. Start manually with: $JAVA_HOME/bin/java -jar $JAVA_APP_JAR_PATH $JAVA_APP_ARGS"
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
	log "WSL detected. If systemd is not enabled in WSL, start this service manually per session."
fi

log "Standalone Java service provisioning complete"
