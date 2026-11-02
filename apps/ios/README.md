# MILO for iPhone

Native SwiftUI implementation of MILO, with current visual and motion comparison against the actual Web product: mood and descriptor rings, present/past memory journeys, offline guidance, diary editing, collection/detail, two card templates, local account entry and AI settings.

**AI temporarily withdrawn (2026-10-10):** `AIFeaturePolicy.isAvailable` in `App/Account/AIConnection.swift` is `false`. The AI/ membership settings and chat AI controls are hidden. A restored AI-settings page shows a local-recording notice instead; stored credentials, preferences and diary/draft data are retained. Both hosted and personal-provider completions (including connection tests) are blocked before network/credential access. Local recording, original-words diary formatting, editing, saving and export remain available. Restore the single gate only after the provider and product release are verified. The standalone coordinator test has an explicit test-only compilation flag for controlled fake responses; a second production-mode suite verifies that even injected completions cannot bypass the pause.

**Full cross-platform acceptance is still in progress.** Current scope, actual results and external blockers are in [PARITY-STATUS.md](PARITY-STATUS.md). The source-bound 53-case screenshot ledger and comparison contract are in [the visual parity documentation](../../docs/visual-parity/README.md).

Open `Milo.xcodeproj` with Xcode and an iPhone simulator. Minimum deployment is iOS 17; Swift 6.1+ is required by the portable test package. Use the **Milo** scheme. The local owner entry is `milo`. The supported AGConnect iOS provider is integrated; remote login still requires the bundle-matching service configuration and actual service verification. Synthetic screenshot identities never count as remote authentication.

```sh
# Run from repository root
npm ci --prefix apps/ios --ignore-scripts
xcodegen generate --spec apps/ios/project.yml
swift test --package-path apps/ios/MiloCore
apps/ios/scripts/test-journal-ai.sh
bash apps/ios/scripts/test-journal-compatibility.sh
node --test apps/ios/tests/parity-evidence.test.mjs
node --test apps/ios/tests/web-parity-gate.test.mjs
# Existing local iteration: resume its saved state; do not initialize again.
node .agents/skills/specdrive/scripts/specdrive.mjs status .specdrive/web-native-20260929
# User-authorized stability continuation; preserve its saved attempts.
node .agents/skills/specdrive/scripts/specdrive.mjs status .specdrive/stability-20260930
# For a genuinely new authorized phase, initialize specdrive.web-native.json once.
# Keep its returned state directory for every repair resume.
```

The app keeps device-local records and atomic JSON drafts in Application Support. Schema 1 remains readable and migrates on successful writes; unknown future or corrupted data blocks rewriting. Personal API keys are bound to account/provider/HTTPS destination in Keychain and excluded from exports. AI failures preserve expression through explicit local recording, without pretending to understand user content.

`specdrive.stability.json` verifies Xcode simulator signing, the compiled AppIcon, data-preserving installation, native Keychain, repeated launches, account journeys, journal journeys, motion and all 53 native capture cases. The [stability plan](../../docs/operations/ios-stability-plan-2026-09-30.md) defines the repair and review bounds. Simulator builds use Xcode's normal signing; do not manually attach device-only entitlements to a host ad-hoc signature. The installer backs up and compares existing persisted files before replacing the app without uninstalling it.

`specdrive.web-native.json` preserves the Web-reference phase; `specdrive.parity.json` preserves the historical Harmony-reference phase. Missing screenshot pairs or actual remote account verification blocks final acceptance. The previous `specdrive.config.json`, `verify.mjs` and pilot reports document the earlier offline slice; their six screenshots cannot approve the expanded product.

The portable package pins Apple's Swift Testing only for tests; its production domain model has no third-party runtime dependency. The iOS account adapter links the pinned AGConnect SDK. Original HarmonyOS mood artwork is reused byte-for-byte. Source assets, implementation, project configuration, tests and verification scripts are fingerprinted alongside actual builds; never copy a passing receipt onto changed code.

Raw `.xcresult` bundles, simulator stores and signing/service credentials stay local or in controlled CI artifacts. Do not publish personal diary data.


## iOS conversation behavior (2026-10-03)

Classification offers “说说此刻”, “自己写下来”, and the existing past-memory path. Present conversation does not ask for a past time. Replies prioritize concrete expression, may ask no question, and are displayed in full. “先聊到这里” only retains a local draft; the home resume action restores it. “收藏原话” saves without a diary request; “整理成日记” explicitly requests an editable diary for present or past conversation.

Before the temporary withdrawal above, the default MILO hosted source was **not connected in this build**. Personal HTTPS/OpenAI-compatible requests required consent and account-bound Keychain credentials. Those model requests are now also paused; the chat remains a local recording surface. No new service, credentials or real model evaluation was introduced. Previous screenshot/parity receipts do not validate the changed conversation layout or semantic model behavior.

Present conversations keep the existing `now` kind and schema-2 record envelope. Present diaries encode the legacy `diaryEnabled` as false plus an additive optional `presentDiaryEnabled: true`, while retaining diary and transcript content, so the previous iOS decoder can still read the whole file. Current iOS restores the enabled state from the extension. Existing notes and drafts remain readable. There is no file-import UI in these clients; compatibility checks exercise their storage decoders. Older apps cannot offer the new present-chat workflow and may drop the new mode flag if they rewrite a record, though its diary text remains readable. No other client was modified.
