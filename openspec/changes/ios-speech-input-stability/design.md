## Context

Crash logs Milo-2026-10-04-220853.ips and Milo-2026-10-05-120340.ips share EXC_BREAKPOINT at _dispatch_assert_queue_fail, _swift_task_checkIsolatedSwift and the authorization callback inside SpeechInputModel.start. All three legacy callbacks are created in a MainActor context. Apple explicitly does not guarantee the authorization handler's main queue. Swift 6 dynamically checks inherited actor isolation.

## Goals / Non-Goals

Fix callback isolation and cancellation, verify real speech controls and controlled edge cases. Real microphone transcription quality on physical iPhone and full visual parity remain outside this focused milestone. No remote account or diary schema changes.

## Decisions

Keep the observable model MainActor; extract a small injectable native speech backend. Use explicitly Sendable, nonisolated callback factories for permission, recognition and tap handlers. Send only value-type recognition events to MainActor. Do not disable Swift isolation checking or assume the main queue. Audio buffers stay in the synchronous native tap; recognition request has one producer, teardown removes the tap before ending the request.

Use a UUID generation for pending starts and callbacks, track starting as user-visible cancellable state, and stop owned audio resources idempotently. Observe real audio interruption/route loss/media reset and stop for background, but do not cancel just because the first permission dialog makes the scene inactive. Cancel pending authorization on navigation/background. Preserve draft prefix and accepted transcript. Unit tests inject permission suspension and background callbacks into the production bridge; native UI tests use the real backend.

## Verification

Create a new scoped runner state speech-20261005 (the previous stability run is retained, not reset). Limit to 3 executions per check, 2 identical no-progress failures and 40 minutes of active commands. Checks: strict spec validation, native preflight, signed build, data-preserving install, native unit suite including new speech tests, real speech UI suite, existing launch suite. Isolated UUID stores for test hosts; ordinary app final launch. Independent plan and final evidence review; preserve original source baseline, logs, result bundles and test provenance.

## Risks / Trade-offs

Simulator recognition assets/audio vary: assert recording OR visible fallback rather than fabricate transcription, and report this limit. Native callbacks from legacy Objective-C need a narrow Sendable bridge; verify on a background queue. No reinstall-by-uninstall or production journal reset. Protect existing dirty files and only apply a small ChatView lifecycle/control diff.

## Migration Plan

Normal Xcode simulator signing and covered install preserving stored data; source repair alone does not fix the installed package. Retain old logs, evidence and local backups. Leave ongoing parity changes active.

## Actual native-audio finding during verification

First real microphone-refusal test passed, but real granted entry exposed a distinct SIGABRT: _ReportRPCTimeout → AURemoteIO.Initialize → AVAudioEngine.inputNode. Simulator log says Initialize RPC timeout / deadlocked. Preserve failed attempt and original crash in `.artifacts/ios/speech-20261005/first-ui` and `audio-start-crash.ips`. Use playAndRecord/measurement/defaultToSpeaker, validate activated session input availability/sample rate/channel count before node access, and cache the input node for tap teardown. Simulator-specific audio routes are set explicitly to builtin Mac microphone/speaker and the same device rebooted without erase. This is environmental repair plus setup/lifecycle hardening; valid properties cannot make a fatal underlying AudioUnit timeout catchable. No platform-wide speech disabling or fake transcription, no claims about untested Bluetooth/physical devices. Pending authorization locks only the editor and retains a cancel control to preserve the snapshotted text prefix.
