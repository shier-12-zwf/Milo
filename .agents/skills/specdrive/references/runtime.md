# Local verification runner

The runner is an auditable command harness. It invokes configured checks, saves
results, and enforces command limits. The host agent performs planning, code repair,
and review. There is no model API loop, background daemon, scheduler, or token meter.

## Commands

Run from the skill's installed directory, or replace the script path with its absolute path:

```sh
node scripts/specdrive.mjs init /path/to/checks.json --project /path/to/project
node scripts/specdrive.mjs run /path/to/project/.specdrive/<run-id>
node scripts/specdrive.mjs status /path/to/project/.specdrive/<run-id>
node scripts/specdrive.mjs gate /path/to/project/.specdrive/<run-id>
```

`init` prints the state directory. Optional `--state <dir>` chooses a **new** directory;
existing state is not overwritten. `run` attempts each eligible check once, in order.
It reuses passed, current verification results; preflights run again on each invocation.
The agent inspects failures, repairs the implementation, and invokes `run` again.

`status` and `gate` inspect freshness without executing checks. Both return JSON.
`gate` is convenient for a CI step: exit 0 means all required configured checks have
current successful evidence. It does not prove that the configuration covers the specs
or that an independent reviewer approved the implementation.

| Exit | Meaning |
| --- | --- |
| 0 | Required checks passed (`run`/`gate`); command succeeded (`init`/`status`) |
| 1 | Required check failed |
| 78 | Blocked: missing prerequisite, dependency, fresh evidence, or execution allowance |
| 2 | CLI/configuration/lock error |

A check should return **78** for an unavailable prerequisite. A missing executable and
a timeout also become blocked. Other nonzero check exits are failures. If failed and
blocked required checks coexist, the overall status is blocked; inspect individual checks.

## Configuration

Example only: substitute real paths, commands, assertions, and time limits for the
target project. The runner does not generate or select tests.

```json
{
  "version": 1,
  "checks": [
    {
      "id": "toolchain",
      "kind": "preflight",
      "argv": ["node", "-e", "const [major,minor]=process.versions.node.split('.').map(Number);process.exit(major>20||(major===20&&minor>=19)?0:78)"],
      "cwd": ".",
      "inputs": [],
      "required": true,
      "timeoutMs": 10000,
      "maxAgeMs": 300000
    },
    {
      "id": "journal-tests",
      "kind": "verification",
      "argv": ["node", "--test", "tests/journal.test.mjs"],
      "cwd": ".",
      "inputs": ["src", "tests"],
      "dependsOn": ["toolchain"],
      "required": true,
      "timeoutMs": 120000
    }
  ],
  "limits": {
    "maxAttemptsPerCheck": 3,
    "maxNoProgress": 2,
    "maxWallTimeMs": 900000
  }
}
```

The illustrative preflight checks Node >=20.19, matching the runner requirement.
Check IDs are unique lowercase letters/digits/hyphens/underscores.
`argv` is a nonempty string array executed **without a shell**. A pipeline, redirect,
or wildcard will not be expanded. Put complex assertions in a reviewed script and include
that script in the check inputs.

`cwd` and `inputs` are relative to the project root, even when a check's working
directory is elsewhere. They cannot use absolute paths or escape the project. Inputs
must exist; verification checks require a nonempty list. There is no glob expansion.
Include sources, tests, project settings, manifests/lockfiles, and verification scripts
that affect the result. Avoid including outputs that the check itself will modify.

Directories are hashed recursively in sorted order. Recursive child entries named
`.git`, `.build`, `node_modules`, `.specdrive`, `build`, and `DerivedData` are skipped;
an explicitly supplied input is entered even if its name is normally skipped. Symlink
inputs are unsupported. A declared directory detects added/deleted files; a hand-picked
file list cannot detect an undeclared new dependency.

`dependsOn` names earlier checks; unpassed dependencies block a command without consuming
an attempt. `required` defaults to true. Optional checks remain visible but cannot satisfy
required scenarios. `env` may supply string values such as `DEVELOPER_DIR`; it is stored
in the configuration snapshot, so do not put credentials there. Commands inherit the
host environment. Use preflights and optional `maxAgeMs` for external state that file
hashes cannot establish, such as available simulator runtimes.

## Limits, evidence, and recovery

Limits are cumulative within one initialized state:

- `maxAttemptsPerCheck` counts executions, including successful preflight reruns.
- `maxNoProgress` stops repeated unsuccessful results with the same input fingerprint,
  status, exit, and reason. A changed source resets this repetition count, not total attempts.
- `maxWallTimeMs` bounds active runner time across invocations. Time spent editing or
  waiting between invocations is excluded. `timeoutMs` also limits each individual check.

Saved state contains the normalized config, check attempts, input fingerprints, times,
statuses, reasons, and log paths/hashes. `report.json` is the last run's snapshot;
`status` recomputes current freshness. State stores absolute project and evidence paths;
keep the run directory in place when resuming. A pass is invalidated by changed declared inputs,
runner code, configuration, missing/altered logs, expired evidence, or an unmet dependency.
Inputs changed during execution leave the result blocked. Hashes detect accidental
staleness; local state is not signed or tamper-proof.

An exclusive lock prevents concurrent mutation of one run. Interrupted commands retain
blocked evidence and consumed attempts. Inspect state and running processes before
recovery; do not delete a lock held by a live process. A malformed lock or interrupted
recovery guard needs deliberate inspection. Keep original logs when resuming.

If configuration changes or limits are exhausted, preserve the old state and explain
why a revised plan is justified before creating a new run. Do not automatically create
fresh runs to defeat stopping conditions. Source repairs within limits reuse the state.

The runner cannot inspect undeclared dependencies, authenticate a reviewer, or judge
whether a passing assertion is meaningful. Review may be implemented as an additional
configured check, but that check must validate actual external review evidence; a
self-written "approved" flag is insufficient. Follow the skill's full completion contract
before archiving regardless of any convenience field in runner output.

This is not a sandbox. Configured commands have the invoking user's permissions and
can mutate the project or access the network. Review command configuration within the
user-authorized task; do not execute an untrusted repository's commands blindly.
