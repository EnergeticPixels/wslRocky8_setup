# Runtimes

## Java runtime and server

Java provisioning is optional and modular.

Main entry script:

```bash
sudo bash scripts/java_install.sh
```

Routing behavior:
- `scripts/tomcat_install.sh` when `JAVA_SERVER_MODE=tomcat`
- `scripts/java_service_install.sh` when `JAVA_SERVER_MODE=jar`

Set in `.env`:
- `JAVA_ENABLE=true` to enable Java provisioning (default: `false`)
- `JAVA_VERSION=8` for legacy compatibility
- `JAVA_SERVER_MODE=tomcat` or `JAVA_SERVER_MODE=jar`
- `JAVA_DISTRO=temurin` (recommended on Debian 13)

If `JAVA_SERVER_MODE=jar`, also set:
- `JAVA_APP_JAR_PATH=/absolute/path/to/app.jar`
- `JAVA_APP_PORT=8081`
- `JAVA_APP_ARGS=` (optional)

Tomcat notes:
- Prefers `tomcat9` from apt when available
- Falls back to manual Apache Tomcat 9 under `/opt/tomcat` if apt package is unavailable

## Node.js with NVM

Node provisioning is optional and user-scoped.

Run only Node setup:

```bash
sudo bash scripts/node_install.sh
```

Set in `.env`:
- `NODE_ENABLE=true` to enable Node provisioning (default: `false`)
- `NODE_DEFAULT_VERSION=22`
- `NODE_VERSIONS=22` (comma-separated)
- `NODE_NVM_VERSION=v0.40.3`
- `NODE_GLOBAL_PACKAGES=` (placeholder)

Behavior details:
- NVM installs to invoking user's home (`~/.nvm`)
- NVM init lines are added to `~/.bashrc` when missing
- `NODE_DEFAULT_VERSION` is installed and set as default alias
- If default version is missing from `NODE_VERSIONS`, it is auto-added

## Python

Python provisioning is available via:

```bash
sudo bash scripts/python_install.sh
```

Use this when you want Python setup without full provisioning.

See [Config Reference](CONFIG-REFERENCE.md) for runtime-related variables.
