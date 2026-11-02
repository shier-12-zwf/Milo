# iOS Evidence Gates

## Purpose

Make the development milestone auditable by preserving executable verification evidence and distinguishing portable logic checks from actual iOS build and runtime validation.

## ADDED Requirements

### Requirement: Current platform evidence
The milestone SHALL require portable behavior tests, an iOS simulator build, iOS UI relaunch tests, and visual accessibility review before full completion. Evidence SHALL identify commands, exit status, time, relevant inputs, and limitations.

#### Scenario: Xcode missing
- **WHEN** only Command Line Tools are available
- **THEN** portable tests may pass, but iOS checks are blocked and the change is not archived or reported as fully verified

#### Scenario: Sources change after verification
- **WHEN** a relevant source or check command changes after a passing check
- **THEN** the prior result is stale and cannot satisfy the completion gate

### Requirement: Bounded resumable verification
The verifier SHALL persist check outcomes, enforce configured check timeouts and attempt caps, and reuse only valid successful evidence. It SHALL execute checks directly and never infer test success from a reviewer summary.

#### Scenario: Interrupted verification
- **WHEN** a run is interrupted and resumed
- **THEN** completed unchanged successful checks can be reused and incomplete checks remain unverified until executed

#### Scenario: Repeated failure
- **WHEN** an unchanged failing check reaches the configured no-progress limit
- **THEN** the verifier stops that check, reports the reason and preserves existing logs
