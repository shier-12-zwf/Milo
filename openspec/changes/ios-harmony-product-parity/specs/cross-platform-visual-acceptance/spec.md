# Spec Delta

## Purpose

Make cross-platform product acceptance depend on actual, traceable HarmonyOS/iOS page-and-state screenshots, complete behavior coverage and explicit visual review instead of a successful build or a few representative images.

## ADDED Requirements

### Requirement: Frozen current reference
Every baseline SHALL identify the current HarmonyOS source-file hashes including relevant uncommitted files, build hash, simulator/device version, viewport, locale, data and capture state. Historical screenshots MUST remain labelled historical and SHALL NOT satisfy current coverage.

#### Scenario: Reference changes
- **WHEN** a relevant HarmonyOS source or asset changes after capture
- **THEN** affected screenshot comparisons become stale until recaptured and reviewed.

### Requirement: Complete paired coverage
The acceptance ledger SHALL enumerate every principal page plus required empty/populated, selected, keyboard, expanded, loading/error and long-content variants before final review. Each required case MUST contain real reference and iOS screenshots, image hashes, matching test data and a case-specific verdict. Missing pairs or unresolved differences SHALL block final completion.

#### Scenario: Incomplete or stale evidence
- **WHEN** one required case lacks a screenshot, has modified bytes, uses unrelated fixture data or has an unresolved finding
- **THEN** the final parity gate fails even when all build and unit checks pass.

### Requirement: Faithful product with justified aesthetic improvement
The iOS page SHALL preserve the reference's branding, information hierarchy, core composition, labels and interaction meaning. Native safe areas, controls and font rasterization are permitted differences and MUST be documented. Aesthetic improvement SHALL be assessed per page for spacing consistency, readable hierarchy, contrast, alignment, touch targets and removal of clipping/overlap, with concrete evidence rather than an author's assertion. Essential content MUST remain usable with keyboard and large accessibility text.

#### Scenario: Independent side-by-side review
- **WHEN** an independent reviewer inspects each paired page and key state
- **THEN** the review records fidelity, readable content, actionable controls and specific polish changes; a redesigned or omitted product element cannot pass merely because it looks attractive.

### Requirement: Behavior and platform claims stay separate
Screenshots SHALL supplement actual end-to-end behavior tests for both memory journeys, persistence, failure fallback and exports. Simulator evidence MUST NOT be called physical-device evidence. Fixture-only account or network states MUST NOT be called actual external-service success.

#### Scenario: Final acceptance report
- **WHEN** the release candidate is assessed
- **THEN** the report lists complete case coverage, actual interaction outcomes, current source-bound review and any external-service/device gaps, keeping the change incomplete while required product behavior remains unverified.

### Requirement: Long pages and large text are completely inspected
The paired capture manifest SHALL record actual system text size and every required scroll checkpoint. Long pages SHALL include overlapping viewport captures through the final content/action without omitted middle sections. Representative home, editor, chat, diary, collection, detail, account and settings cases SHALL use the largest supported accessibility text size. Platform-specific safety improvements SHALL be explicitly reviewed as deviations against the source action.

#### Scenario: A long page only has a first-screen image
- **WHEN** any required overflow checkpoint or declared large-text capture is absent
- **THEN** the parity gate fails even when the page's initial image is approved

#### Scenario: System text sizes differ across platforms
- **WHEN** iOS accessibility5 and Harmony's largest supported setting have different pixel sizes
- **THEN** the reviewer records both actual settings and checks equivalent content, readable wrapping and reachable actions rather than claiming pixel identity

## 2026-09-29 user-authorized scope amendment

The current reference is the actual public Web experience at https://milo.huangtangai.top/app, per the user's explicit direction; do not launch HarmonyOS. Preserve the prior Harmony evidence as historical. Develop only in /Users/hut/Projects/milo. The current phase restores Web starfield/touch motion and page semantics while improving native iOS controls, retains all 53 native state checks, and records Web-absent native states separately without fabricating reference screenshots. See docs/visual-parity/web-native-plan-2026-09-29.md for the reviewed implementation and acceptance plan. This amendment supersedes the prior requirement to use a sibling worktree or to obtain new Harmony runtime captures for this phase; real account/device release claims remain separate.
