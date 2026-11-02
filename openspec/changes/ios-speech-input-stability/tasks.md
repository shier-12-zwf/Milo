## 1. Callback isolation and recording lifecycle

- [x] 1.1 Implement native callback bridges and verify permission, recognition and audio handlers can run on background queues with native unit tests.
- [x] 1.2 Implement cancellable start, generation checks and idempotent owned-resource cleanup; verify pending cancellation, duplicate starts, stale events, setup failure and partial transcript retention in native unit tests.
- [x] 1.3 Stop on interruption, audio route loss, media reset and background/navigation; verify lifecycle tests and document actual simulator limitations in the incident report.

## 2. Product entry and installed verification

- [x] 2.1 Expose stable voice/error identifiers and cancellable pending state; verify real simulator granted/denied speech entry, editable prior text, repeated use and background return through XCUI tests.
- [x] 2.2 Build normally signed package, install preserving user data, and pass native speech/unit and launch regression checks with source/build/loaded-test provenance.
- [x] 2.3 Independently review implementation and original evidence; deliver a saved incident report with crash cause, executed counts, exclusions and runner state; launch the fixed ordinary demo visibly.
