# Design

## Context

See proposal.md. The current iOS pilot has one capture screen and a now-only schema. The authoritative HarmonyOS tree includes uncommitted account, AI, export and UI improvements absent from HEAD; old store screenshots predate these improvements. Local Xcode 26.6/iOS 26.5 is now installed. HarmonyOS builds with the installed DevEco toolchain; startup currently awaits the emulator license response.

## Goals / Non-Goals

**Goals:** Shared product semantics, original mood art, faithful dark spatial composition, durable full journeys and case-complete visual evidence. Preserve existing user changes and the pilot's immutable evidence.

**Non-Goals:** Paid enrollment, purchases, App Store publication, redesigning the HarmonyOS reference or claiming physical-device/remote-provider results without execution. These exclusions do not remove account/settings pages or permit fabricated product behavior.

## Decisions

1. Continue in the isolated iOS worktree. Freeze HarmonyOS source hashes from the main working tree and a new signed build; capture by operating the actual app. Never overwrite its data to fabricate empty states. Where necessary, add an isolated debug fixture only with explicit test storage separation.
2. Keep the existing Swift package and robust atomic repository, extend JournalEntry with labels, kind, timeMark, transcript, diary and stickerTemplate, and explicitly migrate schema 1 to 2 with preservation tests. Add pure draft, fallback, export and card-summary rules. Foundation core owns no UI or credentials.
3. Use one observable app coordinator, a small explicit page enum and feature views. Core ownership is separate from shared theme/assets and from features; the integration owner controls shared interfaces, Xcode configuration and tasks.
4. Match the actual deep-black/lavender brand and original five mood sheets. Implement planet cropping from the exact HarmonyOS mapping. Preserve ring selection and two-stage feeling/name flow. Improve restrained typography, consistent margins, readable contrast, safe areas, keyboard avoidance and minimum target sizes; do not replace the ring with a generic chip grid.
5. Put Keychain, native share/export/photo selection, speech and URLSession behind platform adapters. Maintain real account/provider error states. Remote AGC iOS needs a bundle-matching configuration and supported SDK; missing setup is a tracked blocker, while owner-local and deterministic DEBUG fixtures are explicitly separate.
6. Capture a manifest of named page/state cases with fixed synthetic data and dates. DEBUG case injection requires an isolated UUID store; rendering remains the production component. Freeze motion only for snapshot consistency. Pair original images in a browsable comparison report without repainting screenshots. Native system chrome is excluded from product-geometry judgments but never erased from originals.
7. Acceptance has two dimensions: real journeys and independent per-case visual inspection. The new parity validator requires every manifest case and its hashes/review; the old 2-image visual gate is not reused as full-product acceptance. Keep both small iPhone/default text and accessibility/keyboard stress checks.

## Risks / Trade-offs

- [Large difference from pilot] → replace its root composition with bounded feature modules, retain portable regression tests and immutable pilot evidence.
- [Current HarmonyOS not committed] → enumerate file hashes and build identity instead of claiming HEAD describes the reference.
- [AGC iOS credentials/configuration absent] → prepare the real adapter and report the external setup requirement; do not use fake production login.
- [Aesthetics are partly subjective] → explicit per-page rubric and side-by-side evidence; do not claim universal or pixel-byte perfection.
- [Private data in reference simulator] → use synthetic records and redact only in separate labelled presentation copies if necessary, preserving controlled originals locally; never publish keys or personal diary content.
- [Runtime/rasterization differences] → compare logical layout ratios and intended hierarchy, record permitted native deviations.

## Migration Plan

Read v1 records without modification; write the new complete schema atomically only after valid decode. Preserve previous bytes on failure. Keep signing and service secrets local. Final draft PR must state remaining external verification honestly, and the new change stays active until every required pair and behavior passes.

## Evidence-led visual repair phase (2026-09-26)

The first 53-state run produced 183 original screenshots; three independent reviews found concrete layout and coverage defects. `docs/visual-parity/visual-repair-plan.md` and its two-round review retain the old bounded run and define a separate repair phase under the same limits. UIKit-raster card previews eliminate unconstrained Canvas layout. A native bounded text editor preserves full Dynamic Type and draft behavior. DEBUG-only UUID-isolated public scroll/UITextView probes record actual geometry without driving the UI or changing text; capture uses real overlapping gestures and state assertions, including preserved confirmation modals. These diagnostics do not constitute paired visual approval or external account verification.

## 2026-09-29 user-authorized scope amendment

The current reference is the actual public Web experience at https://milo.huangtangai.top/app, per the user's explicit direction; do not launch HarmonyOS. Preserve the prior Harmony evidence as historical. Develop only in /Users/hut/Projects/milo. The current phase restores Web starfield/touch motion and page semantics while improving native iOS controls, retains all 53 native state checks, and records Web-absent native states separately without fabricating reference screenshots. See docs/visual-parity/web-native-plan-2026-09-29.md for the reviewed implementation and acceptance plan. This amendment supersedes the prior requirement to use a sibling worktree or to obtain new Harmony runtime captures for this phase; real account/device release claims remain separate.

## 2026-09-30 functional parity continuation

The user explicitly requests a new functional audit against the current HarmonyOS source, especially login, account and settings. Implement the bounded scope and scenarios in docs/operations/ios-functional-parity-plan-2026-09-30.md. Keep the Web visual reference and historical failures; do not launch Harmony or treat functional checks as full visual acceptance. All work stays in the current project. Production email authentication requires the actual supported iOS provider and bundle-specific configuration; distinguish implementation, injected tests and actual remote verification.

## Stability and installation repair

Use Xcode's normal simulator signing and generated simulated entitlement sections, with a project-local clean DerivedData directory. Never attach restricted iOS entitlements directly to the host ad-hoc signature. The installed bundle must match the verified source-bound build. Add a compiled opaque 1024 AppIcon and require actual normal home-screen launch, repeated cold launches and native Keychain round-trip. Follow the three-round plan in docs/operations/ios-stability-plan-2026-09-30.md; preserve older failed runs and user data. No runtime test may modify source, and a build success alone cannot approve delivery.
