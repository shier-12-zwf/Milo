# MILO Web on Huawei Cloud

The website and `/app` share one Vite build. Nginx serves that build and forwards
only the three `/api/v1/recall/` endpoints to the existing AI gateway. Diary data
stays in the visitor's browser; this does not deploy the HarmonyOS package.

## Current private preview

The preparation configuration listens **only on `127.0.0.1:8080`**. It does not
open public ports 80/443, request a certificate, or change DNS. Keep this private
until the website's filing and public release conditions have been checked.

As of 2026-09-23, the APP filing is awaiting initial review. The website is not
public: its separate filing still needs to be completed, DNS does not yet point
the domain to this server, and TLS certificate issuance is waiting for the
website filing. The domain is registered, but registration alone does not connect
it to this deployment.

- Static releases: `/opt/milo-web/releases/<release-id>`.
- Active static build: `/opt/milo-web/current` symlink.
- Deployment helpers: `/opt/milo-web/deploy/`.
- Nginx site: `/etc/nginx/sites-available/milo-web-loopback.conf`.
- Private credential include: `/etc/nginx/milo-private/gateway-auth.conf`.
- Existing gateway: `/opt/milo-gateway/current`, listening on `127.0.0.1:8787`.
- Gateway environment: `/etc/milo-gateway/gateway.env`, readable only by root.
- Certbot certificate location after a later approved request: `/etc/letsencrypt/live/`.

Ubuntu 24.04 packages `nginx`, `certbot`, and `python3-certbot-nginx` are installed
from the Ubuntu signed archive through Huawei's mirror. No certificate exists yet.

## Install or refresh the private proxy

Copy `web-install-loopback.py`, `web-nginx-loopback.conf`, and
`web-publish-release.py` from `services/ai-gateway/deploy/` to
`/opt/milo-web/deploy/` on the server, then run:

```sh
sudo python3 /opt/milo-web/deploy/web-install-loopback.py
```

The installer reads the gateway token on the server and writes an Nginx include
with directory mode 0700 and file mode 0600. It never prints the token or puts it
in the static build. It checks Nginx syntax before reloading and restores its
previous configuration if the syntax check fails. An absent static release gets
a local placeholder until the actual build is published. Other sites are untouched.

Do not run `nginx -T` in captured logs: it expands the private token include.
Use `nginx -t` for validation. Rerun the installer after rotating the gateway token.

## Build and publish the website

Build from the repository root with the domain-root base path:

```sh
npm -w apps/web run build -- --base=/
COPYFILE_DISABLE=1 tar -czf /tmp/milo-web-dist.tgz -C apps/web/dist .
scp -i ~/.ssh/milo_cloud_ed25519 /tmp/milo-web-dist.tgz root@119.3.231.143:/tmp/
ssh -i ~/.ssh/milo_cloud_ed25519 root@119.3.231.143 \
  'python3 /opt/milo-web/deploy/web-publish-release.py /tmp/milo-web-dist.tgz 2026-09-23-001'
```

Choose a new release ID for each upload. The publisher rejects symlinks, path
traversal, special files, and oversized archives, then changes `current` atomically.
It verifies `/`, `/app`, and `/privacy` against the uploaded `index.html`,
and restores the previous symlink if verification fails. Old releases remain
available for rollback. Publishing static files does not restart the AI gateway.

Preview from the Mac through SSH:

```sh
ssh -i ~/.ssh/milo_cloud_ed25519 -N -L 8080:127.0.0.1:8080 root@119.3.231.143
```

Open `http://localhost:8080/` and `http://localhost:8080/app` locally. The preview
requires the Mac's current **direct** public IP in the SSH security-group rule.
When FlClash TUN is enabled, `api.ipify.org` may show a different proxy exit;
`198.18.*` responses are fake DNS, not real domain records. Use an independent
HTTPS DNS lookup when checking domain records.

## Proxy boundaries and verification

- `/api/health` is anonymous and does not invoke AI.
- Only POST to `open`, `respond`, or `diary` is proxied; other API paths return 404.
- Nginx overwrites Authorization, forwarding headers, and request IDs. Caller
  supplied values cannot select a gateway credential or forge the rate-limit IP.
- JSON bodies are capped at 64 KiB, matching the gateway. API requests with query
  strings are rejected, and request buffering to disk is disabled.
- HTML, CSS, JavaScript, JSON, XML, and SVG responses of at least 1 KiB use gzip
  when requested by the browser, reducing transfers over the 2 Mbps connection.
  PNG files are served unchanged.
- Nginx applies 60 requests/minute/IP with a burst of 10 and 5 concurrent API
  connections/IP. The gateway's existing 60/minute limit is unchanged.
- Access logs and site error logs are disabled to avoid retaining request URLs or
  content. Gateway logs retain only request ID, fixed route, status, and timing.
- The gateway trusts only a local proxy. Nginx uses the actual peer IP, not incoming
  `X-Forwarded-For`. SSH-tunnel visitors share the tunnel's loopback source IP;
  a future directly exposed HTTPS site can preserve each visitor's IP.
- The server-side application token is not user authentication. A future public
  API must retain rate limits and needs a deliberate usage/cost policy.

Read-only checks, without sending diary text or using the AI provider:

```sh
curl -fsS http://127.0.0.1:8080/api/health
# Invalid input must return 400 rather than 401: the private credential was applied.
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' \
  --data '{}' http://127.0.0.1:8080/api/v1/recall/open
ss -ltn
```

## Later public release

Check the website's filing status separately from the APP filing, add real DNS A
records to `119.3.231.143`, prepare the HTTPS site, obtain its certificate, then
enable only the intended public HTTP/HTTPS listeners and security-group rules.
Keep the private preview configuration as a separate site. Do not duplicate its
`limit_req_zone`/`limit_conn_zone` declarations in another enabled configuration;
reuse these named zones. Preserve the private credential include, fixed API route
allowlist, real-client forwarding, request limits, and SPA fallback in the public
site. This guide intentionally does not auto-enable public access.
