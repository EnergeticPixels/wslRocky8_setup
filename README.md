# WSL Debian Provisioning Kit

Opinionated provisioning scripts for Windows 11 + WSL2 (Debian/Trixie) focused on app development and Moodle testing.

## Quickstart

1. Update system packages:

```bash
sudo apt update
sudo apt dist-upgrade
```

2. Copy this repository into your Linux home directory.
3. Copy `.env.sample` to `.env` and edit values.
4. Start the provisioning wizard:

```bash
./provisioning.sh wizard
```

The wizard saves `.env`, displays the provisioning plan, and starts the run after confirmation.

### Fresh clone quick start (Debian 13 WSL)

If you cloned the repo directly (recommended), run:

```bash
cd /path/to/your/cloned/repo
chmod +x provisioning.sh

# Create .env from .env.sample
./provisioning.sh init

# Interactive setup, inline plan review, and confirmation
./provisioning.sh wizard

# Optional validation and plan commands
./provisioning.sh validate
./provisioning.sh plan

# Run provisioning
sudo bash ./provisioning.sh run
```

### Terminal interface (`provisioning.sh`)

You can use `provisioning.sh` as a terminal interface for `.env`-driven provisioning.
The wizard always uses plain text question-and-answer prompts in the terminal.

```bash
# Create .env from .env.sample
./provisioning.sh init

# Run interactive configuration, plan review, and confirmation
./provisioning.sh wizard

# Validate current .env values against script validators
./provisioning.sh validate

# Show what provisioning will run with current .env
./provisioning.sh plan

# Run full provisioning
sudo bash ./provisioning.sh run

# Run a single component
sudo bash ./provisioning.sh run --only db
```

Config helpers:

```bash
./provisioning.sh config show
./provisioning.sh config get DATABASE_TYPE
./provisioning.sh config set DATABASE_TYPE=postgres POSTGRESQL_VERSION=17
./provisioning.sh config unset TMUX_CONFIG_URL
```

### Local DNS requirement for .local developer URLs

When using web SSL with a custom `.local` URL, you must add that URL to the host machine HOSTS file.
If this is skipped, the URL will not resolve from outside Debian (for example, from a browser on the host OS).

Map the selected `WEB_SSL_BASE_DOMAIN` to one of the following:
- `127.0.0.1` when traffic is forwarded to localhost
- Debian WSL2 guest IP when resolving directly to the guest

Example HOSTS entries:

```text
127.0.0.1 app.local
172.26.227.15 app.local
```

Use one mapping that matches your networking setup. Do not keep conflicting entries for the same host name.

For Nginx SSL setups, you can control HTTP redirect behavior with `WEB_SSL_FORCE_HTTPS_REDIRECT=true|false`.

### Windows browser trust for mkcert certificates

If Edge or Chrome on Windows shows Not Secure for your local HTTPS URL, import the mkcert root CA into Windows Trusted Root Certification Authorities.

In Debian/WSL:

```bash
sudo mkcert -CAROOT
```

This prints the CA directory used by the provisioning run. When provisioning is run with sudo, this is usually under /root/.local/share/mkcert.

Copy rootCA.pem from that directory to Windows, then in Windows PowerShell (Run as Administrator):

```powershell
certutil -addstore -f Root "C:\path\to\rootCA.pem"
```

After import:
- fully close and reopen Edge or Chrome
- verify URL resolution still points to your intended target in the Windows HOSTS file

Other helpers:

```bash
# Dry run execution commands
sudo bash ./provisioning.sh run --dry-run
sudo bash ./provisioning.sh run --only node --dry-run

# Show recent provisioning logs
./provisioning.sh logs
```

### SSH and GPG key management
Keys are managed automatically during each `provisioning.sh run`:

- [Documentation Home](docs/README.md)
- [00 - Quickstart](docs/00-QUICKSTART.md)
- [01 - Setup and Prerequisites](docs/01-SETUP.md)
- [02 - Core Services (Git, SSH/GPG, Vim, tmux)](docs/02-CORE-SERVICES.md)
- [03 - Runtimes (Java, Node, Python)](docs/03-RUNTIMES.md)
- [04 - Web Stack (Apache/Nginx, Tomcat, PHP)](docs/04-WEB-STACK.md)
- [05 - Databases (MariaDB, PostgreSQL, MongoDB)](docs/05-DATABASES.md)
- [06 - Cache Store (Redis)](docs/06-CACHE-STORE.md)
- [07 - WSL Notes and Service Behavior](docs/07-WSL-NOTES.md)
- [Config Reference (.env variables)](docs/CONFIG-REFERENCE.md)

## Script Entry Points

- Full run: `provisioning.sh`
- Script directory: `scripts/`
- Shared libraries: `scripts/lib/`

Run any installer directly if you only want one component, for example:

```bash
sudo bash scripts/node_install.sh
sudo bash scripts/database_install.sh
sudo bash scripts/redis_install.sh
```

## Notes

- Detailed guidance moved into `docs/` to keep this README focused.
- `.env` is expected to remain local and is not meant to be committed.
