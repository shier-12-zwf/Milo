# MILO HarmonyOS

Bundle name: `com.milo.echoes`

**2026-10-10 update:** AI is temporarily withdrawn at the owner's request.
The current build uses a product-level off switch, hides AI/settings/membership
entry points, and runs recall and diary generation locally even when saved
preferences previously enabled hosted or personal AI. Existing keys, account
login, diaries, avatars and export are retained. The live gateway service has
also been stopped and its API proxy returns `AI_DISABLED` without calling
MiniMax. Earlier AI connection records below are historical, not a request to
resume the rollout.

Stage-model ArkTS application that mirrors the MILO web diary/recall
experience for HarmonyOS devices. Architecture, screen flow, and AI
fallback contract are identical to the web build; only the render layer
changes. See `docs/superpowers/plans/2026-08-08-harmonyos-native-replica.md`
for the multi-platform strategy and `docs/compliance/` for the release
artifacts.

## Toolchain

- DevEco Studio 6.1.1, build `DS-243.24978.46.36.611300`
- HarmonyOS SDK `6.1.1.125` (API 24): OpenHarmony base components (ArkTS/Ets, Js, Native, Previewer, Toolchains) plus HMS components
- Node.js `v18.20.1`
- OHPM `6.1.2.285`
- Hvigor `6.24.4`
- HDC `3.2.0d`
- JetBrains Runtime `21.0.8` (`JBR-21.0.8+9-1038.71-jcef`)

The reproducible wrapper expects DevEco Studio at `/Applications/DevEco-Studio.app/Contents` unless `DEVECO_STUDIO_HOME` is set. It uses DevEco's bundled Node, Hvigor, JBR, HDC, and HarmonyOS SDK; no system Java is required. Hvigor resolves the all-in-one SDK through `sdk-pkg.json` inside `sdk/default`, so the wrapper points `sdk.dir`/`DEVECO_SDK_HOME` at the SDK root (the parent of `default`) and regenerates ignored `local.properties` before every invocation.

## Source layout

```
entry/src/main/ets
├── core/
│   ├── data/         # MapKVStorage + EntryRepository + RecallSessionRepository
│   ├── flow/         # RecallMachine state machine
│   ├── model/        # Domain types, Moods, MoodAssets
│   ├── network/      # AiGatewayClient + typed HTTP transport
│   ├── system/       # SpeechInput, Haptics, CardRenderer, ShareService
│   └── theme/        # MiloTheme tokens
├── features/
│   ├── conversation/ # ChatScreen, ConversationController, FallbackGuide
│   ├── diary/        # DiaryScreen
│   ├── home/         # HomeScreen
│   ├── mood/         # MoodOrbitCarousel + gesture model
│   ├── recall/       # ClassifyScreen, NowNoteScreen, PastTimeScreen
│   ├── share/        # ShareCardScreen
│   └── timeline/     # TimelineScreen, DetailScreen, CardScreen
└── pages/Index.ets   # Root navigation + draft hydration
```

Tests live in `entry/src/ohosTest/ets/test/` and are wired in
`entry/src/test/List.test.ets`. The test suite covers domain types, the
recall state machine, repositories, the offline fallback flow, the
mood-orbit swipe model, the AI gateway client, the conversation
controller, the system adapters, and the card renderer contract.

## Install dependencies

```bash
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install --all
```

The generated `oh-package-lock.json5` pins `@ohos/hypium` 1.0.28 and `@ohos/hamock` 1.0.0.

## Build and test

```bash
./hvigorw clean
./hvigorw assembleHap                       # debug HAP (default product)
./hvigorw assembleHap --mode module -p product=release -p buildMode=release   # release HAP
./hvigorw assembleApp --mode project -p product=release -p buildMode=release  # .app for AGC upload
./hvigorw test
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node --test tests/shell-contract.test.mjs
```

The unsigned debug HAP is generated at `entry/build/default/outputs/default/entry-default-unsigned.hap`; the signed release HAP at `entry/build/release/outputs/default/entry-default-signed.hap`. Signing must remain local and is intentionally not committed.

Signing materials (all local, never committed):

- debug: `~/.ohos/config/default_harmony_*.p12/.cer/.p7b` (auto-generated via `devecocli signature generate`)
- release: `~/.ohos/config/release_harmony_milo.cer` + `release_harmony_milo.p7b` (AGC 发布证书 `milo_release.cer` + 发布 Profile `milo_release`, both valid to 2029-09-12), signing with the same debug p12 keypair; wired as the `release` product/signingConfig in `build-profile.json5`

## Verification matrix

Run from the repo root after every release candidate:

```bash
npm test                       # web tests (146 as of 2026-10-10)
npm run build                  # web build to apps/web/dist
npm -w services/ai-gateway test
npm -w services/ai-gateway run build
cd apps/harmony && ./hvigorw clean && ./hvigorw test && ./hvigorw assembleHap && ./hvigorw assembleHap --mode module -p product=release -p buildMode=release
```

The release step is intentionally blocked while the local device-test gateway
credential exists; complete user-level authentication before a public release.

Last verified locally (2026-10-10):

- `npm test` — 146 / 146 pass; `npm run build` succeeds.
- `npm -w services/ai-gateway test` — 23 / 23 pass; the gateway TypeScript build succeeds.
- `./hvigorw test` — 172 / 172 Hypium tests pass.
- Shell contract — 7 / 7 pass.
- Gateway preparation tests — 5 / 5 pass (safe writing and exact filed-domain binding).
- `./hvigorw assembleHap` — signed debug HAP builds successfully, including the corrected root-domain configuration. The root-domain HAP has been installed in place and restarted on the existing Pura 90 emulator; the home screen still reports five saved memories. The 22:11 root-domain UI AI check failed with a network error and correctly displayed offline guidance. A release `.app` build is not covered by this record.

## Default gateway configuration

As of 2026-10-10 at 22:11, `AppConfig.ets` points to the exact APP-filed domain,
`https://milomood.xyz`, with a 30-second timeout. Its A record to
`119.3.231.143` was created at 22:04:40 with TTL 300 and verified using Google
public DNS. The server configuration has been backed up and root-domain TLS
installed; Nginx and the gateway are active. After HTTP ACME validation failed
with 403, manual DNS-01 issuance succeeded: CN `milomood.xyz`, expiry
`2027-01-08 13:10:35 GMT`. Server-local root-domain SNI/Host requests verify
TLS normally and return health 200, root-path 404, anonymous recall 401, and
three authorized synthetic AI successes (1497/986/859 ms).

Public HTTP still returns Huawei `ADM/2.1.1` 403 with block code 157, while
the same path requested locally returns Nginx 404. Public Mac curl fails with
TLS error 35; public Node health, anonymous, and authorized requests all fail
with `ECONNRESET`. No root-domain public AI success is recorded. The manual
DNS-01 certificate has no automatic renewal yet: switch to webroot after
public access is restored and dry-run it, or configure DNS authentication
hooks. The existing global `certbot.timer` is not sufficient. The temporary
ACME TXT record remains because deletion required SMS operation protection;
that protection was left enabled.

Earlier probes to `api.milomood.xyz` returned successful synthetic AI results,
but later access hit the provider's filing block and the native app fell back
offline. Those subdomain results do not verify the root domain. The deployed
application remains at `/opt/milo-gateway/releases/2026-09-23`.

At 22:11 the native flow (calm → descriptors → past → yesterday → recall)
showed `✦ AI 开`, `网络连接不可用。`, and the offline prompt
`「昨天」，你最先想起什么？`. App PID 12866 logs recorded
`NETSTACK CURLcode 35` at `10-10 22:11:02.441`. Live AI failed; the fallback
worked. No historical diary data or real user information was sent and no
test diary was saved. Permission for a Huawei filing support ticket has been
requested; no ticket has been submitted.

Local device-test builds load a URL-bound shared Gateway Token from the ignored
`entry/src/main/resources/rawfile/gateway-credentials.local.json`. Prepare it
from an explicitly supplied server env file before building:

```bash
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node tools/prepare-gateway-config.mjs --env-file /absolute/path/to/milo-gateway.env
./hvigorw assembleHap
```

The helper copies only `GATEWAY_BEARER_TOKEN`, never the MiniMax key. Without a
valid resource the app reports the missing configuration and retains offline
guidance. The token is included in the local test HAP, so this distribution
mechanism must be replaced by AGC user-level authentication before public
release. A shared token does not establish membership or authorize payment
benefits. See [deployment state and HTTPS verification](../../docs/operations/gateway-deploy.md).

`./hvigorw` prevents `assembleApp`, `product=release`, and `buildMode=release`
builds while that local credential exists. Normal debug builds, tests, and
standalone clean operations remain available. This is a wrapper-level guard;
direct IDE or bundled Hvigor builds bypass it and must not be used to make a
public release carrying the shared credential.

## Compliance and release

The completed APP filing is `京ICP备2026067150号-1A` (subject filing:
`京ICP备2026067150号`). The approved preview identifies APP `MILO-米洛`,
domain `milomood.xyz`, the cloud server range
`119.3.231.143-119.3.231.143`, and Beijing cloud access. This does not establish
a website filing; the separate Web service remains private at `127.0.0.1:8080`.

### Personal settings and AI providers

`我的` now includes a planet avatar (replaceable via the system photo picker), local JSON/Markdown diary export, and AI provider settings. AI defaults on for new recordings, using the MILO hosted model for new accounts after confirmation of the data-sending purpose. Existing personal-model choices are retained. Personal keys use device-only HarmonyOS Asset Store and requests go directly to the configured HTTPS Chat Completions endpoint. BYOK requires no membership. The MILO hosted-model monthly subscription is a **preview only** until payment verification and server-side entitlements exist; choosing the default model does not grant paid membership. Development gateway access uses the local test-build credential described above. See [implementation, verification and membership proposal](../../docs/operations/harmony-personal-ai-membership.md).

- `docs/compliance/data-flow.md` — every data category, trigger, retention, and processor
- `docs/compliance/permissions.md` — `ohos.permission.MICROPHONE` matrix
- `docs/compliance/release-checklist.md` — reviewer test path (fresh install → privacy → now → past AI → forced offline → share → deletion)

The MILO default model uses the MiniMax gateway; personal-model mode
calls the user's selected provider directly. The local `FallbackGuide` and `fallbackDiary` paths cover
every AI failure so the diary flow always completes offline. The product
is a personal diary and recall tool, **not** a mental-health diagnosis or
treatment service.
