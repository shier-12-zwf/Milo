# Native iOS verification profile

Use this profile for an iOS application, including one whose shared logic also runs
as a Swift package on macOS. Keep the repository's chosen architecture and deployment
target. SwiftUI is a reasonable default for a new native app, not a migration mandate.

## Required environment evidence

Before claiming simulator delivery, inspect and record:

```sh
swift --version
xcode-select -p
xcodebuild -version
xcrun simctl list devices available --json
xcrun simctl list runtimes --json
```

Check that a usable **iOS** runtime and destination exist; successful listing alone is
not sufficient. Prefer a task-local `DEVELOPER_DIR` if Xcode is installed but the global
selection points at Command Line Tools. Avoid changing global tool selection without
need. Record the Xcode version, SDK, simulator device ID, and OS version used.

Missing full Xcode, an unaccepted license, unavailable iOS runtime, or unavailable
simulator must leave the corresponding required check **blocked**. A macOS `swift test`
pass is useful core-logic evidence, not an iOS build, UI test, or simulator pass. Do not
remove the iOS gate to make the overall run green. Independent core work can continue
while the native validation remains blocked.

Use existing authorized accounts and installations. Do not invent signing identities,
embed credentials, or silently enroll in paid services. State the exact installation or
account action needed when it cannot be completed in the authorized environment.

## Scenario-to-check mapping

| Concern | Evidence |
| --- | --- |
| Domain behavior | Swift Testing or the project's existing unit tests, asserting edge cases |
| Persistence | Temporary-store tests for save/reload, ordering, failures, and migration when applicable |
| Native compilation | `xcodebuild` for the actual project/workspace, scheme, and iOS Simulator destination |
| User journey | XCTest/XCUIAutomation executing real controls with asserted visible outcomes |
| Restart durability | Save through the UI, terminate the app, launch again, and assert the saved record remains |
| Offline support | Exercise the application's no-network/no-AI behavior, not just a network status flag |
| Presentation | Simulator screenshots and interaction evidence for keyboard, long content, Dynamic Type, and supported appearance modes |

Read project schemes and available destinations before constructing `xcodebuild`
commands. Use argument arrays in the runner. Include the app sources, test sources,
project settings, dependency manifests, assets, and validation scripts in check inputs.
Capture `.xcresult` bundles outside source directories; retain paths in the acceptance
report. Tests must assert meaningful outcomes instead of merely launching successfully.

Make UI tests deterministic with fixture stores and stable accessibility identifiers.
A reset launch argument may clear fixtures at the beginning of a test, but must be
removed before the relaunch assertion. Otherwise a restart-persistence test can falsely
exercise a fresh seeded state. Keep test-only controls out of the ordinary product flow.

## Cloud simulator and independent visual-review handoff

When local Xcode is unavailable, an authorized cloud macOS runner can perform a
separate native verification run. Preserve its environment and provenance. Do not move
its runner state into the local run or rewrite a local blocked check as passed; report
cloud results as cloud evidence for the exact revision tested.

Use two stages: first build and run native scenarios, retaining `.xcresult` and actual
simulator screenshots; then give those images and the acceptance scenarios to an
independent reviewer. The reviewer must inspect the images themselves, including large
text, keyboard obstruction, and appearance modes, rather than approve an implementation
summary or the existence of screenshot files.

Bind the review receipt to the cloud job/run ID, exact commit, relevant source/input
hashes, and each reviewed screenshot's content hash. Preserve its original Specdrive run. Record the
reviewer, verdict, findings, and limitations. A project-specific verification command
must reject missing, mismatched, or stale receipts; Specdrive does not authenticate a
reviewer merely because a receipt file exists. Include that receipt and its verification
command in the declared check inputs.

Keep the same cloud runner environment alive for a bounded handoff window, for example
10 minutes within the configured timeout and run budget. Read-only CI may consume and
verify an independently supplied receipt; it must not manufacture its own approval.
After receipt validation, resume with `run` and then `gate` against the **original state
directory**, retaining prior attempts, failures, and logs. Do not reset state or start
fresh just to bypass a failure limit. If the receipt does not arrive in time, retain
the blocked outcome and evidence for an explicit later continuation.

Independent agent review checks the stated engineering and presentation requirements.
It does not replace design confirmation the user has reserved, or authorize product
scope changes, distribution, or release.

## Final native gate

Each required native scenario needs current automated results or specifically identified
external observation, including device/runtime and the source revision inspected. An
independent reviewer assesses this evidence and the implementation. A screenshot alone
does not prove persistence; static source inspection does not prove working interaction.

Simulator delivery, signed device testing, TestFlight distribution, and App Store release
are distinct milestones. Do not label simulator completion as real-device or distribution
readiness. Retain blocked tasks and active OpenSpec changes until the agreed milestone's
evidence is complete.
