## ADDED Requirements

### Requirement: Visible keyboard input
The simulator SHALL show its screen keyboard after tapping an editable chat field and SHALL allow typing and sending without losing existing draft text.

#### Scenario: Tap and send
- **WHEN** a test user taps the chat input
- **THEN** XCUI shall find a visible keyboard, append text to the existing fixture, send it and observe the sent text

### Requirement: Usable speech entry
Speech SHALL use supported system routing and SHALL distinguish service failure from silence.

#### Scenario: Actual recording
- **WHEN** authorized voice input is started on the simulator
- **THEN** actual speech state shall reach recording and remain recording for five seconds, and stopping shall preserve text

#### Scenario: Real transcription
- **WHEN** Chinese speech is provided through the real recognition API or microphone
- **THEN** a nonempty recognized Chinese result shall be observed without injected transcript

#### Scenario: Service unavailable
- **WHEN** Apple's recognition service cannot start
- **THEN** a service unavailable message shall be shown, keyboard input shall remain usable, and this shall not pass the usable speech requirement
