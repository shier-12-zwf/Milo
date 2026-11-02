# MILO HarmonyOS Native Replica Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, and prepare for release an ArkTS + ArkUI HarmonyOS replica of the existing MILO Web MVP, backed by a MiniMax AI gateway and a complete offline scripted fallback.

**Architecture:** The HarmonyOS Stage-model client lives in `apps/harmony` and owns navigation, native persistence, system capabilities, and rendering. `services/ai-gateway` is a TypeScript HTTP service that hides the MiniMax credential, validates requests, streams model output, and returns stable error codes; the client always retains a local scripted path.

**Tech Stack:** HarmonyOS Stage model, ArkTS, ArkUI, ArkData, HarmonyOS system kits, Hvigor, Hypium, Node.js 20+, TypeScript, Fastify, Vitest, MiniMax OpenAI-compatible Chat Completions API.

## Global Constraints

- `apps/web` is the only source of truth for existing product behavior, Chinese copy, mood order, and visual appearance.
- Do not use WebView for any core screen.
- Reuse original image and icon files without generation, redrawing, or lossy conversion.
- Copy mood sheets from `docs/superpowers/concepts/mood-orbs`, never from `apps/web/dist`.
- Keep real `MINIMAX_API_KEY` values out of source, client resources, logs, test snapshots, and Git.
- A failed network, speech, AI, card-rendering, or sharing operation must not prevent local diary creation and retrieval.
- Preserve all unrelated dirty-worktree changes. Stage and commit only files named by the current task.
- Use the current stable DevEco Studio and HarmonyOS SDK available from Huawei at execution time; record exact installed versions in `apps/harmony/README.md`.
- Use `com.milo.echoes` as the provisional bundle name until the user supplies the final AppGallery Connect identity.
- Use phone portrait as the first visual baseline; also verify safe areas, keyboard avoidance, system font scaling, and application restoration.

---

## File Structure

```text
apps/harmony/
  AppScope/app.json5                         # application identity and icon
  build-profile.json5                       # project build targets
  hvigorfile.ts                             # project build entry
  oh-package.json5                          # project package metadata
  README.md                                 # reproducible DevEco/SDK/build instructions
  entry/
    build-profile.json5
    hvigorfile.ts
    oh-package.json5
    src/main/module.json5                   # UIAbility and permissions
    src/main/ets/entryability/EntryAbility.ets
    src/main/ets/pages/Index.ets            # app root
    src/main/ets/core/model/Domain.ets       # stable domain types
    src/main/ets/core/model/Moods.ets        # mood catalogue and asset mapping
    src/main/ets/core/flow/RecallMachine.ets # navigation/state transition rules
    src/main/ets/core/data/EntryRepository.ets
    src/main/ets/core/network/AiGatewayClient.ets
    src/main/ets/core/system/*.ets           # speech, haptics, image/share adapters
    src/main/ets/features/**                 # one focused component per screen/feature
    src/main/resources/base/media/           # copied original assets
    src/main/resources/base/element/string.json
    src/ohosTest/ets/test/**                 # device/component tests
    src/test/                        # pure ArkTS unit tests where supported
services/ai-gateway/
  package.json
  tsconfig.json
  src/config.ts
  src/contracts.ts
  src/prompts.ts
  src/minimax.ts
  src/server.ts
  tests/*.test.ts
  .env.example
docs/compliance/
  data-flow.md
  permissions.md
  release-checklist.md
docs/visual-baselines/
  README.md
```

## Task 1: Reproducible HarmonyOS Toolchain and Buildable Shell

**Files:**
- Create: `apps/harmony/**` from the official Empty Ability Stage-model template
- Create: `apps/harmony/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: current stable DevEco Studio and HarmonyOS SDK.
- Produces: `apps/harmony/hvigorw` and a debug HAP that launches `pages/Index`.

- [ ] **Step 1: Install and record the native toolchain**

Install DevEco Studio from Huawei's official distribution, accept its license, install the recommended HarmonyOS SDK and a phone emulator image, then record the exact versions:

Create `apps/harmony/README.md` with the heading `# MILO HarmonyOS`, the bundle name `com.milo.echoes`, and the commands `./hvigorw assembleHap` and `./hvigorw test`. Under a `Toolchain` heading, copy the complete DevEco Studio build identifier from **About DevEco Studio** and every selected HarmonyOS SDK package/API version from **SDK Manager**. Do not write a guessed version or an unresolved marker.

- [ ] **Step 2: Create the Stage-model project and verify the initial build**

Create an Empty Ability project at `apps/harmony`, set bundle name `com.milo.echoes`, choose ArkTS, and run:

```bash
cd apps/harmony
./hvigorw clean
./hvigorw assembleHap
```

Expected: exit code 0 and one debug `.hap` below `entry/build/default/outputs/`.

- [ ] **Step 3: Replace the template page with a smoke-test root**

```ts
@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('MILO')
        .fontSize(28)
        .fontWeight(FontWeight.Medium)
      Text('回到过去的某一天')
        .fontSize(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#050608')
  }
}
```

- [ ] **Step 4: Add build-output ignores and verify only intended files appear**

Append the exact generated directories observed after the build, at minimum:

```gitignore
apps/harmony/.hvigor/
apps/harmony/.idea/
apps/harmony/**/build/
apps/harmony/oh_modules/
```

Run `git status --short apps/harmony .gitignore` and verify no HAP, cache, local signing material, or IDE user state is tracked.

- [ ] **Step 5: Run the shell in the emulator**

Expected: dark full-screen root displays `MILO` and `回到过去的某一天`, with no crash or clipped safe-area content.

- [ ] **Step 6: Commit the buildable shell**

```bash
git add .gitignore apps/harmony
git commit -m "feat(harmony): scaffold native Stage application"
```

## Task 2: Domain Model, Mood Catalogue, and Recall State Machine

**Files:**
- Create: `apps/harmony/entry/src/main/ets/core/model/Domain.ets`
- Create: `apps/harmony/entry/src/main/ets/core/model/Moods.ets`
- Create: `apps/harmony/entry/src/main/ets/core/flow/RecallMachine.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/Domain.test.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/RecallMachine.test.ets`

**Interfaces:**
- Produces: `MoodId`, `MoodState`, `ChatMessage`, `DiaryEntry`, `Draft`, `Screen`, `MOODS`, `transition(state, event): RecallState`.

- [ ] **Step 1: Write failing catalogue and transition tests**

```ts
it('keeps the exact web mood order', 0, () => {
  expect(MOODS.map(item => item.id).join(',')).assertEqual(
    'very-low,low,heavy,calm,okay,bright,joyful,lonely,sad,angry,afraid,disappointed,anxious,aggrieved,embarrassed'
  )
})

it('routes a past draft through time and chat', 0, () => {
  let state = initialRecallState()
  state = transition(state, { type: 'SELECT_MOOD', moodId: 'calm' })
  state = transition(state, { type: 'CLASSIFY', kind: 'past' })
  expect(state.screen.name).assertEqual('past-time')
  state = transition(state, { type: 'SET_TIME_MARK', value: '去年夏天' })
  expect(state.screen.name).assertEqual('chat')
})
```

- [ ] **Step 2: Run tests and confirm missing-symbol failures**

Run `cd apps/harmony && ./hvigorw test`.

Expected: FAIL because `MOODS`, `initialRecallState`, and `transition` do not exist.

- [ ] **Step 3: Implement stable domain types and exact catalogue**

Define string unions equivalent to `apps/web/src/types.ts`, immutable value objects, and all fifteen mood records. Preserve `valence`, labels, `emotionId`, entry kind, transcript, diary toggle, and sticker-template fields. Use explicit event variants:

```ts
export type RecallEvent =
  | { type: 'SELECT_MOOD'; moodId: MoodId }
  | { type: 'CLASSIFY'; kind: EntryKind }
  | { type: 'SET_NOTE'; value: string }
  | { type: 'SET_TIME_MARK'; value: string }
  | { type: 'APPEND_MESSAGE'; message: ChatMessage }
  | { type: 'SET_DIARY'; value: string }
  | { type: 'OPEN_TIMELINE' }
  | { type: 'OPEN_DETAIL'; entryId: string }
  | { type: 'BACK' }
  | { type: 'RESET' }
```

- [ ] **Step 4: Implement pure deterministic transitions**

`transition` must return a new state, reject invalid forward transitions by returning the unchanged state, retain draft content on back navigation, and clear the draft only on `RESET`.

- [ ] **Step 5: Run all HarmonyOS tests**

Run `cd apps/harmony && ./hvigorw test`.

Expected: PASS for exact mood order, now path, past path, back navigation, invalid transitions, and reset.

- [ ] **Step 6: Commit the domain foundation**

```bash
git add apps/harmony/entry/src/main/ets/core apps/harmony/entry/src/ohosTest/ets/test
git commit -m "feat(harmony): add recall domain and state machine"
```

## Task 3: Original Asset Inventory and Native Mood Rendering

**Files:**
- Create: `docs/visual-baselines/README.md`
- Create: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_01.png`
- Create: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_02.png`
- Create: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_03.png`
- Create: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_04.png`
- Create: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_05.png`
- Create: `apps/harmony/entry/src/main/ets/features/mood/MoodPlanet.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/MoodAssets.test.ets`

**Interfaces:**
- Consumes: `MOODS` and the five original transparent three-panel sheets.
- Produces: `MoodPlanet({ moodId, width })`, asset SHA-256 ledger, Web baseline instructions.

- [ ] **Step 1: Create a failing asset-integrity test**

Test that every mood maps to one of five media resources and panel `0`, `1`, or `2`; test the special anxious focus offset and the Web constants `1748 x 2700` and panel count `3`.

- [ ] **Step 2: Copy original files without transformation and record hashes**

Use `cp`, not image conversion:

```bash
cp docs/superpowers/concepts/mood-orbs/01-very-low-low-heavy-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_01.png
cp docs/superpowers/concepts/mood-orbs/02-calm-okay-bright-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_02.png
cp docs/superpowers/concepts/mood-orbs/03-joyful-lonely-sad-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_03.png
cp docs/superpowers/concepts/mood-orbs/04-angry-afraid-disappointed-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_04.png
cp docs/superpowers/concepts/mood-orbs/05-anxious-aggrieved-embarrassed-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_05.png
shasum -a 256 docs/superpowers/concepts/mood-orbs/*-transparent.png apps/harmony/entry/src/main/resources/base/media/mood_sheet_*.png
```

Pair source and destination hashes in `docs/visual-baselines/README.md`; every pair must match.

- [ ] **Step 3: Implement panel clipping**

`MoodPlanet` renders the full three-panel sheet inside a clipped viewport, translates it by the mapped panel and focus offset, preserves transparency, sets an accessibility description from the mood label, and disables independent image interaction.

- [ ] **Step 4: Run asset and component tests**

Run `cd apps/harmony && ./hvigorw test`.

Expected: all fifteen mappings pass and copied-file hashes match their sources.

- [ ] **Step 5: Commit assets and renderer**

```bash
git add apps/harmony/entry/src/main/resources/base/media apps/harmony/entry/src/main/ets/features/mood docs/visual-baselines apps/harmony/entry/src/ohosTest/ets/test/MoodAssets.test.ets
git commit -m "feat(harmony): reuse original mood assets"
```

## Task 4: Native Entry Repository and Draft Restoration

**Files:**
- Create: `apps/harmony/entry/src/main/ets/core/data/EntryRepository.ets`
- Create: `apps/harmony/entry/src/main/ets/core/data/RecallSessionRepository.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/EntryRepository.test.ets`

**Interfaces:**
- Produces: `list(): Promise<DiaryEntry[]>`, `get(id): Promise<DiaryEntry | undefined>`, `save(entry): Promise<void>`, `remove(id): Promise<void>`, `saveDraft(state): Promise<void>`, `loadDraft(): Promise<RecallState | undefined>`, `clearDraft(): Promise<void>`.

- [ ] **Step 1: Write failing repository tests**

Cover newest-first ordering, update-by-ID, deletion, malformed-record isolation, empty first launch, and draft round-trip. Use a temporary test store and fixed timestamps.

- [ ] **Step 2: Verify tests fail before implementation**

Run `cd apps/harmony && ./hvigorw test`.

Expected: FAIL because repository classes are missing.

- [ ] **Step 3: Implement versioned persistence**

Store an envelope with explicit schema version:

```ts
export interface EntryEnvelope {
  schemaVersion: 1
  entries: DiaryEntry[]
}
```

Validate parsed values before exposing them. Do not report success until the native persistence write resolves. Keep draft state under a separate key so a damaged draft cannot hide saved entries.

- [ ] **Step 4: Run repository and full domain suites**

Expected: PASS, including malformed data and restoration.

- [ ] **Step 5: Commit persistence**

```bash
git add apps/harmony/entry/src/main/ets/core/data apps/harmony/entry/src/ohosTest/ets/test/EntryRepository.test.ets
git commit -m "feat(harmony): persist diaries and recall drafts"
```

## Task 5: Navigation Shell and Complete Offline Product Flow

**Files:**
- Modify: `apps/harmony/entry/src/main/ets/pages/Index.ets`
- Create: `apps/harmony/entry/src/main/ets/features/home/HomeScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/recall/ClassifyScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/recall/NowNoteScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/recall/PastTimeScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/conversation/ChatScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/diary/DiaryScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/timeline/TimelineScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/timeline/DetailScreen.ets`
- Create: `apps/harmony/entry/src/main/ets/features/conversation/FallbackGuide.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/OfflineFlow.test.ets`

**Interfaces:**
- Consumes: state machine, repositories, mood renderer.
- Produces: all Web-equivalent screens and an offline end-to-end path.

- [ ] **Step 1: Write a failing offline flow test**

Drive the app state through `calm -> past -> 去年夏天 -> five user answers -> diary -> save -> timeline -> detail`. Assert the fallback opening and five exact replies match `apps/web/src/lib/guide.ts`, and the saved diary uses first person.

- [ ] **Step 2: Implement `FallbackGuide` and local diary generation first**

Port `opening()`, all five `next()` strings, `isWrappingUp()`, `fallbackDiary()`, and transcript formatting exactly. Add a constructor that can restore the current step from persisted state.

- [ ] **Step 3: Implement screen components in existing Web order**

Each screen accepts data and callbacks; it must not call persistence directly. `Index.ets` owns the current `RecallState`, invokes repositories, and maps `screen.name` to one component. Copy visible strings from the corresponding Web page rather than paraphrasing them.

- [ ] **Step 4: Persist state at meaningful boundaries**

Save draft after mood selection, classification, time mark, each sent message, and diary edit. Save entries only on explicit user confirmation. Clear draft only after a successful save or explicit reset.

- [ ] **Step 5: Run automated and emulator flow tests**

Run `cd apps/harmony && ./hvigorw test`, then manually complete both now and past branches with network disabled.

Expected: both branches save, survive process termination, appear newest-first, and open in detail.

- [ ] **Step 6: Commit the offline vertical slice**

```bash
git add apps/harmony/entry/src/main/ets/pages apps/harmony/entry/src/main/ets/features apps/harmony/entry/src/ohosTest/ets/test/OfflineFlow.test.ets
git commit -m "feat(harmony): complete offline recall flow"
```

## Task 6: Pixel-Faithful Mood Interaction and Screen Styling

**Files:**
- Modify: `apps/harmony/entry/src/main/ets/features/**/*.ets`
- Create: `apps/harmony/entry/src/main/ets/features/mood/MoodOrbitCarousel.ets`
- Create: `apps/harmony/entry/src/main/ets/features/mood/Starfield.ets`
- Create: `apps/harmony/entry/src/main/ets/core/theme/MiloTheme.ets`
- Modify: `docs/visual-baselines/README.md`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/MoodInteraction.test.ets`

**Interfaces:**
- Produces: continuous drag carousel, deterministic index selection, shared theme tokens, screenshot ledger.

- [ ] **Step 1: Capture Web mobile baselines**

Run the existing Web app at its established mobile viewport and capture Home, Classify, NowNote, PastTime, Chat, Diary, Card, Timeline, and Detail. Record viewport, route/actions, filename, and commit hash in `docs/visual-baselines/README.md`.

- [ ] **Step 2: Write failing pure gesture tests**

Port the direction, threshold, wraparound, and selected-index contracts from `apps/web/src/components/moodSwipeModel.ts` and `apps/web/tests/moodSwipeModel.test.ts` before implementing the ArkTS gesture model.

- [ ] **Step 3: Implement theme, starfield, orbit, and gestures**

Use constants extracted from current Web CSS for colors, spacing, typography, opacity, and timings. Render stars deterministically from a fixed seed so screenshots are stable. The orbit must preserve Web mood order, drag direction, selection snapping, and accessible tap targets.

- [ ] **Step 4: Match every secondary screen**

For each baseline, adjust ArkUI layout using the same visible hierarchy and asset crops. Do not compensate by editing source PNGs. Record any platform-required difference with reason and screenshot.

- [ ] **Step 5: Run screenshot and interaction validation**

Expected: no missing assets, clipped primary actions, reversed gestures, unreadable text, or uncontrolled layout shift at normal system font size.

- [ ] **Step 6: Commit visual parity**

```bash
git add apps/harmony/entry/src/main/ets/features apps/harmony/entry/src/main/ets/core/theme docs/visual-baselines apps/harmony/entry/src/ohosTest/ets/test/MoodInteraction.test.ets
git commit -m "feat(harmony): match Web visuals and mood interaction"
```

## Task 7: MiniMax AI Gateway

**Files:**
- Modify: `package.json`
- Create: `services/ai-gateway/package.json`
- Create: `services/ai-gateway/tsconfig.json`
- Create: `services/ai-gateway/.env.example`
- Create: `services/ai-gateway/src/config.ts`
- Create: `services/ai-gateway/src/contracts.ts`
- Create: `services/ai-gateway/src/prompts.ts`
- Create: `services/ai-gateway/src/minimax.ts`
- Create: `services/ai-gateway/src/server.ts`
- Test: `services/ai-gateway/tests/server.test.ts`
- Test: `services/ai-gateway/tests/prompts.test.ts`

**Interfaces:**
- Produces: `POST /v1/recall/open`, `POST /v1/recall/respond`, `POST /v1/recall/diary`, `GET /health`.
- Error envelope: `{ code: 'AI_UNAVAILABLE' | 'RATE_LIMITED' | 'INVALID_REQUEST' | 'CONTENT_BLOCKED'; retryable: boolean; requestId: string }`.

- [ ] **Step 1: Write failing HTTP contract tests**

Use an injected fake MiniMax transport. Test missing fields return 400, missing server key fails startup, upstream timeout returns `AI_UNAVAILABLE`, supplier sensitivity flags return `CONTENT_BLOCKED`, logs exclude message text and authorization, and successful requests return the expected text.

- [ ] **Step 2: Run gateway tests and confirm failure**

Run `npm -w services/ai-gateway test`.

Expected: FAIL because the workspace and server do not exist.

- [ ] **Step 3: Add workspace and configuration**

Add `services/ai-gateway` to root workspaces. `.env.example` contains names only:

```dotenv
MINIMAX_API_KEY=
MINIMAX_BASE_URL=https://api.minimaxi.com/v1
MINIMAX_MODEL=MiniMax-M2.7
PORT=8788
AI_TIMEOUT_MS=20000
```

Validate all configuration at startup and redact secrets in errors.

- [ ] **Step 4: Port prompts and implement MiniMax transport**

Port the exact opening and diary constraints from `apps/web/src/lib/guide.ts`. Call `${MINIMAX_BASE_URL}/chat/completions` with Bearer authorization. Keep the model configurable and map MiniMax input/output sensitivity metadata to `CONTENT_BLOCKED`.

- [ ] **Step 5: Implement bounded public routes**

Validate body sizes, mood IDs, transcript roles, maximum message count, and maximum text length. Apply per-client rate limiting. Generate a request ID for every call. Never include raw input in logs.

- [ ] **Step 6: Run tests and a no-secret scan**

```bash
npm -w services/ai-gateway test
npm -w services/ai-gateway run build
rg -n "Bearer [A-Za-z0-9_-]{20,}|MINIMAX_API_KEY=." services/ai-gateway --glob '!node_modules/**'
```

Expected: tests/build PASS; secret scan returns no real value.

- [ ] **Step 7: Commit the gateway**

```bash
git add package.json package-lock.json services/ai-gateway
git commit -m "feat: add secure MiniMax AI gateway"
```

## Task 8: HarmonyOS AI Client and Seamless Fallback

**Files:**
- Create: `apps/harmony/entry/src/main/ets/core/network/AiGatewayClient.ets`
- Create: `apps/harmony/entry/src/main/ets/features/conversation/ConversationController.ets`
- Modify: `apps/harmony/entry/src/main/ets/features/conversation/ChatScreen.ets`
- Modify: `apps/harmony/entry/src/main/ets/features/diary/DiaryScreen.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/ConversationController.test.ets`

**Interfaces:**
- Consumes: Task 7 HTTP routes and local `FallbackGuide`.
- Produces: `open(draft)`, `respond(draft)`, `createDiary(draft)` with typed results; `ConversationController` owns AI/script source switching.

- [ ] **Step 1: Write failing controller tests**

Test AI success, offline-at-start, first-response timeout, rate limit, content block, empty text, interruption after partial output, and restored fallback step. Assert AI failure never removes user messages and never blocks local diary generation.

- [ ] **Step 2: Implement typed gateway calls**

Use only HTTPS outside local debug builds. Set connect/response timeouts, parse the stable error envelope, reject blank success payloads, and return typed failures rather than platform exceptions to the UI.

- [ ] **Step 3: Implement deterministic source switching**

`ConversationController` begins in `ai`, changes once to `script` for the current failed request, persists the fallback step, and does not replay already completed questions. Partial AI text may remain visible but must not be treated as a completed assistant turn unless the response completes.

- [ ] **Step 4: Connect chat and diary screens**

Display a short recoverable status when switching to script. Keep user text input enabled. Generate the local diary whenever AI diary generation fails.

- [ ] **Step 5: Run all client and gateway tests**

Expected: complete past-flow success with live fake AI and with forced timeout.

- [ ] **Step 6: Commit AI integration**

```bash
git add apps/harmony/entry/src/main/ets/core/network apps/harmony/entry/src/main/ets/features/conversation apps/harmony/entry/src/main/ets/features/diary apps/harmony/entry/src/ohosTest/ets/test/ConversationController.test.ets
git commit -m "feat(harmony): integrate AI gateway with fallback"
```

## Task 9: Native Speech, Haptics, Card Rendering, and System Share

**Files:**
- Modify: `apps/harmony/entry/src/main/module.json5`
- Create: `apps/harmony/entry/src/main/ets/core/system/SpeechInput.ets`
- Create: `apps/harmony/entry/src/main/ets/core/system/Haptics.ets`
- Create: `apps/harmony/entry/src/main/ets/core/system/CardRenderer.ets`
- Create: `apps/harmony/entry/src/main/ets/core/system/ShareService.ets`
- Create: `apps/harmony/entry/src/main/ets/features/share/CardScreen.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/SystemAdapters.test.ets`
- Test: `apps/harmony/entry/src/ohosTest/ets/test/CardRenderer.test.ets`

**Interfaces:**
- Produces: permission-aware Chinese speech input, selection haptic, `render(entry, template): Promise<PixelMap>`, `share(pixelMap): Promise<void>`.

- [ ] **Step 1: Write adapter and card-contract tests**

Port the card width, layout sections, text wrapping, template IDs, and failure isolation contracts from `apps/web/tests/cardRenderContract.test.ts`. Fake denied speech permission and failed sharing; assert text input and saved entries remain available.

- [ ] **Step 2: Declare minimum permissions and usage reasons**

Add only permissions proven necessary by the selected official APIs. Request microphone permission on voice-button activation, never at startup. Do not add contacts, location, device identifiers, or broad storage access.

- [ ] **Step 3: Implement speech and haptics behind interfaces**

Normalize recognized Chinese text into the active input without auto-sending it. Treat cancellation and denial as normal outcomes. Trigger the same selection/confirmation points as `apps/web/src/lib/haptics.ts`.

- [ ] **Step 4: Implement deterministic card rendering**

Match the Web card's 1080-pixel logical width, adaptive height, typography hierarchy, mood asset, diary wrapping, and both `planet-letter` and `orbit-theatre` templates. Render to an app-owned temporary image without mutating the original mood asset.

- [ ] **Step 5: Implement save and system share**

Preview first; share only on explicit tap. Clean app-owned temporary files after their lifecycle. A failed share returns to the preview with retry and never rolls back the diary.

- [ ] **Step 6: Run tests and mandatory real-device checks**

Verify microphone allow/deny, Chinese recognition, haptic timing, both card templates, image save, system share, cancellation, and app resume.

- [ ] **Step 7: Commit native capabilities**

```bash
git add apps/harmony/entry/src/main/module.json5 apps/harmony/entry/src/main/ets/core/system apps/harmony/entry/src/main/ets/features/share apps/harmony/entry/src/ohosTest/ets/test
git commit -m "feat(harmony): add native speech haptics and sharing"
```

## Task 10: Compliance, Release Checks, and Final Verification

**Files:**
- Create: `docs/compliance/data-flow.md`
- Create: `docs/compliance/permissions.md`
- Create: `docs/compliance/release-checklist.md`
- Modify: `apps/harmony/README.md`
- Modify: root `README.md`

**Interfaces:**
- Consumes: final permission manifest, network routes, SDK list, build/test commands.
- Produces: auditable release package instructions and reviewer test path.

- [ ] **Step 1: Document the exact data flow**

List mood, time mark, transcript, diary, audio stream, generated image, request ID, and operational logs. For each, record collection trigger, local/remote destination, retention, deletion, processor, and whether it leaves the device.

- [ ] **Step 2: Reconcile the permission matrix against the manifest**

For each declared permission, document feature, request moment, denial behavior, user-facing explanation, and official API. Fail the check if a manifest permission has no row or a row has no implemented feature.

- [ ] **Step 3: Write the release and review path**

Include: fresh install, privacy-policy entry, now note, past recall with AI, forced offline fallback, diary edit/save, timeline/detail, microphone denial, card generation/share, and local-data deletion. Explicitly disclose MiniMax as the AI processor and state that the product is a diary/recall tool rather than diagnosis or treatment.

- [ ] **Step 4: Run the complete verification matrix**

```bash
npm test
npm run build
npm -w services/ai-gateway test
npm -w services/ai-gateway run build
cd apps/harmony && ./hvigorw clean && ./hvigorw test && ./hvigorw assembleHap
```

Also run the emulator and real-device checklist from Tasks 6 and 9. Record command versions and outcomes in `apps/harmony/README.md`.

- [ ] **Step 5: Scan the release tree**

```bash
git status --short
rg -n "MINIMAX_API_KEY=.+|Authorization: Bearer .+" . --glob '!node_modules/**' --glob '!apps/web/dist/**'
find apps/harmony -type f \( -name '*.p12' -o -name '*.cer' -o -name '*.hap' -o -name 'local.properties' \) -print
```

Expected: no real secret, signing material, built HAP, or machine-local configuration is tracked.

- [ ] **Step 6: Produce the release candidate and stop at user-owned credentials**

Use DevEco Studio's standard signed-build flow only after the user supplies/authorizes the Huawei developer account, AppGallery Connect identity, signing material, privacy-policy URL, and MiniMax deployment secret. Do not invent or bypass these credentials.

- [ ] **Step 7: Commit release documentation**

```bash
git add README.md apps/harmony/README.md docs/compliance
git commit -m "docs: add HarmonyOS release and compliance guide"
```

## Final Done Checklist

- [ ] All ten tasks are committed independently and unrelated pre-existing changes remain intact.
- [ ] `apps/harmony` builds, tests, installs, and completes now/past flows offline.
- [ ] All five copied mood sheets hash-match the originals and all fifteen crops are correct.
- [ ] MiniMax live calls work only through the gateway; missing key and failures use scripts.
- [ ] Speech, haptics, card save, and system share pass on a real HarmonyOS device.
- [ ] Web-to-HarmonyOS visual comparisons are recorded for every screen.
- [ ] Compliance documents match the actual manifest, network behavior, and third-party services.
- [ ] No credentials, signing files, HAPs, logs containing user text, or machine-local SDK paths are committed.
