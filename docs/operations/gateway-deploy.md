# MILO AI Gateway · Deployment Guide

The gateway is a plain Express + TypeScript service that proxies `/v1/recall/*`
to the MiniMax upstream. It runs anywhere Node 20+ runs. The current deployment
uses Huawei Flexus; the other hosting options below are reference instructions.

## Current deployment — 2026-10-10

**Superseding state — AI temporarily withdrawn at the owner's request (22:17):**
the owner suspects the MiniMax subscription/key has expired; this was not
independently diagnosed. AI rollout and filing-support work is paused.
On the live Huawei server, `milo-gateway` is stopped and disabled from boot;
its credentials and application files are retained. The root-domain Nginx
configuration responds with `503 / AI_DISABLED` for recall endpoints without
proxying upstream; `/health` reports `aiEnabled: false` and `aiStatus: paused`.
These responses were verified over server-local TLS after reload. Public
access remains subject to the filing block described below.

Source builds now default to AI disabled (`AI_ENABLED=false` for the gateway,
central availability flags for clients). Existing consent or saved personal
API keys cannot enable the shipping client paths. Restore only by a separate
owner request: verify provider entitlement and filing access, configure the
source flags, remove the Nginx pause responses, and explicitly re-enable the
backend service. The manual DNS-01 certificate renewal limitation below still
applies; stopping AI does not delete certificates or DNS records. The web and
iOS changes are source/build changes, not a new public site or store release.

The following rollout observations are historical, before the AI withdrawal:

**Current state (22:11):** source configuration, local test credentials, and
the installed HarmonyOS HAP target `https://milomood.xyz`. Its root-domain A
record was created at `22:04:40` with TTL 300 and verified using Google public
DNS. The server's bootstrap Nginx configuration has been backed up and switched
to the root domain. Public HTTP requests still return 403 from Huawei
`ADM/2.1.1` with block code `157`; the same path requested locally reaches
Nginx and returns 404. HTTP ACME validation failed with 403, but manual DNS-01
issuance subsequently succeeded. The root-domain TLS configuration is now
installed, with Nginx and the gateway active. Server-local TLS checks validate
the certificate normally; public Mac curl still fails with TLS error 35, and
Node public health, anonymous, and authorized probes all fail with
`ECONNRESET`. Root-domain public AI is not working; the native UI check failed
to connect and successfully displayed the local fallback described below.

The approved filing preview explicitly identifies APP `MILO-米洛`, domain
`milomood.xyz`, cloud server range `119.3.231.143-119.3.231.143`, and Beijing
cloud access. It does not list `api.milomood.xyz`. Huawei requires the actual
APP domain level to be filed:
[official domain rules](https://support.huaweicloud.com/icprb-icp/icp_01_0008.html).
Do not treat the earlier subdomain probes below as root-domain success. No
proxy or TLS-verification settings were weakened. The existing web preview
remains private.

- APP filing is complete: `京ICP备2026067150号-1A`; the subject filing number is
  `京ICP备2026067150号`. The console shows completion at `15:46:42`. This is an
  APP filing, not a website filing. The web service remains private on
  `127.0.0.1:8080`.
- `milomood.xyz` now resolves by A record to `119.3.231.143`. The native client
  uses this exact filed root domain, not the earlier `api` subdomain.
- The active backend release remains `/opt/milo-gateway/releases/2026-09-23`;
  the HTTPS rollout did not replace the running application version.
- MiniMax credentials remain on the server. Native device-test builds use a
  separate shared gateway token, injected only into a gitignored local resource.

### Root-domain certificate and server-local verification — 22:09–22:10

The issued certificate has CN `milomood.xyz` and expires at
`2027-01-08 13:10:35 GMT`. The `--tls` deployment completed. The following
requests used the root-domain SNI and Host against server-local port 443,
with ordinary certificate verification enabled (no `-k`):

| Server-local root-domain check | Observed result |
| --- | --- |
| `GET /health` | 200 |
| `/` | 404 |
| Anonymous recall POST | 401 |
| Authorized synthetic osmanthus-walk opening | 200, 1497 ms |
| Authorized follow-up response | 200, 986 ms |
| Authorized diary generation | 200, 859 ms |

These calls used synthetic test content and verify the installed certificate,
reverse proxy, authorization, and upstream path inside the server. They do
not establish public access: public HTTP remains blocked and public TLS
connections reset.

The root certificate uses **manual DNS-01** and does not currently renew
automatically. A running global `certbot.timer` does not supply its DNS
challenge. After public access is restored, switch renewal to webroot and
verify it with a dry run, or configure a DNS authentication hook. The temporary
`_acme-challenge` TXT record remains: deleting it required SMS operation
protection, so deletion was canceled without obtaining a code or disabling
the protection. The remaining validation TXT is harmless.

### Native UI verification — 22:11

The root-domain HAP on the existing Pura 90 emulator was exercised through
calm mood → descriptor continuation → past → yesterday → recall. It displayed
`✦ AI 开`, then `网络连接不可用。` and the local fallback
`「昨天」，你最先想起什么？`. Logs filtered to app PID 12866 recorded
`NETSTACK CURLcode 35` at `10-10 22:11:02.441`. This is a failed live AI
end-to-end check with working offline fallback, not an untested path or an AI
success. No historical user content was sent, no real user information was
entered, and no synthetic diary was saved. A back action was issued to return
to the home screen; its final screen state was awaiting confirmation.

Permission to submit a Huawei filing support ticket on the user's behalf has
been requested. No reply has been received and no ticket has been submitted.

### Earlier subdomain rollout history — not root-domain acceptance

The earlier `api.milomood.xyz` configuration used a dedicated Nginx HTTPS
entry to `127.0.0.1:8787`. Its Let's Encrypt certificate expires on
`2027-01-08`; `certbot.timer` was enabled and started, and the then-configured
`certbot renew --dry-run --run-deploy-hooks` succeeded. These facts refer to
the subdomain certificate. They do not establish automatic renewal for the
new root-domain manual DNS-01 certificate; its separate renewal work is
described above.

Earlier probes against `https://api.milomood.xyz` (before the block appeared):

| Check | Observed result |
| --- | --- |
| `GET /health` | 200 |
| Anonymous recall POST | 401 |
| `/` and `/v1/unknown` | 404 |
| Health request with a query string | 400 |
| Authorized synthetic osmanthus-walk opening | 200, 1415 ms |
| Authorized follow-up response | 200, 833 ms |
| Authorized diary generation | 200, 685 ms |

The three authorized calls used synthetic test content. They confirm those
individual requests only, not ongoing availability or final root-domain access.
The HarmonyOS live AI UI check subsequently failed with TLS error 35 and used
offline guidance. Public app distribution remains blocked on
AGC user-level authentication. Paid hosted-model access additionally requires
server-verified payment entitlements; membership is still a preview.

## Prerequisite

1. Get a MiniMax API key from the MiniMax platform console.
2. **Never** commit it. Inject it as an environment variable on the
   platform you pick.
3. The current deployment requires a separate `GATEWAY_BEARER_TOKEN` (at least 32 characters). Local device-test builds inject the same application token using the preparation tool below; never put the MiniMax key in the client. This shared token is not user authentication and is not suitable for public app distribution.
4. The executable entry is `src/main.ts` / `dist/main.js`; `server.ts` only exports the Express factory. Local and systemd processes bind to loopback by default. Containers set `HOST=0.0.0.0` internally and publish only to host loopback behind HTTPS.

## 0. Local sanity check

```bash
cd services/ai-gateway
cp .env.example .env
# edit .env, paste your key
npm install
npm test            # gateway contract and startup tests
npm run build       # tsc → dist/
npm run dev         # http://127.0.0.1:8787
# in another terminal:
curl http://127.0.0.1:8787/health
# expect: {"ok":true,"requestId":"req-..."}
```

## Option A · Vercel (zero-config, free tier)

```bash
npm i -g vercel
cd services/ai-gateway
vercel deploy --prod
```

Then in the Vercel dashboard:

- Project Settings → Environment Variables:
  - `MINIMAX_API_KEY` = your key (Production)
  - `MINIMAX_BASE_URL` = `https://api.minimax.chat/v1` (optional)
  - `MINIMAX_MODEL` = `MiniMax-M3` (optional)
  - `GATEWAY_BEARER_TOKEN` = a separate application token, at least 32 characters

The included `vercel.json` + `api/index.js` mount the Express app as a
single Serverless Function.

Health check:
```bash
curl https://<your-project>.vercel.app/health
```

## Option B · Fly.io (single region, containerized)

```bash
brew install flyctl
cd services/ai-gateway
fly launch --copy-config --no-deploy    # creates the app, uses fly.toml
fly secrets set MINIMAX_API_KEY=<your-key>
fly deploy
```

Health check (the included `fly.toml` already configures this on `/health`):
```bash
curl https://milo-gateway.fly.dev/health
```

## Option C · Railway (one-click)

```bash
npm i -g @railway/cli
cd services/ai-gateway
railway init
railway variables set MINIMAX_API_KEY=<your-key>
railway up
```

Railway auto-detects the included `Dockerfile` and exposes `/health`.

## Option D · Plain Docker (your own VPS)

```bash
cd services/ai-gateway
cp .env.example .env   # edit, paste key
docker build -t milo-gateway .
docker run --rm -d \
  --name milo-gateway \
  -p 127.0.0.1:8787:8787 \
  --env-file .env \
  milo-gateway
```

Health check:
```bash
curl http://127.0.0.1:8787/health
```

## Where to plug the URL into the HarmonyOS app

`apps/harmony/entry/src/main/ets/core/config/AppConfig.ets` now sets
`GATEWAY_BASE_URL` to `https://milomood.xyz` and the request timeout to
30 seconds. Its token constant stays empty. `LocalGatewayCredential` loads
`entry/src/main/resources/rawfile/gateway-credentials.local.json`, validates
the exact configured URL and token format, and supplies the local build's
credential. Missing or invalid credentials produce a clear status and leave
offline guidance available.

For the current local device-test build, prepare the resource from an explicit
env file. The tool copies only `GATEWAY_BEARER_TOKEN`, binds it to the fixed
gateway URL, and writes a mode-0600 file covered by an exact Git ignore rule.
It never copies `MINIMAX_API_KEY`.

Rebuild:
```bash
cd apps/harmony
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node tools/prepare-gateway-config.mjs --env-file /absolute/path/to/milo-gateway.env
./hvigorw assembleHap
```

The user selects the MILO default model and confirms the data-sending purpose
before requests use the gateway. Existing BYOK choices remain intact. The
resource is bundled into the test HAP, so Git exclusion does not make the
shared token a private user credential; replace this mechanism with AGC
user-level authentication before public distribution.

The repository's `./hvigorw` wrapper blocks `assembleApp`, `product=release`,
and `buildMode=release` builds while the local device-test credential resource
exists. Normal debug builds, tests, and standalone clean operations remain
available. This guard applies only to the wrapper: direct IDE or bundled
Hvigor invocation can bypass it, so neither path should produce a distributable
release while the shared credential is present. Wrapper contract tests pass
7/7, and preparation-tool tests pass 5/5 (four safe-file-writing cases and one
exact filed-domain binding case).

## Security checklist

- [ ] Gateway is HTTPS (Vercel / Fly / Railway do this automatically)
- [ ] `MINIMAX_API_KEY` is set as a secret, never committed
- [ ] Rate limit stays at the default (60/min/IP)
- [ ] Install and verify `deploy/logrotate.conf` for systemd deployments; other platforms need their own retention policy.
- [ ] The HarmonyOS bundle name stays `com.milo.echoes` (matches AGC)

## Huawei Flexus deployment

The original purchase and September rollout history are tracked in
[huawei-release-2026-09-15.md](huawei-release-2026-09-15.md). The verified October
HTTPS state is recorded above. The `services/ai-gateway/deploy/` directory
contains systemd, Nginx and log rotation templates.
