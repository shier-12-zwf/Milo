# Design

## Context

See proposal.md. Existing web now-note behavior allows blank notes, trims input, and stores `kind=now`, `diaryEnabled=false`. Seven primary mood IDs and valences are shared semantics. The Mac currently has Swift 6.3.3 Command Line Tools but no discoverable Xcode; simulator validation is a tracked prerequisite, not an implicit pass.

## Goals / Non-Goals

Goals: a small native SwiftUI vertical slice and executable evidence for the upgraded framework. Deployment target iOS 17 to use modern observation and navigation without adding dependencies. Portable logic supports macOS 14 for local testing.

Non-goals: complete platform parity in this milestone, cloud sync, account gate, external AI, publishing, and changes to existing clients.

## Decisions

1. `apps/ios/MiloCore` is a local Swift package with Foundation models, a versioned JSON repository and Swift Testing tests. SwiftUI app depends on it. This lets available Swift test real persistence before Xcode is ready. SwiftData was considered; a small atomic JSON store makes the first milestone's durability, corruption and failure behavior explicit and testable without Apple UI frameworks.
2. The repository is single-owner on the main actor in the app. Atomic writes persist `{schemaVersion:1,entries:[...]}`. Every save reads/validates current data, upserts by ID, writes atomically, and only then updates UI state. A read failure prevents overwrite. Test injection supplies read/write failures without permissions hacks. No cross-process concurrent writers are supported in this milestone; tests use isolated directories.
3. `JournalEntry` stores a stable UUID string, epoch-millisecond creation time, a primary `Mood`, trimmed note, now-kind and diary-disabled constants. Unknown/invalid schema, duplicate IDs in loaded data, nonfinite/out-of-range timestamps and invalid moods must report errors. Existing foreign-client data import is out of scope.
4. SwiftUI uses a small view model with injected repository, no network SDK and no credentials. Navigation separates capture, history and detail; draft resets only after successful save. Read errors are presented with retry, preserving both file and draft. Purple cosmic accents reference MILO; native typography, controls and accessibility IDs make automated testing reliable.
5. Use a checked-in Xcode project generated from a small declarative project definition if tooling is available; one integrator owns project metadata. iOS build/UI commands select a discovered installed iPhone simulator (or an explicit destination override), avoid signing, and emit `.xcresult` evidence. UI tests use a dedicated sandbox path and reset only the test fixture at test setup; relaunch never resets data.
6. Specdrive remains a thin OpenSpec orchestrator. Its small runner owns check state and evidence, not requirement scaffolding or model scheduling. Config lists exact argv/cwd/inputs, timeouts, dependencies and attempt limits. Required platform checks are never downgraded to optional to make the gate green. Scope/spec and independent review are retained alongside evidence.

## Risks / Trade-offs

- Missing Xcode or simulator → complete portable core tests, leave iOS gate blocked, resume after environment setup.
- Concurrent edits in the existing working tree → new iOS paths only, no root build scripts or existing client files modified.
- Same-model review can miss issues → independent context plus behavioral tests and recorded runtime evidence.
- JSON is appropriate for the small milestone but scales poorly to large histories → keep storage behind a protocol, add migration in a later change if needed.
- Visual quality cannot be proved by unit tests → actual simulator captures and review remain a separate required check.

## Migration Plan

Additive first installation only. iOS data stays in the app's Application Support directory. Rollback removes the new client from the repository without altering other clients. No automatic migration or deletion of personal data.

## Verification environment finding

The installed Command Line Tools compiler does not ship the Swift Testing module. Pin official swift-testing 6.2.4 as a test-only package dependency (and retain Package.resolved) so portable tests can execute; the app/core runtime remains Foundation-only. Actual iOS checks can also execute on a GitHub macOS runner when local Xcode is unavailable. Remote simulator evidence must identify its source commit and environment and is separate from a locally blocked run.
