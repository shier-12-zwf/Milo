---
name: specdrive
description: >-
  Run multi-step development with OpenSpec specifications, independent review,
  bounded implementation, and recorded verification. Use when the user requests
  specdrive, spec-first development, or unattended implementation with a clear
  product direction. Skip this workflow for trivial edits or open-ended ideation.
---

# specdrive

Turn authorized product work into a traceable sequence:

**Specify → review → implement → verify and repair → archive when complete.**

OpenSpec owns artifact scaffolding, dependencies, task tracking, validation, and
archiving. This skill coordinates the agent. Its local runner executes configured
checks and records evidence; it is neither an autonomous model service nor a scheduler.

## Working contract

- Proceed independently within the user's established scope. Independent AI review
  checks engineering quality; it does not grant product, account, payment, or release
  authorization. Honor a request for step-by-step approval, but do not invent new gates.
- Read the repository's instructions and preserve existing work. Confirm the project
  from context; never initialize OpenSpec in a personal home directory by accident.
- Treat missing tools, unavailable review, stale evidence, and unexecuted scenarios
  as incomplete. A task checkbox or successful build alone does not prove completion.
- Do not promise token or cost enforcement: the runner limits command attempts and
  elapsed time, not model tokens. Continued work after this session requires a separately
  configured execution service or user resumption.

## 1. Specify and review

Read [the OpenSpec and host workflow](references/workflow.md). Inspect installed CLI
help/version and use the available host adapter, not invented tool names or model IDs.
Follow the active schema's dependency order, usually proposal → specs/design → tasks.

Write measurable acceptance scenarios, explicit exclusions, and a verification plan.
Map each required scenario to a check or identifiable external evidence. Include
negative and persistence cases where relevant, not only successful first-run behavior.

Before implementation, ask an independent reviewer to inspect the artifacts and
acceptance coverage. Record the reviewed revision or file hashes, findings, and verdict.
Allow at most **two review-and-revision rounds**; stop earlier after the same unresolved
finding repeats twice. If independent review is unavailable, record the blockage and
finish useful preparation without pretending the gate passed. Review does not replace
any product decision the user has reserved for themselves.

## 2. Implement in bounded workstreams

Read OpenSpec's apply instructions and context files. Assign independent modules or
features to agents only when doing so improves progress. Define ownership and shared
interfaces first; keep one integration owner for shared project configuration and task
checkboxes. Use worktrees when isolation is useful, not one agent per file or maximum
concurrency as a goal. Tell workers others are editing the project and not to revert them.

Keep milestones runnable. Check off a task only when its acceptance condition has
evidence. Record design changes in the affected artifacts and re-review material scope
or architecture changes. Fix routine implementation issues within existing authorization.

## 3. Verify, repair, and resume

Read [the runner contract](references/runtime.md) before configuring or using it.
Include required environment checks and actual behavior assertions. Declare the inputs
that affect each check so a source or test change invalidates its earlier result.
For native iOS work, also read [the iOS profile](references/ios.md).

Use the runner to capture check output, attempts, timeouts, and current input hashes.
The agent repairs failures between invocations; the runner does not repair code. Bound
agent repair work to three attempts per failing requirement and stop after two attempts
without meaningful progress. Runner limits independently enforce command execution.
Do not reset state or weaken required checks just to bypass a limit or obtain green output.

Before resuming, read OpenSpec task status, the runner state, the working tree, and the
last review. Re-run affected checks and refresh review after relevant changes. Independent
final review must inspect the implementation and evidence against the scenarios, rather
than accepting the implementation agent's summary.

## 4. Complete or report the remaining work

Archive through OpenSpec only when required tasks, scenarios, current runner checks,
external evidence, and final review all pass. `gate` checks runner evidence only; it does
not authorize archiving, validate product scope, or certify the reviewer.

If anything remains blocked, keep the change active. Report what was implemented,
what actually ran, what failed or could not run, the saved state path, and the concrete
next action. Distinguish a useful partial milestone from a completed product.
