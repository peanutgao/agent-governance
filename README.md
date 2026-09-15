# agent-governance — 个人多设备 AI 开发约束

个人跨设备共享的全局 AI 开发约束仓库。每台设备拉取本仓后执行 `scripts/distribute.sh`，更新本机的全局 AI 约束。

项目级约束、架构、Spec、Contract、测试和发布说明由各项目仓库自己维护。本仓库不收集项目代码，也不替项目维护项目级 AI 约束。

## 结构

```text
AGENTS.md                              # 软链 → global/AGENTS.md（本仓自身的工作区级入口）
global/
├── AGENTS.md                          # 个人全局通用约束（唯一正文）
└── ai-change-implementation-prompt.md # 复杂任务按需读取的详细流程
onboarding.md                          # 多设备初始化和更新
scripts/distribute.sh                  # 分发（--rollback / --list-targets）
scripts/check-commit-attribution.sh    # commit 归属检查（--governance / --print-policy）
scripts/check-version-bump.sh          # 规则改动检查
tests/run-all.sh                       # 全部测试的唯一入口
VERSION                                # 基线版本号
```

根目录的 `AGENTS.md` 是指向 `global/AGENTS.md` 的软链，不是第二份内容。作用是让**治理仓自己**也落在同一套约束下：任何支持项目级 `AGENTS.md` 的工具（Codex、pi、opencode、DeepSeek Harness、commandcode、WorkBuddy）在本仓干活时都会读到它，不依赖本机是否跑过分发。

## 分发目标

`~/.codex/AGENTS.md` 是本机唯一真源副本，其余工具入口都是指向它的软链，避免多份内容各自漂移：

| 工具 | 本机路径 | 方式 |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | 内容副本（真源） |
| Codex | `~/.codex/ai-change-implementation-prompt.md` | 内容副本 |
| Codex | `~/.codex/check-commit-attribution.sh` | 内容副本，可复制进项目仓库 |
| Claude Code | `~/.claude/CLAUDE.md` | 软链 |
| pi | `~/.pi/agent/AGENTS.md` | 软链 |
| opencode | `~/.config/opencode/AGENTS.md` | 软链 |
| DeepSeek Harness | `$DSH_HOME/AGENTS.md`（默认 `~/.dsh/AGENTS.md`） | 软链 |
| commandcode | `~/.commandcode/AGENTS.md` | 软链 |
| WorkBuddy | `~/.workbuddy-ai/rules/agent-governance.md` | 生成文件（带 frontmatter） |

WorkBuddy 需要单独处理：它的用户级规则是 `<configDir>/rules/*.md`，必须带 `alwaysApply` frontmatter 才会全量注入，且正文上限 40000 字符（超限会被静默丢弃，因此分发前先校验长度）。它的工作区级入口是项目根目录的 `AGENTS.md` / `CODEBUDDY.md` / `.codebuddy/CODEBUDDY.md` 以及 `.codebuddy/rules/*.md`。本仓不分发项目级文件，只在**自己**根目录放一个 `AGENTS.md` 软链（见上）。

`DSH_HOME` 与 `WORKBUDDY_CONFIG_DIR` 只在指向 `$HOME` 之下时才被采用，避免误写到真实用户目录；确需安装到外部目录时设 `AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS=1`。

> 本仓只分发个人全局规则，不分发项目设置、项目 hook、权限、token 或个人 memory。
> `~/.claude/settings.json`、`settings.local.json`、`~/.workbuddy-ai/{SOUL,IDENTITY,USER,MEMORY}.md` 和其他本机配置由个人自行维护，分发脚本不碰。

## 修改全局约束

1. 修改 `global/`、分发脚本、检查脚本或测试。
2. **bump `VERSION`**（严格递增的 SemVer）。
3. 运行 `bash tests/run-all.sh`。
4. 提交并推送；其他设备执行 `git pull` 和 `bash scripts/distribute.sh`。

## 分发到设备

```bash
bash scripts/distribute.sh
bash scripts/distribute.sh --list-targets   # 只看目标清单，不安装
```

分发门禁，任一不过就中止，且不写任何文件：

1. 规则路径无未提交改动；
2. `VERSION` 格式合法、比上一版本递增，且其提交包含所有规则路径的最近一次提交；
3. 本地检查：脚本语法 + 非递归测试套件（`tests/distribute.sh` 自身不参与，避免递归）；
4. 本地仓不落后 origin。**origin 存在但 fetch 失败一律失败关闭**——绝不把本地旧内容装成「已是最新」。

安装规则：

- 受管 `copy` 路径若是软链接，直接拒绝安装（避免顺着链接写到链接目标）；先删链接或改回普通文件。
- 安装前对全部受管路径 + `.gov-version` 做一次**整组快照**，存于 `~/.codex/.gov-backup/<时间戳>/`。
- 内容一致时跳过，不产生冗余快照；不一致时先快照当前状态再覆盖。
- 软链目标若原是普通文件，同样随整组快照保存后再替换为软链。

回滚到最近一次分发前的整组状态（不是按文件各取一份备份）：

```bash
bash scripts/distribute.sh --rollback
```

## 项目级 AI 约束

每个项目仓库维护自己的项目级 AI 约束，通常放在项目根目录的 `AGENTS.md` 或 `CLAUDE.md`，并与项目自己的 Spec、架构文档和测试说明一起演进。

项目级文件负责项目专属内容，例如技术栈、目录、构建命令、模块边界、业务规则和发布流程；不要把这些内容写进本仓的全局规则。

本仓不复制或覆盖任何项目仓库文件。

项目交付物和 Git/协作记录不得披露 AI 参与、模型、供应商、Agent、Bot、生成归属或类似自动化身份信息；历史提交不重写。治理仓规则源可以使用必要的治理术语来定义这条约束。

要让项目仓库获得同等的 commit 归属检查，把检查器复制进项目，接上 `commit-msg` hook 与 CI；本仓不替项目安装 hook：

```bash
cp ~/.codex/check-commit-attribution.sh <project>/scripts/
bash ~/.codex/check-commit-attribution.sh --print-policy   # 查看当前拦截清单
```

治理仓自身描述这条政策的提交用 `--governance` 模式（只查 trailer 与身份，跳过 message 披露短语）。

## 设备更新

新设备或已有设备都执行：

```bash
cd agent-governance
git pull --ff-only
bash scripts/distribute.sh
```

首次使用见 [`onboarding.md`](onboarding.md)。本仓不保存设计文档或历史资料；规则、脚本和检查的当前行为以代码、测试和提交历史为准。
