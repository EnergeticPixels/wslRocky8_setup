# Web Stack

## Web server selection

Set `WEB_SERVER` in `.env`:
- `WEB_SERVER=apache` installs Apache (`apache2` package)
- `WEB_SERVER=nginx` installs Nginx (`nginx` package)

If `WEB_SERVER` is unset, web server installation is skipped.
`web_server` is accepted for compatibility.

Scripts:
- `scripts/web_server_install.sh` selects installer by `WEB_SERVER`
- `scripts/web_server_apache_install.sh` handles Apache
- `scripts/web_server_nginx_install.sh` handles Nginx

Run only web server setup:

```bash
sudo bash scripts/web_server_install.sh
```

## Local HTTPS with mkcert (Apache and Nginx)

Set SSL options in `.env`:
- `WEB_SSL_ENABLE=true`
- `WEB_SSL_BASE_DOMAIN=app.local`
- `WEB_SSL_CERT_EXPIRY=1y`
- `WEB_SSL_FORCE_HTTPS_REDIRECT=true` (Nginx only)

Current phase scope:
- Apache SSL execution is implemented
- Nginx SSL execution is implemented

When enabled, provisioning:
- Installs `mkcert` if missing
- Generates certificate SANs for base domain and wildcard (`app.local` and `*.app.local`)
- Stores artifacts in web-server-specific SSL paths
- Enables web-server-specific SSL site configuration

Apache certificate and site files:
- `/etc/apache2/ssl/serverprovo-local.crt`
- `/etc/apache2/ssl/serverprovo-local.key`
- `/etc/apache2/ssl/serverprovo-domains.txt`
- `/etc/apache2/sites-available/serverprovo-ssl.conf`

Nginx certificate and site files:
- `/etc/nginx/ssl/serverprovo-local.crt`
- `/etc/nginx/ssl/serverprovo-local.key`
- `/etc/nginx/ssl/serverprovo-domains.txt`
- `/etc/nginx/sites-available/serverprovo-ssl.conf`

Nginx redirect behavior when SSL is enabled:
- `WEB_SSL_FORCE_HTTPS_REDIRECT=true`: HTTP traffic redirects to HTTPS
- `WEB_SSL_FORCE_HTTPS_REDIRECT=false`: HTTP and HTTPS are both served

### Host OS HOSTS file requirement

If the URL should work from the host computer, add `WEB_SSL_BASE_DOMAIN` to the host OS HOSTS file.
Without this step, name resolution can fail outside Debian.

Map to either:
- `127.0.0.1` when localhost forwarding is used
- WSL2 Debian guest IP for direct guest routing

### Windows browser trust (Edge and Chrome)

If Windows browsers still show Not Secure after hosts mapping, trust the mkcert root CA in Windows.

1. In Debian/WSL, print the mkcert CA directory used by provisioning:

```bash
sudo mkcert -CAROOT
```

2. Copy rootCA.pem from that directory to Windows.

3. In Windows PowerShell (Run as Administrator), import into Trusted Root:

```powershell
certutil -addstore -f Root "C:\path\to\rootCA.pem"
```

4. Fully close and reopen Edge/Chrome.

Note:
- If provisioning was run with sudo, the CA directory is typically `/root/.local/share/mkcert`.
- A privately trusted CA is expected for local development `.local` domains.

### Troubleshooting

- Ensure local trust was initialized: `mkcert -install`
- Check Apache config: `sudo apache2ctl configtest`
- Check Nginx config: `sudo nginx -t`
- Confirm SSL module: `sudo apache2ctl -M | grep ssl_module`
- Check cert expiry and SANs:

```bash
sudo openssl x509 -in /etc/apache2/ssl/serverprovo-local.crt -noout -dates -ext subjectAltName
sudo openssl x509 -in /etc/nginx/ssl/serverprovo-local.crt -noout -dates -ext subjectAltName
```

- Validate endpoint:

```bash
curl -k https://app.local
```

## PHP provisioning

Enable/disable per run:
- `PHP_ENABLE=true` installs PHP alongside selected web server
- `PHP_ENABLE=false` skips PHP

Set PHP version:
- `PHP_VERSION=7.4|8.0|8.1|8.2|8.3`

Extension planning:
- `PHP_EXTENSIONS_BASELINE=common` for default profile
- `PHP_EXTENSIONS_BASELINE=none` to disable baseline
- `PHP_EXTENSIONS_EXTRA=` comma-separated extras (example: `soap,pgsql`)
- `PHP_EXTENSIONS_STRICT=true` fail when requested extension package is unavailable
- `PHP_EXTENSIONS_STRICT=false` skip unavailable packages with warning

Database driver extension selection:
- `PHP_DB_DRIVER_MODE=auto|mysql|postgres|none`
- In `auto` mode, selection follows `DATABASE_TYPE`

Behavior details:
- Apache and Nginx use `php-fpm` integration
- Scripts prefer distro packages first
- If requested version is unavailable, installer adds Sury repository and retries
- Lowercase compatibility keys are accepted (`php_enable`, `php_version`, etc.)

Current baseline profile:
- `common` maps to `mbstring`, `xml`, `curl`, `zip`, `intl`, `gd`, `bcmath`, `opcache`, `readline`

## Tomcat note

If Java mode is Tomcat, see runtime details in [Runtimes](03-RUNTIMES.md).
