#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "This script must run as root. Use: sudo bash scripts/tomcat_install.sh" >&2
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

install_java8_runtime
configure_java_home_profile

log "Installing Tomcat (preferred package: tomcat9)"
apt-get update

if apt-cache show tomcat9 >/dev/null 2>&1; then
	apt-get install -y tomcat9
	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload || true
		systemctl enable --now tomcat9 || true
	fi
	SERVICE_NAME="tomcat9"
else
	log "Package tomcat9 is unavailable. Installing Apache Tomcat 9 manually."
	TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.108}"
	TOMCAT_USER="tomcat"
	TOMCAT_DIR="/opt/tomcat"
	TOMCAT_TARBALL="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
	TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/${TOMCAT_TARBALL}"
	TMP_DIR="$(mktemp -d)"
	trap 'rm -rf "$TMP_DIR"' EXIT

	apt-get install -y curl tar

	if ! id -u "$TOMCAT_USER" >/dev/null 2>&1; then
		useradd -r -m -U -d /opt/tomcat -s /bin/false "$TOMCAT_USER"
	fi

	curl -fsSL "$TOMCAT_URL" -o "$TMP_DIR/$TOMCAT_TARBALL"
	rm -rf "$TOMCAT_DIR"
	mkdir -p "$TOMCAT_DIR"
	tar -xzf "$TMP_DIR/$TOMCAT_TARBALL" -C "$TOMCAT_DIR" --strip-components=1
	chown -R "$TOMCAT_USER":"$TOMCAT_USER" "$TOMCAT_DIR"
	chmod +x "$TOMCAT_DIR/bin/"*.sh

	cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 9 Web Application Container
After=network.target

[Service]
Type=forking
User=$TOMCAT_USER
Group=$TOMCAT_USER
Environment=JAVA_HOME=$JAVA_HOME
Environment=CATALINA_PID=$TOMCAT_DIR/temp/tomcat.pid
Environment=CATALINA_HOME=$TOMCAT_DIR
Environment=CATALINA_BASE=$TOMCAT_DIR
Environment='CATALINA_OPTS=-Xms256M -Xmx512M -Djava.security.egd=file:/dev/./urandom'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Dfile.encoding=UTF-8'
ExecStart=$TOMCAT_DIR/bin/startup.sh
ExecStop=$TOMCAT_DIR/bin/shutdown.sh
SuccessExitStatus=143
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload
		systemctl enable --now tomcat
	fi
	SERVICE_NAME="tomcat"
fi

if command -v systemctl >/dev/null 2>&1; then
	if systemctl is-active --quiet "$SERVICE_NAME"; then
		log "Tomcat service is active: $SERVICE_NAME"
	else
		log "Tomcat service is not active yet. Check with: systemctl status $SERVICE_NAME"
	fi
fi

if command -v curl >/dev/null 2>&1; then
	if curl -fsS http://127.0.0.1:8080 >/dev/null 2>&1; then
		log "Tomcat HTTP health check passed on http://127.0.0.1:8080"
	else
		log "Tomcat HTTP health check did not return success yet (this can be normal right after install)."
	fi
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
	log "WSL detected. If systemd is not enabled in WSL, run this service manually per session."
fi

log "Tomcat provisioning complete"
