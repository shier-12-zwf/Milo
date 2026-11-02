## Purpose

Keep optional iOS speech entry stable across permission decisions and recording lifecycle changes, preserving the user's writing and keyboard access.

## ADDED Requirements

### Requirement: Safe asynchronous speech callbacks
The application SHALL accept permission, audio and recognition callbacks on their documented execution contexts without terminating the application.

#### Scenario: Background authorization and recognition
- **WHEN** speech authorization or recognition returns on a background queue
- **THEN** the app remains responsive and updates recording state and text on its UI executor

#### Scenario: Native speech entry
- **WHEN** the user taps the real speech control repeatedly with granted permissions
- **THEN** the app either records and can stop or shows an actionable keyboard fallback without terminating

### Requirement: Denied or unavailable speech keeps keyboard access
The application SHALL preserve existing input and expose keyboard entry when permissions, recognizer or audio hardware are unavailable.

#### Scenario: Permission refusal
- **WHEN** either microphone or speech permission is denied
- **THEN** the app shows the reason, preserves prior text and permits typing and sending

#### Scenario: Recording setup or recognition failure
- **WHEN** recording cannot start or recognition fails after partial text
- **THEN** resources are released and the prior text and any accepted partial text remain editable

### Requirement: Recording lifecycle cancellation
The application SHALL prevent cancelled starts and stale callbacks from changing the current recording session.

#### Scenario: Cancel while permission is pending
- **WHEN** the user cancels, leaves chat or backgrounds the app before permission returns
- **THEN** the late permission result does not start audio capture

#### Scenario: Repeated start and stale result
- **WHEN** the user starts repeatedly or a previous session returns after stop and restart
- **THEN** at most one capture exists and the previous session cannot overwrite the current text or stop it

#### Scenario: Interruption and background
- **WHEN** recording is interrupted or the app moves to background
- **THEN** capture stops, input remains available and resuming does not silently restart the microphone
