# Rocky 8 Compatibility Contract

This document defines the Phase 1 compatibility contract for this repository.

## Scope

Supported target:
- Windows 11 host
- WSL2 guest
- Rocky Linux 8

Out of scope for this contract:
- Debian-first onboarding behavior
- Non-Rocky RPM distributions unless explicitly added later

## Platform Contract

### Package manager
- Primary package manager: `dnf`
- Base bootstrap commands:
  - `sudo dnf makecache`
  - `sudo dnf upgrade --refresh`
  - `sudo dnf install -y git tar epel-release ripgrep`

### Service management
- Primary service manager: `systemctl`
- Fallback manager when systemd is unavailable in WSL session: `service`

### Package query contract
- Preferred installed-package check: `rpm -q <package>`
- Preferred availability check: `dnf info <package>`

### Repository layout contract
- Repository files: `/etc/yum.repos.d/*.repo`
- Imported keys: RPM key import flow for third-party repositories

### User and group mapping contract
- Apache runtime group: `apache`
- Nginx runtime group: `nginx`

### Configuration path contract
- Apache root: `/etc/httpd`
- Apache site config directory: `/etc/httpd/conf.d`
- Nginx root: `/etc/nginx`
- Nginx site config directory: `/etc/nginx/conf.d`

## Onboarding Contract

All onboarding commands and target language in [README.md](../README.md), [docs/00-QUICKSTART.md](00-QUICKSTART.md), and [docs/01-SETUP.md](01-SETUP.md) must be Rocky 8-first.

## Migration Note

Phase 1 establishes target behavior and documentation contract.
Implementation migration of installer internals and package flows is completed in later phases of the transformation plan.
