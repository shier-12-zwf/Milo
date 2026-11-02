# Codex / MILO pilot validation — 2026-09-25

This upgrade was applied to a real new SwiftUI client in `horton2048/milo`, not just evaluated by reading the skill text. Scope: seven moods, optional present-moment note, local history/detail and restart durability. Native iOS verification remains distinct from portable Swift tests.

## Framework evidence

- OpenSpec CLI 1.13.2 was installed in an isolated tools directory; actual `init`, `status`, `instructions`, and strict validation were used to produce the MILO change.
- The runner has 19 passing behavioral tests, including child processes, stale source/command/log evidence, caps, timeout, interruption, lock recovery and prerequisite dependencies.
- An independent agent created temporary projects and ran success → resume → source change → failure → repair → stale-review rejection → refreshed-review success. Missing environment correctly blocked dependent checks without consuming their attempts; restoring it allowed continuation.
- Independent forward testing found two P2 issues: ancestor symlinks bypassed lexical path checks, and macOS `/tmp` aliases caused an in-project evidence directory to hash its own changing state. Both were fixed and the original reproductions rerun independently. Symlink inputs/cwd now reject at initialization; the custom evidence directory now passes and resumes without executing unchanged checks again.

These checks use local test fixtures. Fixture reviewer receipts test the contract; they are not product approval or identity attestation.

## Real application evidence

MILO's new Foundation core compiled and ran **17 Swift Testing tests** on the pilot Mac. They cover real-file persistence across new repository instances, blank/trimmed/long Unicode notes, identity upsert and ordering, read/write error preservation/retry, malformed JSON, unsupported schema, invalid record fields, and duplicate UUIDs.

The pilot Mac has Command Line Tools rather than full Xcode, and its compiler did not ship the Testing runtime module. Pinning official swift-testing 6.2.4 as a test-only dependency made actual portable tests possible. The iPhone app runtime remains Foundation/SwiftUI only.

The local native environment check correctly reports **blocked**. It must not be converted into a pass based on the Swift tests or source typecheck. A separate GitHub macOS workflow is used to obtain native build/UI evidence; consult the MILO pilot report and workflow for its current result.

Three native pilot runs exposed distinct failures. First, the app compiled and four UI journeys passed, but the largest accessibility text size caused an editor tap to hit Save; the layout and the interaction assertion were corrected. Second, XCTest itself failed to initialize and ran zero tests; this was retained as an environment failure. After explicit simulator startup preparation, the third run executed all six UI tests successfully. Independent inspection of its six screenshots still rejected completion: images labelled Dark were actually light, and two Light/Dark pairs were byte-identical. No pass receipt was supplied. This is direct evidence that source-bound screenshots and independent inspection add coverage beyond green UI assertions. Current completion status is recorded in [MILO's pilot report](https://github.com/horton2048/milo/pull/1).

## What this establishes

The revised skill can drive a real OpenSpec change across Codex agents, capture behavior checks, find and repair framework defects, and preserve honest platform gaps. It is useful as a lightweight orchestration/evidence layer. It is not proof of fully autonomous iOS release readiness, a scheduler, a sandbox, a model-cost limiter, or protection against deliberate evidence tampering.

The benefit demonstrated is traceability and more credible acceptance. Maintaining specifications, check inputs, platform scripts, dependencies, review receipts, and a working CI environment has a real cost. This pilot did not compare development time or model spending against another workflow, so it does not establish a speed or cost advantage.

The pilot also led to concrete project-check improvements: software-keyboard presence is asserted, simulator runtimes must meet the app deployment target, the pinned test framework's compiler requirement is checked, and reviewed image/result-bundle files must live in the fingerprinted evidence directory.

## Reproduce the framework checks

```sh
npm test
node scripts/specdrive.mjs --help
```

The portable runner requires Node 20.19+ and no npm runtime dependencies. OpenSpec remains a separate dependency. Read `references/runtime.md` before preparing a manifest; declare all transitive inputs relevant to each check.
