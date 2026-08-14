# WSL Notes and Service Behavior

This repository targets Windows 11 + WSL2 + Rocky Linux 8. Some behavior depends on systemd availability.

## systemd impact

If systemd is enabled in WSL, installers can enable/start services normally.
If systemd is disabled, you may need manual service startup each session.

Common examples:

```bash
sudo service mariadb start
sudo service redis start
```

## firewalld and Windows host access

This can affect both browser access from Windows and VS Code Remote WSL session stability.

- If `firewalld` is active in WSL, host traffic from Windows can be blocked until rules are opened.
- Enabling only `http` may still interrupt existing VS Code connectivity briefly when firewall rules are reloaded.

`provisioning.sh run` now normalizes WSL firewall behavior by:

- trusting the Windows host gateway IP in firewalld
- allowing `http` and `https` on the active interface zone

If you changed rules manually and connectivity looks odd, rerun:

```bash
sudo bash ./provisioning.sh run --only web
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
