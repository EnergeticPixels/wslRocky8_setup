# Redis Cache Store

Redis provisioning is optional and controlled by dedicated toggles.

## Variables

Set these in `.env`:
- `REDIS_ENABLE=true` to install and start Redis during provisioning (default: `false`)
- `REDIS_VERSION=7.0` to declare your preferred Redis version target

## Version behavior

- The installer validates format (for example: `7.0` or `7.0.15`)
- Installation uses distro apt repositories
- If the installed version differs from the requested `REDIS_VERSION`, the script logs a warning

## Run Redis only

```bash
sudo bash scripts/redis_install.sh
```

## Verify

```bash
redis-server --version
redis-cli ping
systemctl status redis-server
```

If systemd is unavailable, use service fallback:

```bash
sudo service redis-server start
```

See also: [WSL Notes](07-WSL-NOTES.md)
