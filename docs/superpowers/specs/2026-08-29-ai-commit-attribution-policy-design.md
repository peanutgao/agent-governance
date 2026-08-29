# AI Commit Attribution Prohibition — Design

> status: proposed
> owner: Joseph Koh
> date: 2026-08-29
> classification: Requirement Change（治理规则变更）

## 1. Goal

在所有受团队治理的项目中，禁止 AI、模型、Agent 或 Bot 以 Git commit 的作者、提交者或合作作者身份出现。AI 可以参与代码、文档、测试和审查，但参与信息只能记录在 PR、Issue 或任务总结中，不得写入 commit metadata。

本规则必须同时适用于 `agent-governance`、Backend、Desktop、Admin、未来的 iOS 项目以及其他接入治理基线的项目；项目仓库必须能够在没有父目录和本机全局规则的情况下执行检查。

## 2. Current Problem

当前 `team-contract.md` 要求 AI 提交带 `Co-Authored-By: <AI 模型名>`，`onboarding.md` 也要求在 commit 中添加该 trailer。Backend、Desktop、Admin 和治理仓历史中已经存在这类记录。

历史提交不属于本次变更范围，不进行 rebase、filter-repo、force push 或其他历史重写。本规则只阻止新产生的违规提交，并允许对历史结果进行只读审计。

## 3. Approved Behavior

### 3.1 Forbidden commit metadata

以下内容不得出现在新 commit 中：

- 任意大小写形式的 `Co-Authored-By`、`Co-authored-by`、`Co-Author` 或 `Coauthor` trailer；本项目当前不区分人类和 AI，统一禁止 `Co-Authored-By` trailer。
- 已知 AI、模型或 Bot 名称出现在 Git author name、author email、committer name 或 committer email 中。
- 已知 AI/Bot 服务域名或账号标识出现在上述 author/committer 字段中。
- 通过脚本、环境变量或 `git -c` 参数将 AI/Bot 身份写入 commit author 或 committer。

已知身份匹配至少覆盖：`Claude`、`GPT`、`ChatGPT`、`OpenAI`、`Anthropic`、`Codex`、`Copilot`、`Cursor`、`Codeium`、`Gemini`、`CommandCode`、`Bot`、`Agent`，以及 `anthropic.com`、`openai.com`、`commandcode.ai` 等已知服务域名。匹配应大小写不敏感，并允许名称中存在空格、连字符或下划线。

### 3.2 Allowed metadata and disclosure

- 人类维护者使用自己的 Git author/committer 身份提交。
- AI 参与情况可以写入 PR 的「AI 参与」区、Issue、审查报告和 Execution Summary。
- `Governance-Exception: ...` 仍然允许使用，因为它是 owner 审批记录，不是作者归属声明。
- commit subject、commit body 中出现普通的 `AI` 业务术语不自动违规；检查重点是作者归属和合作作者 trailer。

### 3.3 Historical behavior

- 已存在的历史 commit 不修改、不重写、不强制迁移。
- CI 只检查当前 PR 或当前 push 新增的 commit 范围，不扫描整个历史作为合并失败条件。
- 提供只读历史审计模式，报告历史违规数量和 commit hash，但不改变仓库状态。

## 4. Enforcement Layers

规则使用“文字约束 + 本地 hook + CI”三层执行：

1. `agent-governance` 的规则源、团队契约和 onboarding 明确禁止该行为，并删除相反要求。
2. 每个项目仓库携带可独立使用的 commit attribution 检查脚本和本地 `commit-msg` hook。
3. 每个项目的 PR CI 检查相对于目标分支新增的 commit；检查失败时不得将该变更标记为通过。

本地 hook 是开发期快速反馈，CI 是仓库级合并检查。GitHub branch protection 是否真正开启必须单独记录，不能把 CI 配置文件描述为平台强制拦截。

## 5. Shared Script Contract

治理仓维护一份通用脚本模板，项目仓库携带同步后的副本。脚本不依赖 Node、npm、TypeScript、Xcode 或项目业务代码，以便 iOS 和非 JavaScript 项目使用。

脚本至少提供两个入口：

```text
check-commit-attribution.sh --message <commit-msg-file>
check-commit-attribution.sh --range <git-revision-range>
```

`--message` 用于 `commit-msg` hook，检查提交消息和当前 author/committer 身份；`--range` 用于 CI，检查指定范围内每个 commit 的消息、author 和 committer。

违规时：

- 返回非零退出码；
- 输出 commit hash、违规字段类别和修复提示；
- 不打印完整敏感凭据；
- 不自动修改 commit message、Git 配置或历史。

允许的修复提示是删除 AI trailer、恢复人类 author/committer 后重新创建尚未推送的 commit。对已经推送的历史，不提示使用强制推送重写，除非用户单独明确提出历史治理任务。

## 6. Project Integration

### `agent-governance`

修改：

- `global/AGENTS.md`；
- `global/ai-change-implementation-prompt.md`；
- `team-contract.md`；
- `onboarding.md`；
- `README.md`；
- 通用 commit attribution 检查脚本；
- 项目快照同步模板和脚本。

删除 `team-contract.md` 中“AI 改动必须添加 `Co-Authored-By`”的要求，改为 PR/Issue 内披露 AI 参与。

治理仓自身也必须执行相同的禁止规则；本次提交不能添加 AI co-author trailer。

### Backend / Desktop / Admin

每个项目仓库同步：

- `AI-GOVERNANCE.md` 或等价的公共规则快照；
- `AGENTS.md` 中的项目入口约束；
- `scripts/check-commit-attribution.sh`；
- 本地 `commit-msg` hook 接入；
- PR 模板中的 AI 参与说明；
- CI 的新增 commit 范围检查；
- CODEOWNERS 对公共治理快照和检查脚本的保护。

Admin 已有 Husky，直接在现有 `.husky/commit-msg` 中调用检查脚本，再运行 commitlint。Backend 和 Desktop 没有现成的项目级提交 hook，则使用项目内可追踪的 hook 入口，并在 onboarding 中完成启用；CI 检查不依赖维护者是否成功安装本地 hook。

### iOS and other projects

iOS 项目不依赖 npm。它只需要携带同一份 shell 检查脚本，并在 Xcode/CI 使用的 Git 工作流中执行：

- 提交前由 `commit-msg` hook 检查；
- PR CI 检查新增 commit 范围；
- AI 参与写 PR，不写 commit metadata。

iOS 的 Swift、Xcode、Keychain、LocalAuthentication、签名和 App Store 规则仍由 iOS 自己的 `AGENTS.md` 维护，不进入本通用规则。

## 7. PR Contract

PR 模板保留 AI 参与披露，但明确写成：

```markdown
## AI 参与

- [ ] 未在任何 commit metadata 中添加 AI/Bot author、committer 或 co-author。
- [ ] 如使用 AI，已在本 PR 中说明参与范围和人工复核范围。
```

不得要求或建议将模型名称写入 `Co-Authored-By`。如果团队未来需要记录人类共同作者，需要另行提出规则变更，不能通过本规则的例外隐式恢复该 trailer。

## 8. Non-goals

- 不判断代码是否由 AI 生成；本规则只判断 Git 作者归属 metadata。
- 不禁止人类使用 AI 辅助编码。
- 不强制所有 commit 使用同一个人类身份；项目维护者可以使用各自批准的 Git 身份。
- 不扫描并重写现有 Git 历史。
- 不依赖某一个 AI 产品、IDE、CLI 或模型名称作为唯一检测方式。
- 不通过修改远端分支保护或强制推送实现历史清理。

## 9. Acceptance Criteria

- `agent-governance` 的规则源不再要求 `Co-Authored-By`。
- 三个业务项目的公共规则快照不再要求 `Co-Authored-By`。
- 新 commit message 含任意大小写 `Co-Authored-By` 时，本地 hook 失败。
- author 或 committer 命中已知 AI/Bot 标识时，本地 hook 失败。
- 人类 author/committer、普通业务文本和 `Governance-Exception` 不被误判。
- CI 只检查 PR/push 新增 commit，新增违规 commit 失败，旧历史违规不阻断本次变更。
- AI 参与可以在 PR 中披露，但 PR 模板不再要求 commit co-author trailer。
- 现有历史 commit、分支、远端引用和用户未提交工作树不被重写或覆盖。
- 新增脚本能够在没有 Node/npm 的环境中运行，以支持 iOS 项目。

## 10. Verification Plan

至少执行以下负向和正向验证：

```text
1. 人类 author/committer + 普通 commit message       -> PASS
2. message 含 Co-Authored-By                        -> FAIL
3. message 含 Co-authored-by                        -> FAIL
4. author 为 Claude / GPT / Bot                     -> FAIL
5. committer email 为 anthropic.com/openai.com      -> FAIL
6. message 含 Governance-Exception                  -> PASS
7. 历史范围含旧违规，但新增范围无违规                -> PASS
8. 新增范围含违规 commit                            -> FAIL
```

验证还包括：

- 治理仓现有规则和 onboarding 旧表述搜索归零；
- 三个项目的 PR 模板和 AGENTS 旧表述搜索归零；
- hook 脚本 shellcheck/语法检查或项目已有等价检查；
- 各项目 CI 配置引用正确的新增 commit 范围；
- `git status` 确认用户既有 WIP 未被修改；
- 不运行历史重写、不 force push、不删除远端分支。

## 11. Reconciliation Boundary

本设计只改变 AI commit attribution 的治理规则，不改变：

- 项目业务 Spec；
- API / Event / Data Contract；
- 数据库模型；
- 用户可见产品行为；
- 项目技术架构；
- 已有历史 commit 内容。

完成实施后必须逐项核对：

```text
Policy source:      updated
Project snapshots:  synchronized
Local hook:         installed/configured
CI check:           wired
PR templates:       synchronized
History:            unchanged
```
