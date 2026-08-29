# AI Commit Attribution Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在治理源、Backend、Desktop、Admin 及未来可接入的 iOS 项目中，阻止新的 AI/Bot Git 作者归属和 `Co-Authored-By` trailer，同时保留 AI 在 PR/Issue 中的透明披露，并且不重写历史提交。

**Architecture:** `agent-governance` 维护公共规则和无 Node/npm 依赖的 shell 检查脚本；每个业务仓库携带版本化的 `AI-GOVERNANCE.md` 与检查脚本快照。项目本地 hook 负责提交前快速失败，项目 CI 只扫描 PR/push 新增 commit，治理源和项目仓库分别维护自己的规则与代码。

**Tech Stack:** Markdown、Bash、Git hooks、GitHub Actions、现有 Admin Husky/commitlint；不新增运行时依赖。

**Spec:** `docs/superpowers/specs/2026-08-29-ai-commit-attribution-policy-design.md`

## Global Constraints

- 禁止所有大小写形式的 `Co-Authored-By`、`Co-Authored-by`、`Co-Author`、`Coauthor` trailer。
- 禁止已知 AI、模型或 Bot 出现在 Git author/committer name 或 email 中。
- AI 参与只记录在 PR、Issue、审查报告或 Execution Summary，不写入 commit metadata。
- `Governance-Exception` 是 owner 审批记录，继续允许，不视为 AI 作者归属。
- 历史 commit、远端分支和现有用户 WIP 不重写、不覆盖、不 force push。
- CI 只检查当前 PR 或 push 新增的 commit 范围，不因旧历史中的违规 trailer 失败。
- 公共规则由 `agent-governance` 维护，项目仓库携带同步快照；项目维护者不能自行修改公共快照内容。
- 检查脚本不依赖 Node、npm、TypeScript、Xcode 或项目业务代码。
- 现有工作树中的未提交修改属于用户资产；只修改本任务目标文件，不使用 `git add -A`。

---

### Task 1: Update governance source rules

**Files:**

- Modify: `global/AGENTS.md`
- Modify: `global/ai-change-implementation-prompt.md`
- Modify: `team-contract.md`
- Modify: `onboarding.md`
- Modify: `README.md`
- Modify: `VERSION`

**Interfaces:**

- Consumes: the approved policy in `docs/superpowers/specs/2026-08-29-ai-commit-attribution-policy-design.md`.
- Produces: a governance source that explicitly forbids AI/Bot author, committer, and co-author metadata and directs disclosure to PR/Issue text.

- [ ] **Step 1: Remove the contradictory positive requirement**

Replace the existing `team-contract.md` rule that requires `Co-Authored-By: <AI 模型名>` with:

```markdown
2. **禁止 AI 提交归属**：AI、模型、Agent 或 Bot 不得出现在 Git commit 的 author、committer 或 co-author metadata 中；项目提交禁止出现任何 `Co-Authored-By` trailer。AI 参与只能在 PR、Issue、审查报告或任务总结中披露。
```

Preserve the existing `Governance-Exception` trailer rule and explain that it records human owner approval rather than authorship.

- [ ] **Step 2: Add the prohibition to both global rule documents**

Add this section to `global/AGENTS.md` and `global/ai-change-implementation-prompt.md`:

```markdown
## Git 提交作者归属

- 禁止 AI、模型、Agent 或 Bot 作为 Git commit 的 author 或 committer。
- 禁止 commit message 中出现 `Co-Authored-By`、`Co-Author` 或等价合作作者 trailer。
- AI 参与只能记录在 PR、Issue 或任务总结中。
- 历史提交不重写；本规则只阻止新提交。
```

- [ ] **Step 3: Correct onboarding and repository README guidance**

Remove the onboarding instruction that asks contributors to add `Co-Authored-By`. Replace it with:

```markdown
用了 AI 时，在 PR 的「AI 参与」节说明参与范围和人工复核范围；不得在 commit author、committer 或 trailer 中写入 AI/Bot 身份。
```

Document that `agent-governance` owns the policy source while project repositories carry the synchronized snapshot.

- [ ] **Step 4: Bump the governance version without discarding existing WIP**

The current working tree already changes `VERSION` from `1.4.0` to `1.5.0` for another approved governance change. Preserve that intent and advance the version monotonically to `1.6.0` for this additional policy change.

- [ ] **Step 5: Run source-policy checks**

Run:

```bash
rg -n -i '给 commit 带.*Co-Authored-By|AI.*Co-Authored-By|标 author.*Co-Authored-By' global team-contract.md onboarding.md README.md
bash scripts/check-version-bump.sh
git diff --check
```

Expected: the first command returns no contradictory positive instruction; the version check passes after the source files and `VERSION` are updated; `git diff --check` exits 0.

Do not stage or commit the pre-existing changes in `VERSION`, `global/AGENTS.md`, or `team-contract.md` separately from the user’s chosen integration flow.

### Task 2: Implement the portable attribution checker

**Files:**

- Create: `scripts/check-commit-attribution.sh`
- Create: `tests/check-commit-attribution.sh`

**Interfaces:**

- Consumes: `--message <commit-message-file>`, `--range <git-revision-range>`, and `--audit-history`.
- Produces: exit code 0 for allowed metadata, exit code 1 for violations, and concise violation diagnostics without rewriting files or Git history.

- [ ] **Step 1: Write the shell regression fixture**

Create a Bash test that creates a temporary Git repository and checks:

```bash
run_expect_success message-human.txt
run_expect_failure message-co-authored-by.txt
run_expect_failure message-co-authored-lowercase.txt
run_expect_failure author-claude
run_expect_failure committer-commandcode
run_expect_success message-governance-exception.txt
```

The fixture must use `trap` to remove only its own temporary directory and must not touch any project repository.

- [ ] **Step 2: Implement message and identity matching**

Implement `scripts/check-commit-attribution.sh` with these functions:

```bash
check_message_file() { ...; }
check_identity() { ...; }
check_current_identity() { ...; }
check_revision_range() { ...; }
audit_history() { ...; }
```

The message check rejects a line beginning with a case-insensitive co-author trailer. The identity check rejects case-insensitive known AI/Bot names and domains including `Claude`, `GPT`, `ChatGPT`, `OpenAI`, `Anthropic`, `Codex`, `Copilot`, `Cursor`, `Codeium`, `Gemini`, `CommandCode`, `Bot`, `Agent`, `anthropic.com`, `openai.com`, and `commandcode.ai`.

The script must allow ordinary human identities, ordinary business text containing `AI`, and `Governance-Exception`.

- [ ] **Step 3: Implement the three execution modes**

Use these exact command contracts:

```text
bash scripts/check-commit-attribution.sh --message .git/COMMIT_EDITMSG
bash scripts/check-commit-attribution.sh --range <base>..<head>
bash scripts/check-commit-attribution.sh --audit-history
```

`--message` checks the message file plus `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`; `--range` checks every commit returned by `git rev-list`; `--audit-history` reports all reachable historical violations without changing repository state.

- [ ] **Step 4: Run shell syntax and regression tests**

Run:

```bash
bash -n scripts/check-commit-attribution.sh tests/check-commit-attribution.sh
bash tests/check-commit-attribution.sh
```

Expected: syntax checks pass; human and governance-exception fixtures pass; all co-author and known AI/Bot identity fixtures fail as intended.

### Task 3: Add the portable project governance snapshot

**Files:**

- Create: `project/AI-GOVERNANCE.md`
- Create: `templates/project/AI-GOVERNANCE.md`
- Create: `templates/project/scripts/check-commit-attribution.sh`
- Create: `scripts/sync-project-governance.sh`
- Modify: `README.md`
- Modify: `onboarding.md`

**Interfaces:**

- Consumes: `global/AGENTS.md`, `global/ai-change-implementation-prompt.md`, and the approved attribution policy.
- Produces: a versioned project snapshot and a sync command that updates independent project repositories without moving project code into `agent-governance`.

- [ ] **Step 1: Define the generated snapshot boundary**

Write `project/AI-GOVERNANCE.md` as the project-portable subset. It must include the attribution prohibition, Truth Source, Spec-first workflow, data boundary, Git safety, verification, and document drift rules, but must not include project-specific Backend, Electron, Vue, iOS, Xcode, or MySQL instructions.

Add markers:

```markdown
<!-- BEGIN SHARED-AI-GOVERNANCE: 1.6.0 -->
...
<!-- END SHARED-AI-GOVERNANCE: 1.6.0 -->
```

- [ ] **Step 2: Add the project snapshot and script templates**

Make `templates/project/AI-GOVERNANCE.md` and `templates/project/scripts/check-commit-attribution.sh` the exact source templates for project repositories. Keep the checker dependency-free so an iOS repository can run it without npm.

- [ ] **Step 3: Implement scoped project synchronization**

Implement:

```bash
bash scripts/sync-project-governance.sh \
  --repo /path/to/project-a \
  --repo /path/to/project-b
```

The command must:

- refuse to overwrite a target file with uncommitted changes;
- copy only `AI-GOVERNANCE.md` and the checker template into each target repository;
- write the current baseline version;
- compare existing snapshots before writing;
- never add or move project source code;
- print the exact target files changed.

- [ ] **Step 4: Test synchronization in temporary repositories**

Run the sync script against two temporary Git repositories, verify the snapshot and script contents, then create an uncommitted target-file change and verify that synchronization refuses to overwrite it.

### Task 4: Integrate repository-local rules and hooks

**Files:**

- Create: `hengqin-backend/AI-GOVERNANCE.md`
- Create: `hengqin-backend/scripts/check-commit-attribution.sh`
- Create: `hengqin-backend/.githooks/commit-msg`
- Create: `hengqin-desktop/AI-GOVERNANCE.md`
- Create: `hengqin-desktop/scripts/check-commit-attribution.sh`
- Create: `hengqin-desktop/.githooks/commit-msg`
- Create: `hengqin-admin/AI-GOVERNANCE.md`
- Create: `hengqin-admin/scripts/check-commit-attribution.sh`
- Modify: `hengqin-backend/AGENTS.md`
- Modify: `hengqin-desktop/AGENTS.md`
- Modify: `hengqin-admin/AGENTS.md`
- Modify: `hengqin-admin/.husky/commit-msg`
- Modify: `hengqin-backend/.github/CODEOWNERS`
- Modify: `hengqin-desktop/.github/CODEOWNERS`
- Modify: `hengqin-admin/.github/CODEOWNERS`

**Interfaces:**

- Consumes: the project snapshot and checker from Task 3.
- Produces: standalone project repositories that expose the prohibition even without the parent directory or `~/.codex`.

- [ ] **Step 1: Add snapshots without touching project source code**

Copy the current project snapshot and checker into each project repository. Confirm that the files contain the same baseline version and hash. Do not copy the projects themselves into `agent-governance`.

- [ ] **Step 2: Make each AGENTS entry point self-contained**

Add to each project `AGENTS.md`:

```markdown
本仓库必须先读取 AI-GOVERNANCE.md。该文件携带公共 AI 工程基线；本 AGENTS.md 只追加本项目的技术、架构、测试和发布规则。

禁止 AI、模型、Agent 或 Bot 作为 commit author、committer 或 co-author；禁止任何 `Co-Authored-By` trailer。AI 参与只写 PR/Issue。
```

Remove any instruction that requires the parent repository or `~/.codex` in order to understand the common prohibition.

- [ ] **Step 3: Install Backend and Desktop tracked hooks**

Create `.githooks/commit-msg` in Backend and Desktop:

```bash
#!/usr/bin/env bash
set -euo pipefail
exec bash "$(git rev-parse --show-toplevel)/scripts/check-commit-attribution.sh" --message "$1"
```

Add a documented setup command that runs:

```bash
git config --local core.hooksPath .githooks
```

Do not use a hook to rewrite the message; it must fail and tell the maintainer to remove the forbidden attribution.

- [ ] **Step 4: Extend the existing Admin Husky hook**

Change `hengqin-admin/.husky/commit-msg` to run the attribution check before commitlint:

```bash
bash scripts/check-commit-attribution.sh --message "$1"
npx --no -- commitlint --edit "$1"
```

- [ ] **Step 5: Protect generated governance files**

Add `/AI-GOVERNANCE.md` and the checker path to each project CODEOWNERS while preserving all existing uncommitted CODEOWNERS changes. The rule must distinguish generated public governance files from project-local `AGENTS.md` edits.

### Task 5: Add PR and CI enforcement

**Files:**

- Create: `hengqin-backend/.github/pull_request_template.md`
- Create: `hengqin-admin/.github/pull_request_template.md`
- Modify: `hengqin-desktop/.github/pull_request_template.md`
- Create: `hengqin-backend/.github/workflows/commit-policy.yml`
- Create: `hengqin-desktop/.github/workflows/commit-policy.yml`
- Create: `hengqin-admin/.github/workflows/commit-policy.yml`

**Interfaces:**

- Consumes: `scripts/check-commit-attribution.sh` and GitHub PR/push event SHAs.
- Produces: a CI check that fails only for newly introduced AI/Bot author metadata or co-author trailers.

- [ ] **Step 1: Add the PR disclosure contract**

Add this section to all three templates:

```markdown
## AI 参与

- [ ] 未在任何 commit metadata 中添加 AI/Bot author、committer 或 co-author。
- [ ] 如使用 AI，已在本 PR 中说明参与范围和人工复核范围。
```

Remove any positive request to put a model name in a commit trailer.

- [ ] **Step 2: Add a commit-policy workflow per project**

Use `actions/checkout@v5` with `fetch-depth: 0`, then run the repository-local script. For pull requests, check `${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }}`. For pushes, check `${{ github.event.before }}..${{ github.sha }}`, and handle an all-zero `before` SHA by checking only the current commit.

The workflow must not scan or rewrite full history as a merge failure. It must not print full commit messages or credentials.

- [ ] **Step 3: Verify positive and negative CI ranges locally**

In a temporary repository, create:

```text
base commit with old Co-Authored-By trailer
new human commit without forbidden metadata
new commit with Co-Authored-By trailer
```

Run the checker over each corresponding range. Expected: the range containing only the human commit passes; the range containing the new forbidden commit fails; a range that excludes the old commit does not fail because of that old history.

### Task 6: Complete cross-repository verification and handoff

**Files:**

- Verify: all changed files in `agent-governance`, `hengqin-backend`, `hengqin-desktop`, and `hengqin-admin`.
- Modify only if needed: governance README/onboarding references found by the drift search.

**Interfaces:**

- Consumes: all outputs from Tasks 1–5.
- Produces: verified policy, synchronized project snapshots, working local hooks, CI wiring, and a precise residual-risk report.

- [ ] **Step 1: Search for contradictory instructions**

Run:

```bash
rg -n -i 'Co-Authored-By|Co-authored-by|Co-Author|Coauthor|给 commit 带|标 author|AI.*author|AI.*committer' \
  /Users/joseph/Documents/work/personal-project/ai-projects/agent-governance \
  /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-backend \
  /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-desktop \
  /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-admin
```

Classify remaining matches as policy documentation, historical plan text, test fixtures, or forbidden current instructions. Current policy documentation may mention the forbidden token in order to define it; current positive instructions may not remain.

- [ ] **Step 2: Run repository-level static checks**

Run each applicable command without masking its exit status:

```bash
cd /Users/joseph/Documents/work/personal-project/ai-projects/agent-governance && git diff --check && bash scripts/check-version-bump.sh && bash tests/check-commit-attribution.sh
cd /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-backend && bash scripts/check-doc-links.sh && bash -n scripts/check-commit-attribution.sh
cd /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-desktop && bash -n scripts/check-commit-attribution.sh
cd /Users/joseph/Documents/work/personal-project/ai-projects/e-commerce-toolkits/hengqin-admin && bash -n scripts/check-commit-attribution.sh
```

- [ ] **Step 3: Verify worktree boundaries**

Run `git status --short --branch` in all four repositories and compare with the pre-task status. Confirm that no existing source, migration, test, or WIP file was reset, staged, committed, or rewritten by this change.

- [ ] **Step 4: Complete Reconciliation**

Record:

```text
Policy source:      updated
Project snapshots:  synchronized
Local hooks:        configured or documented
CI checks:          wired for new commits
PR templates:       synchronized
Historical commits: unchanged
Known residuals:    branch protection may not be platform-enforced; old history remains for audit only
```

- [ ] **Step 5: Report execution evidence**

Final output must include Classification, Truth Source, changed scope, Spec/Design/Contract updates, exact commands/results, residual risks, and the fact that no `Co-Authored-By` trailer was added to any commit created during this task.
