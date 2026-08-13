# Config Reference

Central reference for frequently used `.env` variables.

## Core identity and keys

- `GIT_NAME`
- `GIT_EMAIL`
- `GPG_EXPIRATION` (example: `1y`)
- `SSH_KEY_EXPIRATION` (example: `1y`)
- `GIT_ALIAS_BR` (optional override)
- `GIT_ALIAS_LG` (optional override)

## tmux

- `TMUX_CONFIG_URL` (raw gist URL for `.tmux.conf`)

## Java

- `JAVA_ENABLE=true|false`
- `JAVA_VERSION` (example: `8`)
- `JAVA_DISTRO` (recommended: `temurin`)
- `JAVA_SERVER_MODE=tomcat|jar`
- `JAVA_APP_JAR_PATH` (required for jar mode)
- `JAVA_APP_PORT` (default example: `8081`)
- `JAVA_APP_ARGS` (optional)

## Node.js

- `NODE_ENABLE=true|false`
- `NODE_DEFAULT_VERSION` (example: `22`)
- `NODE_VERSIONS` (comma-separated)
- `NODE_NVM_VERSION` (example: `v0.40.3`)
- `NODE_GLOBAL_PACKAGES` (placeholder)

## Python

- Python-related options are handled by `scripts/python_install.sh`
- Keep script-specific values in `.env` when introduced

## Web server and PHP

- `WEB_SERVER=apache|nginx`
- `web_server` (compatibility key)
- `WEB_SSL_ENABLE=true|false`
- `WEB_SSL_BASE_DOMAIN` (base domain only, must end in `.local`, example: `app.local`)
- `WEB_SSL_CERT_EXPIRY=1y` (fixed to one year in current phase)
- `WEB_SSL_FORCE_HTTPS_REDIRECT=true|false` (NGINX only; when true, HTTP redirects to HTTPS)
- `PHP_ENABLE=true|false`
- `PHP_VERSION=7.4|8.0|8.1|8.2|8.3`
- `PHP_EXTENSIONS_BASELINE=common|none`
- `PHP_EXTENSIONS_EXTRA` (comma-separated)
- `PHP_EXTENSIONS_STRICT=true|false`
- `PHP_DB_DRIVER_MODE=auto|mysql|postgres|none`

SSL behavior in current phase:
- Apache: SSL execution active when `WEB_SSL_ENABLE=true`
- Nginx: SSL execution active when `WEB_SSL_ENABLE=true`
- Certificate SANs are generated for base domain and wildcard (`app.local` + `*.app.local`)
- For Nginx, `WEB_SSL_FORCE_HTTPS_REDIRECT=true` enables automatic HTTP to HTTPS redirects

Baseline map:
- `common`: `mbstring`, `xml`, `curl`, `zip`, `intl`, `gd`, `bcmath`, `opcache`, `readline`

## Databases

- `DATABASE_TYPE=none|mysql|postgres|mongodb`
- `MARIADB_VERSION` (10.5-10.11, 11.0-11.6)
- `POSTGRESQL_VERSION=14|15|16|17`
- `MONGODB_VERSION=6.0|7.0|8.0`

Shared dev setup:
- `DB_DEV_SETUP=true|false`
- `DB_DEV_DB_NAME`
- `DB_DEV_USER`
- `DB_DEV_PASSWORD`
- `DB_DEV_USER_HOST`

## Redis

- `REDIS_ENABLE=true|false`
- `REDIS_VERSION` (example: `7.0`)

## Compatibility keys

Several scripts accept lowercase keys for compatibility (for example `web_server`, `php_enable`, `database_type`). Prefer uppercase canonical keys for consistency in new `.env` files.
