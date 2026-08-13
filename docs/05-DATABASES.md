# Databases

Database provisioning is optional and mutually exclusive.

Set in `.env`:
- `DATABASE_TYPE=none` (default) for no database
- `DATABASE_TYPE=mysql` for MariaDB (MySQL-compatible)
- `DATABASE_TYPE=postgres` for PostgreSQL
- `DATABASE_TYPE=mongodb` for MongoDB Community Edition

Run database setup only:

```bash
sudo bash scripts/database_install.sh
```

## Shared development setup variables

These apply when `DB_DEV_SETUP=true`:
- `DB_DEV_DB_NAME=dev_db`
- `DB_DEV_USER=dev_user`
- `DB_DEV_PASSWORD=dev_password`
- `DB_DEV_USER_HOST=localhost` (used by SQL flows)

Security note: these values are plaintext in `.env` and intended for local development only.

## MariaDB (MySQL mode)

Set:
- `DATABASE_TYPE=mysql`
- `MARIADB_VERSION=10.5` (supported: 10.5-10.11, 11.0-11.6)

Example:

```bash
DATABASE_TYPE=mysql
MARIADB_VERSION=10.5
DB_DEV_SETUP=true
DB_DEV_DB_NAME=my_app_db
DB_DEV_USER=app_user
DB_DEV_PASSWORD=app_password
DB_DEV_USER_HOST=localhost
```

Commands:

```bash
mariadb -u root
mariadb -u app_user -p -h localhost my_app_db
mariadb -u root -e "SELECT VERSION();"
systemctl status mariadb
```

Behavior highlights:
- Service is enabled on boot when supported
- Existing installs are detected and not reinstalled
- Dev DB/user creation runs only when `DB_DEV_SETUP=true`

## PostgreSQL

Set:
- `DATABASE_TYPE=postgres`
- `POSTGRESQL_VERSION=14|15|16|17` (default sample uses `17`)

Example:

```bash
DATABASE_TYPE=postgres
POSTGRESQL_VERSION=17
DB_DEV_SETUP=true
DB_DEV_DB_NAME=my_app_db
DB_DEV_USER=app_user
DB_DEV_PASSWORD=app_password
DB_DEV_USER_HOST=localhost
```

Commands:

```bash
sudo -u postgres psql
psql "host=localhost dbname=my_app_db user=app_user password=app_password"
psql --version
sudo -u postgres psql -c "SELECT version();"
systemctl status postgresql
```

Behavior highlights:
- Installs versioned packages when available
- Falls back to default `postgresql` packages when requested versioned package is unavailable
- Starts services using `systemctl` or `service` fallback

Direct install script:

```bash
sudo bash scripts/postgresql_install.sh
```

## MongoDB

Set:
- `DATABASE_TYPE=mongodb`
- `MONGODB_VERSION=6.0|7.0|8.0` (default sample uses `8.0`)

Example:

```bash
DATABASE_TYPE=mongodb
MONGODB_VERSION=8.0
DB_DEV_SETUP=true
DB_DEV_DB_NAME=my_app_db
DB_DEV_USER=app_user
DB_DEV_PASSWORD=app_password
```

Commands:

```bash
mongosh
mongosh "mongodb://app_user:app_password@localhost:27017/my_app_db?authSource=my_app_db"
mongosh --version
systemctl status mongod
```

Behavior highlights:
- Uses official MongoDB apt repository
- On Debian trixie and unknown codenames, falls back to MongoDB `bookworm` track
- Starts services using `systemctl` or `service` fallback

Direct install script:

```bash
sudo bash scripts/mongodb_install.sh
```

## Security notes

- Development credentials in `.env` are acceptable for local WSL development only
- Never commit `.env` with real credentials
- Use strong passwords and restricted privileges for any non-local environment
