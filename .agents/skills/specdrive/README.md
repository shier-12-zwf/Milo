# specdrive

**Spec-driven development for Codex and Claude Code, with recorded verification.**

A thin coordination layer over [OpenSpec](https://github.com/Fission-AI/OpenSpec).
It turns an authorized feature request into specifications, independent review,
implementation, and evidence of what actually works.

[中文说明](#中文说明) · [English skill](SKILL.md) · [中文 skill](SKILL.zh.md)

## How it works

```text
Specify → Independent review → Implement → Verify / repair → Archive when complete
   OpenSpec artifacts              Agent work        Local check runner
```

- **OpenSpec** owns proposal/spec/design/task artifacts, dependency order, validation,
  progress tracking, and archiving.
- **The host agent** plans and implements within the user's scope, delegates independent
  workstreams when useful, repairs failures, and obtains independent review.
- **The runner** executes configured commands, stores logs and input fingerprints,
  checks freshness, and bounds retries/time. Missing prerequisites stay blocked.
- **Completion** requires current behavior evidence and final review. A green runner
  does not prove that its configuration covers every product requirement.

Default mode proceeds within established authorization. Say “confirm each step” to
use an attended workflow. AI review assesses quality; it cannot authorize scope changes,
accounts, payments, or publication on the user's behalf.

## What changed from the original skill

The original version primarily described a Claude workflow in one long prompt.
This version adds Codex adaptation and a small executable verification harness:

| Before | Now |
| --- | --- |
| Claude-specific tool assumptions | Host adapters using capabilities actually available |
| All instructions loaded together | Concise bilingual skill with focused references |
| One agent per file, maximum parallelism | Module/feature ownership, shared interface decisions, optional worktrees |
| Retry and budget promises in prose | Persistent command attempts, timeout/no-progress limits; no claim to limit model spending |
| Completion judged from task state | Current evidence plus independent review and explicit blocked outcomes |
| Generic verification | Native iOS profile separating macOS core tests from simulator validation |

It is **not** an always-running model agent, a scheduler, or a sandbox. The agent must
be active to fix code and resume checks. Cross-session autonomous execution needs a
separately configured host service. Commands run with the host user's permissions.

## Requirements

- Codex or Claude Code with filesystem and command execution capabilities.
- Independent review capability for the review gates.
- Node.js **>=20.19** for OpenSpec and the runner.
- OpenSpec. The CLI integration was inspected with **1.13.2**; use the installed version's
  help/JSON and record its version. Other releases are not implied to have been tested.
- The actual project's development toolchain; iOS simulator validation needs full Xcode
  and an installed iOS runtime.

If OpenSpec is not available, install a chosen version in an authorized tool location.
For a project-local installation:

```sh
npm install --save-dev @fission-ai/openspec@1.13.2
npx --no-install openspec --version
```

For a non-npm repository, an isolated tool directory avoids introducing unrelated package
files. A global installation is also possible when appropriate; do not silently replace
an existing version.

## Install the complete skill

Copying only `SKILL.md` is no longer sufficient: the skill needs `references/` and
`scripts/`. From a checkout of this repository, choose one destination.

Codex, project-local (run in the target project's root):

```sh
git clone https://github.com/horton2048/specdrive.git .agents/skills/specdrive
```

Codex, personal:

```sh
git clone https://github.com/horton2048/specdrive.git "${CODEX_HOME:-$HOME/.codex}/skills/specdrive"
```

Claude Code, personal:

```sh
git clone https://github.com/horton2048/specdrive.git "$HOME/.claude/skills/specdrive"
```

If developing an unpublished local revision, copy the entire skill directory to the
chosen destination instead of cloning the published repository. Preserve an existing
installation rather than overwriting it blindly. To select Chinese, copy `SKILL.zh.md`
over `SKILL.md` **in the installed copy**; keep both source versions maintained here.
When committing a project-local copy, omit the source checkout's `.git` directory so
the skill's files are tracked normally rather than as an embedded Git repository.

Invoke the installed skill with “use specdrive to build …” and the intended project/scope.
The skill drives OpenSpec directly; it does not depend on a particular slash command.

## Verification runner

Create a project-specific check config using [the runner reference](references/runtime.md).
Then, with the script path pointing at your installation:

```sh
node scripts/specdrive.mjs init /path/to/checks.json --project /path/to/project
node scripts/specdrive.mjs run /path/to/project/.specdrive/<run-id>
node scripts/specdrive.mjs status /path/to/project/.specdrive/<run-id>
node scripts/specdrive.mjs gate /path/to/project/.specdrive/<run-id>
```

`init` prints the new state directory. `run` makes one pass; the agent fixes failures
between passes. Exit 0 means required checks passed, 1 failed, and 78 blocked;
`init`/`status` exit 0 on successful execution and errors use 2.

Attempts, logs, hashes, and active execution time survive invocations. Changed source
invalidates relevant evidence. Configuration changes need a new state directory, preserving
the old record. Do not reset state merely to bypass a limit. Read the reference for
dependency ordering, input hashing, timeout behavior, and recovery.

For native iOS, read [the iOS profile](references/ios.md). Missing Xcode is blocked even
when `swift test` succeeds on macOS. Native build, UI interaction, and restart persistence
need their own evidence.

## Development

```sh
node --test tests/*.test.mjs
```

These tests exercise the runner, not arbitrary applications developed with it. A real
project pilot needs its own acceptance results; no product readiness claim follows from
this repository's tests alone. [The original todo example](examples/) is retained as an
illustration of OpenSpec artifacts, not evidence for the new runner or iOS support.

## 中文说明

**给 Codex 和 Claude Code 使用的规格驱动开发框架，包含可执行的验证运行器。**

流程是：写规格 → 独立审核 → 实施 → 验证和修复 → 达标归档。
OpenSpec 管理规格、依赖、任务和归档；Agent 负责开发、修复和审核；
本地运行器执行配置好的检查，保留日志、输入哈希、尝试次数和耗时。

本版升级了 Codex 适配、按模块分工、断点恢复和原生 iOS 验证要求。
中英文入口分别是 [SKILL.md](SKILL.md) 和 [SKILL.zh.md](SKILL.zh.md)，共享
[宿主流程](references/workflow.md)、[运行器说明](references/runtime.md)、
[iOS 验证要求](references/ios.md)。

安装必须包含整个目录，不能只复制入口文件。Codex 项目内可放在
`.agents/skills/specdrive`，个人安装可放在 `~/.codex/skills/specdrive`；
Claude Code 可放在 `~/.claude/skills/specdrive`。选择中文时，在安装副本中
用 `SKILL.zh.md` 替换 `SKILL.md`。依赖 Node >=20.19 和 OpenSpec；
本次检查过的 OpenSpec 版本为 1.13.2。

“无人值守”指在已有授权内自主推进，不代表获得额外产品或发布授权。
它没有隐藏的后台服务，也不计量或强制限制模型费用。Agent 活跃时负责修复，
运行器每次调用执行一轮检查；跨会话继续工作需要额外配置调度或由用户恢复。

缺少 Xcode、iOS 模拟器或有效证据时，必须保留阻塞，不能因为 macOS 上单元测试
通过就宣称 iOS 已验收。归档要求当前检查、必需场景、外部证据和最终独立审核
全部满足；仅有任务打勾或运行器全绿还不够。

## Credit and license

Built on [OpenSpec](https://github.com/Fission-AI/OpenSpec) by Fission-AI.
Specdrive adds coordination, review gates, and a local evidence runner. [MIT](LICENSE).

## Pilot evidence / 实测记录

See [the 2026-09-25 Codex and MILO validation report](docs/validation-2026-09-25.md) for executed checks, discovered defects, fixes, and platform limitations.
