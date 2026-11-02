# iOS Offline Journal

## Purpose

Let an iPhone user privately capture their current mood and optional words, and retrieve the same records after restarting, without an account or network connection.

## ADDED Requirements

### Requirement: Capture the current mood
The app SHALL default to 平静 and offer 雀跃, 明亮, 还不错, 平静, 有些沉, 低落, 非常低落 with valences 3 through -3. A present-moment record SHALL have `kind=now`, `diaryEnabled=false`, a stable unique ID, and creation time in milliseconds since the Unix epoch.

#### Scenario: Save a written note
- **WHEN** a user selects 明亮, enters `  今天散步很开心  ` and saves
- **THEN** exactly one record with valence 2, emotion ID `bright`, and trimmed note `今天散步很开心` is stored and visible in history

#### Scenario: Save only a mood
- **WHEN** a user saves a blank or whitespace-only note
- **THEN** the selected mood is saved and history displays `（一次安静的记录）`

### Requirement: Durable local history
The app SHALL store records locally, show newest records first with a deterministic ID tie-breaker, and display a selected record's mood, note and creation time. Saving an existing ID SHALL replace that record without duplication.

#### Scenario: Relaunch
- **WHEN** a user saves a note, terminates and relaunches the app using the same data location
- **THEN** history and detail show the original note and mood without network or credentials

#### Scenario: New installation
- **WHEN** no data file exists
- **THEN** history shows `这里还很安静` and permits creating the first record

#### Scenario: Repeated identity
- **WHEN** the same record ID is saved twice with a revised note
- **THEN** history contains one record with the revised note

### Requirement: Preserve data when persistence fails
The app SHALL display a recoverable error without claiming save success on failed reads or writes. An unreadable, invalid or unsupported-schema file SHALL remain untouched; saving SHALL be blocked until successful reload. Draft text SHALL remain available after a write error.

#### Scenario: Corrupt or newer data
- **WHEN** the stored file is malformed JSON, has an unsupported schema version, or contains invalid record values
- **THEN** the app reports an error, does not substitute a writable empty journal, and preserves the bytes on disk

#### Scenario: Write failure
- **WHEN** persistence returns an error during save
- **THEN** existing records and the user's draft remain unchanged, and the UI shows a failure with retry available

### Requirement: Accessible native capture
The app SHALL provide labelled native controls, a scrollable editor and history, and a visible save action with the keyboard open on a small iPhone. It SHALL adapt text to system text sizing and render correctly in light and dark appearance.

#### Scenario: Keyboard and large text
- **WHEN** a user edits a long Chinese note on a small iPhone using an accessibility text size
- **THEN** text can be scrolled, save remains reachable, and the saved detail contains the full note
