# Spec Delta

## Purpose

Provide an iPhone MILO experience that preserves the current HarmonyOS product's complete navigation, emotional expression, durable memories and account/settings behavior while respecting native iOS controls.

## ADDED Requirements

### Requirement: Complete navigation and mood expression
The iOS product SHALL expose the same 12 page families and 13 principal views as the frozen HarmonyOS reference: login, mood orbit, descriptor orbit, classify, now note, past time, chat, diary, timeline, detail, cards, account and AI settings. The seven primary mood positions, original planet assets, twelve descriptors and maximum three selections MUST retain their meaning and order. The default brand appearance SHALL be the reference's dark starfield.

#### Scenario: Choose and revise a feeling
- **WHEN** a user selects a mood, enters the descriptor ring, selects up to three words, returns to mood selection and enters again
- **THEN** prior descriptors are cleared, the focused and selected words remain legible, and continuing leads to the present/past choice.

### Requirement: Present and past journeys complete offline
The app SHALL allow an empty or written present note to save and open its card. Past memories SHALL choose a preset or custom time, converse, optionally form and edit a diary, and save to a card. AI failures MUST preserve user input and explicitly switch to local recording without fabricated understanding; a local diary MUST only use user-provided facts. Back navigation and unfinished input SHALL remain recoverable.

#### Scenario: Present memory and restart
- **WHEN** a user saves a present note and restarts the app
- **THEN** the memory appears in the timeline and detail with the same mood, words and content.

#### Scenario: Past memory without network
- **WHEN** a user chooses a time, responds to local guidance, edits a diary and saves offline
- **THEN** the conversation and selected diary content persist, the card opens, and the memory remains readable after restart.

#### Scenario: Interrupted expression
- **WHEN** the app terminates with unsent conversation text or an unfinished diary
- **THEN** the isolated user's draft restores; changing the past-time context resets only context-dependent content.

### Requirement: Collection and card behavior
The app SHALL provide empty/populated timeline, full detail, transcript expansion, deletion with safe recovery/confirmation, both planet-letter and orbit-theatre card templates, persistent template selection and working native image/share export. Markdown/JSON export SHALL include memories and exclude credentials.

#### Scenario: Inspect and export a memory
- **WHEN** a user opens a past memory, expands its transcript, switches card templates and exports
- **THEN** the saved template is retained, the native export contains the selected memory, and no API key or account credential is included.

### Requirement: Account and AI settings are honest and functional
The app SHALL reproduce login forms, owner-local entry, account/avatar controls and AI settings. Production remote authentication MUST use an actual supported provider configured for the iOS bundle, never a simulated success. HTTPS personal-provider settings SHALL bind consent and Keychain credentials to account and destination, reset consent on destination changes, and preserve offline functionality. Hosted membership preview SHALL remain non-purchasable until a real entitlement service exists.

#### Scenario: Credentials and missing configuration
- **WHEN** a user changes the provider destination or remote authentication is not configured
- **THEN** destination consent is requested again, keys are not copied into plaintext settings, and unavailable remote actions clearly report their condition without fabricating login or connectivity.

#### Scenario: Account operations
- **WHEN** a real account operation fails or a user cancels deletion
- **THEN** personal entries and credentials are not silently erased; local-owner operation and remote-provider verification remain separately evidenced.

### Requirement: Existing records remain intact
The expanded store SHALL read the iOS pilot's schema-1 now records, preserve all supported content during migration, and retain original bytes when decoding or writing fails. Unknown future versions MUST block destructive rewriting.

#### Scenario: Upgrade and storage failure
- **WHEN** an existing pilot record is loaded and a new richer record is saved, or a write fails
- **THEN** the old record survives unchanged in meaning and a failed write leaves the original file and unsaved input intact.

## 2026-09-29 user-authorized scope amendment

The current reference is the actual public Web experience at https://milo.huangtangai.top/app, per the user's explicit direction; do not launch HarmonyOS. Preserve the prior Harmony evidence as historical. Develop only in /Users/hut/Projects/milo. The current phase restores Web starfield/touch motion and page semantics while improving native iOS controls, retains all 53 native state checks, and records Web-absent native states separately without fabricating reference screenshots. See docs/visual-parity/web-native-plan-2026-09-29.md for the reviewed implementation and acceptance plan. This amendment supersedes the prior requirement to use a sibling worktree or to obtain new Harmony runtime captures for this phase; real account/device release claims remain separate.

## ADDED Requirements

### Requirement: Account settings affect actual behavior
The iOS client SHALL expose login and account settings through normal navigation and SHALL apply saved AI defaults to new memories and explicitly saved settings to the active conversation. Restored drafts SHALL preserve their existing per-conversation choice. A password reset that succeeds before sign-in fails SHALL return to password sign-in with accurate status. Remote sign-out cleanup failure SHALL NOT trap a user in the local account; unsuccessful local cleanup SHALL remain an error.

#### Scenario: Saved AI default and active request
- **WHEN** the user disables AI and saves settings during an active request, then starts a new memory or restarts
- **THEN** the old request cannot mutate the conversation, the new memory uses the saved default, and a restored draft retains its recorded choice

#### Scenario: Reset succeeded before sign-in failed
- **WHEN** the service resets the password but subsequent password sign-in fails
- **THEN** the user sees that the password changed and can retry password login without reusing the consumed reset code

#### Scenario: Offline exit
- **WHEN** remote sign-out cleanup fails while local session storage is writable
- **THEN** the app returns to login and retains the user's local memories and draft content

### Requirement: Simulator installation is launchable and identifiable
The delivered simulator build SHALL launch from its normal home-screen icon using Xcode-generated signing and SHALL include a compiled opaque MILO AppIcon. Repeated cold launch and foreground/background transitions SHALL preserve the current account and records without unexpected exits. A successful build alone MUST NOT be reported as installation acceptance.

#### Scenario: Restore a previously broken installation
- **WHEN** a simulator installation is replaced after signing-related launch failure
- **THEN** installed bytes match the verified build, icon launch reaches login or the retained journal, and repeated cold launches succeed without deleting production data

#### Scenario: Native secure storage
- **WHEN** isolated personal credentials are saved, read and removed in the simulator test environment
- **THEN** actual Keychain operations succeed with Xcode-supported signing and failures are not replaced by plaintext or simulated success


## 2026-10-03 user-authorized iOS conversation amendment

This phase changes iOS conversational behavior within the existing page families. It supersedes reference parity for the present-chat entry and fixed-turn offline guidance; Web, HarmonyOS and the shared gateway remain outside this phase. It does not authorize publication, new backend services or paid model calls.

### Requirement: Present expression can be a conversation or a free note
The iOS client SHALL offer present conversation directly from classification without a past-time selection, while retaining the existing free-note path. Both present and past conversations SHALL allow explicit raw-transcript collection and an optional diary made only on user request. Ending SHALL preserve a device-local resumable draft without creating an entry or requesting a diary. Starting a new mood journey with a draft SHALL make replacement explicit.

#### Scenario: Today I want to vent
- **WHEN** the user chooses present conversation and says “今天心情不好，想吐槽”
- **THEN** no past-time selection is required; the current conversation context describes today/present expression

#### Scenario: Exit without a diary
- **WHEN** the user says “先到这里，也不用生成日记” or uses the exit action, including during an outstanding reply
- **THEN** no diary request or saved entry is created, late replies cannot mutate the draft, and raw text is recoverable after restart from the resume action

#### Scenario: Deliberate optional collection
- **WHEN** the user chooses raw collection or diary preparation in a present or past conversation
- **THEN** raw collection performs no diary call, while diary preparation uses user-provided facts only and remains editable and optional; the stored kind and full transcript are preserved

#### Scenario: Cancel new mood selection with an existing draft
- **WHEN** a retained conversation exists, the user selects another home-ring mood and cancels new-record confirmation
- **THEN** the retained draft's mood and content remain unchanged on disk and after restart; the new mood is applied only on confirmed new-record creation

### Requirement: Listening-first contextual replies remain intact
The conversation instruction SHALL prioritize the user's concrete situation and expressed preference. It SHALL permit a response with no question, ask at most one necessary question, avoid unsolicited advice and imposed positive meaning, distinguish facts/feelings from assumptions about others, and provide proportionate help when explicitly requested. The client SHALL preserve full returned text, including emoji, newlines and trailing content, without a 48-character cutoff. Prompt and mock checks SHALL NOT be represented as proof of model semantic quality.

#### Scenario: Venting, uncertainty and requested advice
- **WHEN** synthetic messages include “开了一天会，最后被加活，只想说说，先别建议”, “最近每天这样”, “同事没回消息肯定看不起我，别一味附和”, then “请给两个建议”
- **THEN** requests retain the verbatim latest message and the instruction covers listening without a mandatory question, uncertainty and requested help; actual reply quality requires separate multi-sample human evaluation

#### Scenario: Long reply
- **WHEN** a mock returns more than 48 characters with emoji, newlines and an explicit final sentence
- **THEN** the coordinator retains an identical string and the native conversation renders its complete content

### Requirement: Unavailable AI is honest and recoverable
The client SHALL disclose that the default hosted model is unconnected in this build before a user sends. Local recording SHALL not imply semantic understanding or append turn-count scripted responses. Personal-provider requests SHALL retain the current consent/HTTPS/account/Keychain contract. Network, authentication and empty-response failures SHALL preserve user expression, end loading, and offer settings or explicit retry; continued local expression SHALL not automatically repeat failed calls. Duplicate sends and late completions after stop, back, settings, AI-off or exit SHALL not duplicate or corrupt transcript content. No new backend connection is claimed.

#### Scenario: Default or disabled AI
- **WHEN** the default model is unconnected or AI is disabled
- **THEN** the client records user text locally without a network request, clearly shows local capability and offers AI settings or raw collection

#### Scenario: Timeout or authentication failure
- **WHEN** a mock produces timeout or authentication failure, then the user continues writing and deliberately retries
- **THEN** the failure is visible with no fabricated assistant response, no indefinite loading or repeated automatic call; retry appends at most one reply without duplicating user text



### Requirement: Additive backward-readable present diary encoding
Present diaries SHALL keep the existing now/past kind vocabulary, encode the legacy diaryEnabled flag as false for now entries, and record their enabled state in an optional presentDiaryEnabled flag. Prior iOS storage decoders SHALL still read old and new entries together without rejecting the whole file. Current iOS SHALL read old journals and drafts without mutation. Compatibility checks SHALL use synthetic fixtures and the repository's prior decoder, without operating another client or reading personal records.

#### Scenario: Read old files and new exports across decoder versions
- **WHEN** current iOS reads a prior diary or draft, or the prior iOS decoder reads a current export with present and past entries
- **THEN** content, kind, transcript, mood and existing records remain readable; no new kind enum is required. A prior client's inability to offer the new present-chat workflow or retain an unknown flag on rewrite SHALL not be described as file import support


## 2026-10-04 user-authorized iOS refinement

### Requirement: Original brand artwork and quiet conversation layout
The iOS AppIcon SHALL reuse the repository's original MILO brand image byte-for-byte. Its preparation script SHALL restore that source rather than draw a replacement. The chat SHALL keep conversation and a keyboard-aware input bar primary. A short capability status SHALL remain visible; provider limitations and error details SHALL be available on demand. Explicit raw collection, diary preparation and exit SHALL remain available through the conversation menu. Native checks SHALL cover large text, keyboard reachability, complete long replies, menu actions and draft persistence.

#### Scenario: Honest capability without persistent instructional clutter
- **WHEN** an unavailable provider is selected
- **THEN** the header visibly identifies local recording before send; tapping the status reveals the limitation and a settings action, while exit and optional save actions remain in the menu

### Requirement: Continued conversation invalidates an earlier diary
- **WHEN** a user returns from a generated or edited diary to chat and sends another message
- **THEN** the old diary cache is cleared, the transcript is preserved, and the next explicit diary request includes the new user content
