# Setup and Prerequisites

## Target environment

This repository is designed for:
- Windows 11 host
- WSL2 guest
- Debian (Trixie)

## Base preparation

Before running provisioning on a fresh environment:

```bash
sudo apt update
sudo apt dist-upgrade
```

## Configuration file flow

1. Copy `.env.sample` to `.env`
2. Edit values based on your setup profile
3. Run `./provisioning.sh wizard` to review the generated plan and confirm the provisioning run

The wizard can also create `.env` when it is missing. Use `./provisioning.sh validate` or `./provisioning.sh plan` independently when needed.

## Hostname resolution for local SSL URLs

If you enable web SSL and choose a `.local` developer URL, add that URL to the host machine HOSTS file.
Without this step, the URL will not resolve from outside the Debian guest environment.
The selected `WEB_SSL_BASE_DOMAIN` is used by both Apache and Nginx SSL provisioning.

Recommended mapping targets:
- `127.0.0.1` (localhost routing)
- Debian 13 WSL2 guest IP (direct guest routing)

Use only the mapping that matches your setup.

## Common profile patterns

- Minimal shell + Git: enable only core settings
- App development stack: Java/Node/Python + DB + web server
- Moodle testing: choose PHP + DB + web server mix for your version

See [Config Reference](CONFIG-REFERENCE.md) for all variables.

## Security baseline

- `.env` contains environment-specific values and may include local development secrets.
- Keep `.env` local. Do not commit real credentials.
- Development defaults are intended for local WSL use, not production.
