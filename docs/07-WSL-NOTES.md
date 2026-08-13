# WSL Notes and Service Behavior

This repository targets Windows 11 + WSL2 + Debian. Some behavior depends on systemd availability.

## systemd impact

If systemd is enabled in WSL, installers can enable/start services normally.
If systemd is disabled, you may need manual service startup each session.

Common examples:

```bash
sudo service mariadb start
sudo service redis-server start
```

## GPG terminal note

If signed commits fail with `Inappropriate ioctl for device`:

1. Ensure shell exports:

```bash
export GPG_TTY=$(tty)
```

2. `scripts/gpg_gen.sh` adds this export to the invoking user's `~/.bashrc`.
3. If pinentry still complains in the current terminal:

```bash
gpg-connect-agent updatestartuptty /bye
```

## Java service note

When using Java server modes, service behavior depends on systemd support.
If unit management fails in WSL, start services manually for that session.

## Troubleshooting pattern

- Verify service status with `systemctl status <service>` when available
- Use `service <name> start` fallback when systemctl is unavailable
- Re-open shell session after `.bashrc` changes
