# iOS input usability — partial, 2026-10-06

The ordinary demo now shows the Chinese Pinyin keyboard when the chat field is tapped. Native UI testing verifies a visible keyboard, entering new text while preserving the original fixture, and sending the combined text. **Speech remains unavailable; no Chinese transcription or sustained recording has passed.**

## Observed causes and changes

- Simulator hardware keyboard connection initially suppressed the screen keyboard. Disabling it restored input before tests. After XCTest, ordinary input again showed only its accessory toolbar. A nondestructive simulator reboot preserved records; explicit Simulator I/O > Keyboard > Toggle Software Keyboard restored the ordinary keyboard. Final state keeps hardware connection enabled and software keyboard explicitly shown. Chinese Pinyin selected; tapping Done and then the ordinary chat input again showed the Chinese keyboard automatically.
- Native recognition repeatedly reports `kLSRErrorDomain` 300 (failed to initialize recognizer), with `localspeechrecognition` failing to open its Chinese model `mini.json`. It previously appeared as “没有听清”; the backend now distinguishes recognition service failure from silence and logs only error domain/code.
- Three bounded attempts: stop forcing local recognition on Simulator; prepare Chinese assets through public DictationTranscriber/AssetInventory APIs; disable the writable public local-support flag on Simulator as a network-routing attempt. All three strict recording checks failed. The inventory reported `installed`, but subsequent real recognition still failed to open the model; that report is **not** proof of usable assets or transcription. SpeechTranscriber reported unavailable.
- Physical-device local recognition preference retained. No model files fabricated, transcript injected, new speech provider added, production app uninstalled, or simulator erased.

## Verification and preservation

Device: iPhone 17e, iOS 26.5, UDID `EAE7BE56-823B-4B27-93CE-2883A202DC1D`. Final current-source signed build and preserving install passed. Native tests: 19 account tests + 12 speech state/callback tests + 1 explicitly labelled public asset diagnostic. The diagnostic is not a speech behavior pass. Keyboard test passed; strict actual recording failed before reaching its five-second requirement. Real transcription was not observed.

Evidence lives locally under `.artifacts/ios/input-usability-20261006/`: original keyboard/voice screenshots and AX attachments, speech system logs, source/build/test receipt index, baseline file hashes, final ordinary Chinese-keyboard screenshot and normal-demo receipt. Ordinary final launch PID was 10782 with no UI-test arguments or production test text. Existing production `account.json`, `journal.json`, and `draft.json` were preserved across all covering installs; temporary UI writes use UUID fixtures. Test runner removed after checks.

Previous callback/fallback scope and exhausted runner are retained. Initial new run `.specdrive/input-usability-20261006` had an invalid OpenSpec command with two change names, but independently ran the native checks and recorded the first real speech failure. Corrected state `.specdrive/input-usability-20261006-corrected` deducts the initial attempt and frozen 76943ms: two attempts/check and 2323057ms remain, keeping the aggregate budget at three attempts and 2400000ms. Both corrected attempts are consumed; no reset to gain more retries. Current gate passes six checks and fails strict voice. The change remains active and task 4/5 remains incomplete.

The independent review receipt is `docs/operations/ios-input-final-review-2026-10-06.json`. No connected iPhone was available. Next acceptance requires a working real Apple recognition environment and actual Chinese audio-to-text evidence, followed by denial, restart, stop, and background regressions. Physical-device availability alone cannot be assumed to prove success.

Apple's documented error mapping: https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error
