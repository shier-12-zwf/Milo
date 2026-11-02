# OpenSpec and host adapters

## Host selection

Use the host already running the task. Keep its existing model unless the user chooses
another one. Do not assume Claude's `Agent`, `TodoWrite`, or `AskUserQuestion` tools
exist in Codex, or that Codex tools exist in Claude.

| Capability | Codex | Claude Code |
| --- | --- | --- |
| Project initialization | `openspec init --tools codex .` | `openspec init --tools claude .` |
| Parallel work and review | Available agent tools; otherwise report unavailable independent review | Available agent tools; otherwise the same limitation |
| Task record | OpenSpec `tasks.md`, updated by the integration owner | Same |
| Runtime checks | Shell capability running `scripts/specdrive.mjs` | Same |
| User decisions | Normal conversation or an available question tool | Same |

Generated host skills or commands are conveniences. Driving OpenSpec's CLI directly
does not require a specific slash command to be available in the current session.

## Preflight

Inspect `git status`, repository instructions, project root, Node version, and
`openspec --version`. Resolve a project-local installation if the global command is
absent. Inspect help before using optional flags. Set `OPENSPEC_TELEMETRY=0` when
calling OpenSpec. An authorized project-local dependency install is preferable to
silently replacing a global installation; record the selected version.

The commands below were inspected with **OpenSpec 1.13.2**. Newer or older versions
may expose different fields; use the running CLI's JSON instead of assuming a schema.

## Artifact workflow

From the selected project root:

```sh
openspec new change "<change-name>"
openspec status --change "<change-name>" --json
openspec instructions proposal --change "<change-name>" --json
```

Follow `artifacts[].status`, dependencies, and `applyRequires`. Request instructions
for each ready artifact before writing it. Read its dependencies and follow `template`
and `instruction`; `context` and `rules` constrain the work rather than becoming copied
boilerplate. With the default schema, produce proposal, specs, design, and tasks.
Respect a repository's existing custom schema instead of imposing four documents.

Path handling matters:

- Prefer `resolvedOutputPath` **when the returned JSON provides it**. In 1.13.2 it
  appears on instructions and in the status `artifactPaths` map, not necessarily on
  each `artifacts[]` item.
- Otherwise resolve a relative `outputPath` against the returned `changeDir` (or
  the change root reported by status). An already absolute path stays absolute.
- A path such as `specs/**/*.md` is a pattern for capability files, not a literal
  filename. Use the capability paths declared in the proposal and CLI instructions.
- Honor `actionContext` edit roots and store information when supplied. Do not
  reconstruct paths from the current working directory if the CLI reports another root.

Re-read status after each artifact. In the default spec-driven schema, scenarios use
`#### Scenario:` headings and requirements must have observable outcomes. Consult
existing capability specs before adding a near-duplicate. Validate with:

```sh
openspec validate "<change-name>" --type change --strict --no-interactive
```

OpenSpec validation checks artifact structure and consistency; it does not run the app.

## Review gate

Give the reviewer the user request, artifacts, relevant existing behavior, and known
environment constraints. Require a verdict with concrete evidence on:

1. Scope and user value match the authorization; exclusions are explicit.
2. Requirements cover relevant empty/error/boundary/persistence behavior.
3. Scenarios can be verified; proposed checks actually assert their outcomes.
4. Design choices fit the existing system and name consequential tradeoffs.
5. Tasks have dependencies, ownership, and observable completion conditions.

Save review findings alongside the change with reviewed file hashes or a commit plus
working-tree patch hash. Do not use a bare `HEAD` identifier when uncommitted files were
reviewed. Fix actionable findings within the review limit in `SKILL.md`. Preserve the
evidence of failed rounds. A model's confidence or an implementation agent's self-review
is not independent review.

## Apply and close

```sh
openspec instructions apply --change "<change-name>" --json
```

Read the returned context files. A blocked state returns to the missing artifacts.
An `all_done` state means task tracking is complete, not that acceptance has passed.
Keep verification and review requirements explicit in the task list.

After current evidence and final review meet the skill's completion contract:

```sh
openspec instructions archive --change "<change-name>" --json
openspec archive "<change-name>" --yes
```

Honor an explicitly requested attended workflow before archiving. Do not use
`--no-validate` or `--skip-specs` to conceal incomplete work. A release or deployment
is a separate action with its own authorization; archiving does not publish software.
