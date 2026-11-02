# iOS input usability

## Why
Speech crash mitigation only proved safe failure. The ordinary simulator immediately fails speech because local Chinese recognition assets are absent. Hardware keyboard connection suppressed the screen keyboard.

## What Changes
- Use the system's supported speech routing on Simulator instead of forcing unavailable on-device recognition; retain on-device preference on physical devices.
- Distinguish recognition service failures from silence with safe diagnostics.
- Require actual visible keyboard and sustained recording in new native acceptance evidence, with real transcription recorded separately.

## Capabilities
### New Capabilities
- `ios-input-usability`: real keyboard and speech entry acceptance.

## Impact
iOS speech backend, scoped XCTest tests, simulator keyboard preference. No change to stored user records, Harmony, gateway or external provider.
