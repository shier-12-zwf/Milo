# AGENTS.md

MILO — a personal diary/recall app with three clients (web, HarmonyOS, planned iOS/Android) sharing one Express AI gateway. All data is local (localStorage / device storage); there is no user backend.

## Repository layout

- npm workspaces: `apps/web` (React 19 + Vite) and `services/ai-gateway` (Express + TS). Root `package.json` scripts proxy into workspaces with `-w`.
- `apps/harmony/` is **not** an npm workspace — it is a HarmonyOS/ArkTS project with its own toolchain (see below).
- `server/acp-bridge.mjs` is a root-level Node script (WebSocket ↔ Codex ACP bridge), not a workspace.
- `docs/compliance/` (release artifacts), `docs/operations/` (gateway deploy, AGC submission), `docs/superpowers/plans/` (multi-platform strategy).

## Commands

```bash
npm run dev:all      # web (5173) + ACP bridge (8787) together
npm run dev          # web only
npm run server       # ACP bridge only
npm run gateway      # ai-gateway dev server (also port 8787!)
npm test             # web tests ONLY (node:test, 133 tests)
npm run test:gateway # gateway tests (15 tests)
npm run lint         # oxlint from repo root
npm run build        # web: tsc -b && vite build (tsc is the typecheck; no separate typecheck script)
```

Gotchas:

- **Port collision**: the ACP bridge and the ai-gateway both default to 8787. The web client hardcodes `ws://hostname:8787` (`apps/web/src/lib/acp.ts`), so overriding `ACP_BRIDGE_PORT` on the server breaks the web client. Run them separately, not both at once.
- Web and gateway tests use plain `node --test` (with `--experimental-strip-types` / `tsx`), no Jest/Vitest. Run a single file with e.g. `node --experimental-strip-types --test apps/web/tests/moodOrbModel.test.ts` from `apps/web`.
- Some web tests read repo files rather than code (e.g. `tests/pagesDeployment.test.ts` asserts the Pages workflow keeps `--base=/Milo/`), so they can fail on edits to CI config.

## AI / fallback contract (core invariant)

Every AI-dependent path must have an offline fallback (`FallbackGuide` / `fallbackDiary` on both web and HarmonyOS). The product must fully work with no AI, no network, no Codex login. Tests run without any API keys.

- Web chat uses Codex via ACP: requires local `~/.codex` login; `ACP_MODEL` env overrides the default model. If unavailable, the app silently degrades to scripted guidance — don't "fix" this by making the bridge a hard dependency.
- Gateway proxies `/v1/recall/*` to MiniMax. `MINIMAX_API_KEY` comes from env (see `services/ai-gateway/.env.example`); never commit it. Deploy options: `docs/operations/gateway-deploy.md`.

## HarmonyOS app (`apps/harmony/`)

Separate toolchain — do not build it with npm. See `apps/harmony/README.md` for the full verification matrix.

- DevEco Studio 6.1.1 + HarmonyOS SDK (API 24). The `./hvigorw` wrapper expects DevEco at `/Applications/DevEco-Studio.app/Contents` (override with `DEVECO_STUDIO_HOME`) and uses DevEco's bundled Node/Hvigor/JBR/HDC; no system Java needed. It regenerates the ignored `local.properties` on every invocation.
- Build/test: `./hvigorw test`, `./hvigorw assembleHap` (unsigned HAP at `entry/build/default/outputs/default/`). Signing stays local and is never committed.
- Shell contract test uses DevEco's bundled Node: `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node --test tests/shell-contract.test.mjs`.
- `entry/src/main/ets/core/config/AppConfig.ets` `GATEWAY_BASE_URL` is deliberately empty (offline-first); never set it to a loopback address. Bundle name must stay `com.milo.echoes` (matches AGC).
- First launch requires AGC 认证服务 login (`@hw-agconnect/auth`, config in `entry/src/main/resources/rawfile/agconnect-services.json`): email+code registers, email+password logs in returning users. The only offline escape is the owner backdoor email `milo`. After a successful login everything works offline; don't "fix" the gate by removing it.

## CI / release

- `.github/workflows/deploy-pages.yml` deploys `apps/web/dist` to GitHub Pages on push to `main` with base path `/Milo/`.
- Pre-release verification matrix (web tests → web build → gateway tests/build → harmony clean+test+assembleHap) is in `apps/harmony/README.md`; `docs/compliance/release-checklist.md` has the reviewer test path.
