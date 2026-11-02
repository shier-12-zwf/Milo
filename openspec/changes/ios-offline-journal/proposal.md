# Proposal

## Why

MILO has working web and HarmonyOS clients but no native iOS client. Ship a small, offline-first iPhone journal that also provides a real forward test of the upgraded Specdrive workflow: requirements, independent review, executable checks, honest blocked states, and resumable evidence.

## What Changes

- Add a SwiftUI iOS app under `apps/ios`, sharing product behavior rather than TypeScript source.
- Support the seven primary moods, an optional present-moment note, a saved-record timeline and detail view, and durable local persistence.
- Add a portable Swift core with behavioral tests, an Xcode project, iOS UI tests, and reproducible verification commands.
- Integrate a project-local copy of Specdrive, pinned OpenSpec tooling, and a machine-readable verification manifest.
- Keep this milestone narrow: no account gate, cloud sync, external AI requests, past-memory conversation, export, deletion or App Store release yet. These are future changes, not silently omitted completed features.

## Capabilities

### New Capabilities

- `ios-offline-journal`: Record the current mood with an optional note, persist it, and reopen it without network access.
- `ios-evidence-gates`: Require current executable evidence for core behavior and actual iOS build/UI checks before milestone completion.

### Modified Capabilities

None. Existing web, gateway, and HarmonyOS behavior is unchanged.

## Impact

New `apps/ios`, `openspec`, project-local `.agents/skills`, and scoped operations documentation. The existing dirty working tree must be preserved. Full Xcode and an installed iPhone simulator are needed to verify iOS; macOS Swift tests alone do not prove that the iPhone app compiles or runs.
