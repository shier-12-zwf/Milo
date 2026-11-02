# Tasks

## 1. Reference and acceptance

- [x] 1.1 Freeze current HarmonyOS source/build fingerprints and enumerate all required page/state cases; verify the ledger covers the 13 principal views and variants.
- [ ] 1.2 Capture current HarmonyOS reference screenshots using synthetic content and record device/data provenance; verify image hashes and flag any unavailable states.
- [x] 1.3 Independently review this plan and case coverage, address findings and pass strict OpenSpec validation.

## 2. Domain and durable journeys

- [x] 2.1 Expand moods, entries, transcripts, templates and draft state; verify schema-1 migration, schema-2 roundtrip and failure preservation tests.
- [x] 2.2 Implement pure recall transitions, concise offline guidance, literal diary generation and export rules; verify both journeys, context reset and credential-free export tests.

## 3. Native product and visual system

- [ ] 3.1 Reuse original mood sheets and dark theme; implement mood/descriptor rings with accessible selection; verify original asset hashes and reference-aligned home captures.
- [x] 3.2 Implement classify, now note, past time, chat and diary routes with draft restoration; verify complete now/past UI journeys, keyboard and restart behavior.
- [ ] 3.3 Implement timeline, detail, both card templates and native export/share; verify empty/populated/expanded/card screenshots, template persistence and actual export output.
- [ ] 3.4 Implement login/account/avatar/AI settings views and native secure storage/network/speech adapters; verify validation, consent binding, cancellation and honest offline/error behavior.
- [ ] 3.5 Configure the real iOS AGC provider and execute authorized account verification; keep this task blocked if platform configuration or owner-driven checks are unavailable.

## 4. Evidence and iteration

- [x] 4.1 Add isolated deterministic DEBUG fixtures and required-case screenshot capture; verify fixtures cannot reset production stores and captures use actual product views.
- [ ] 4.2 Add parity evidence validation and a paired-image report; demonstrate missing/stale/image-modified cases fail and complete reviewed evidence passes.
- [x] 4.3 Run native build, core tests and both user journeys; preserve current logs and screenshot provenance in a new Specdrive run.
- [ ] 4.4 Independently compare every required screenshot pair, record fidelity and concrete aesthetic improvements, repair findings and recapture affected cases; leave unmatched cases incomplete.
- [x] 4.5 Update the draft PR and user-facing acceptance report with actual coverage and outstanding device/service gaps; declare final product parity only when every required behavior and visual case passes.

## 5. Web reference and native polish (user-authorized 2026-09-29)

- [x] 5.1 Consolidate into the current project; verify and archive old evidence, remove obsolete sibling worktrees, preserve user edits.
- [ ] 5.2 Capture actual Web product pages and motion references; record supported/native-only state mapping.
- [x] 5.3 Independently review the updated scope and implementation plan. Evidence: `docs/visual-parity/web-native-plan-review.json` (round 2 approved; 53-state mapping and temporal criteria).
- [x] 5.4 Restore layered starfield and touch response; verify live and reduced-motion behavior without blocking controls.
- [x] 5.5 Refine iOS navigation/actions and repair template transition layout; verify real journeys, accessibility and both switch directions.
- [ ] 5.6 Capture all 53 native states independently and review actual paired images and motion evidence.
- [ ] 5.7 Run required current checks, update PR and merge the verified code milestone; report external release gaps separately.

## 6. Harmony-source functional completion (user-authorized 2026-09-30)

- [x] 6.1 Record source-based login/account/settings differences and independently review the functional plan.
- [x] 6.2 Integrate the supported iOS AGC adapter and validate the build/configuration boundary; keep actual remote account verification separately blocked when unavailable.
- [x] 6.3 Complete login/reset/logout behavior with failure preservation and account-model regression evidence.
- [x] 6.4 Connect AI defaults and settings saves to new and current journeys, preserve drafts, and reject stale requests; verify regressions.
- [x] 6.5 Exercise normal login/account/settings navigation, persistence and exit in the simulator; independently review current originals and update the PR with accurate external gaps.

## 7. Simulator stability and delivery (user-authorized continuation)

- [x] 7.1 Record the exact launch failure, revise the complete iteration plan and independently review it.
- [x] 7.2 Restore Xcode-supported simulator signing, include AppIcon and verify compiled identity, resources and normal installed launch.
- [x] 7.3 Exercise repeated cold launch/background restoration, native account/Keychain and both durable journal journeys on current binaries.
- [x] 7.4 Repair and re-run long-text, large-text, card controls and live/reduced-motion cases, retaining unsuccessful attempts.
- [x] 7.5 Independently inspect current originals and evidence, install the verified preview, update the existing PR and report remaining remote/device/visual gaps.

Current simulator stability evidence: `docs/operations/ios-stability-iteration-2026-09-30.md`, current 13-check run `.specdrive/stability-20260930`, and independent `ios-stability-final-review-2026-09-30.json`. Native captures 53/53 and interaction regressions are verified; full paired visual acceptance, actual remote accounts, physical devices and release remain incomplete. The archived failed attempts are retained.

Existing draft PR https://github.com/horton2048/milo/pull/1 updated with current simulator results and outstanding external acceptance. Final independent review is scoped PASS; no full-product archive or merge is claimed.
