# Quickstart

## 1) Prepare the system

```bash
sudo apt update
sudo apt dist-upgrade
```

## 2) Clone or copy the repository

Keep it inside your Linux home directory in WSL.

## 3) Start the provisioning wizard

```bash
./provisioning.sh init
./provisioning.sh wizard
```

The wizard collects your configuration, displays the plan inline, and starts provisioning after confirmation. Use `./provisioning.sh validate` or `./provisioning.sh plan` separately when needed.

## 4) Optional one-component installs

```bash
sudo bash scripts/git-config.sh
sudo bash scripts/java_install.sh
sudo bash scripts/node_install.sh
sudo bash scripts/database_install.sh
sudo bash scripts/redis_install.sh
```

## 6) Verify

Use the component-specific verification commands in:
- [Core Services](02-CORE-SERVICES.md)
- [Runtimes](03-RUNTIMES.md)
- [Web Stack](04-WEB-STACK.md)
- [Databases](05-DATABASES.md)
- [Cache Store](06-CACHE-STORE.md)
