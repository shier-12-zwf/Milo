## Why

Two simulator crash reports on October 4 and 5 terminate at Swift executor checks in the speech authorization closure. The user needs speech input to fail safely and keep their writing, rather than terminating the app.

## What Changes

- Correct isolation for authorization, recognition and audio callbacks under Swift 6.
- Cancel pending permission requests logically, ignore stale callbacks, and release recording on interruption/background/navigation.
- Add background-callback regression tests and real simulator speech-entry tests, including denied permissions and repeated use.

## Capabilities

### New Capabilities

- `ios-speech-stability`: safe optional speech input, permission/cancellation lifecycle and keyboard fallback.

### Modified Capabilities

None. Existing parity work remains active and untouched.

## Impact

SpeechInputModel, its native adapter, ChatView lifecycle, native tests and scoped verification configuration. No new remote service, no account migration or production data reset. Simulator tests do not certify real-device transcription quality.
