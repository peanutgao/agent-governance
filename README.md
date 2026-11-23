# agent-governance — 个人多设备 AI 开发约束

个人跨设备共享的全局 AI 开发约束仓库。macOS、Linux 和 Windows 原生的新机入口见 [一键部署](onboarding.md#新设备一键部署)。已经拉取本仓的设备可执行 `bash scripts/install.sh`，安装全局 AI 约束和常用 Skills。

项目级约束、架构、Spec、Contract、测试和发布说明由各项目仓库自己维护。本仓库不收集项目代码，也不替项目维护项目级 AI 约束。

## 结构

```text
AGENTS.md                              # 软链 → global/AGENTS.md（本仓自身的工作区级入口）
global/
├── AGENTS.md                          # 个人全局通用约束（唯一正文）
├── ai-change-implementation-prompt.md # 复杂任务按需读取的详细流程
└── git-hooks/                         # 全局 git 钩子（commit-msg 归属门禁 + 转发层）
onboarding.md                          # 多设备初始化和更新
templates/project/AI-GOVERNANCE.md      # 项目仓库携带的公共治理快照模板
scripts/install.sh                     # 安装全局规则和清单中的 Skills
scripts/distribute.sh                  # 分发全局入口（--check / --rollback / --list-targets）
scripts/sync-project-governance.sh     # 从模板生成三仓 AI-GOVERNANCE.md（--check）
scripts/check-commit-attribution.sh    # commit 归属检查（--governance / --print-policy）
scripts/check-version-bump.sh          # 规则改动检查
tests/run-all.sh                       # 全部测试的唯一入口
VERSION                                # 基线版本号
```

根目录的 `AGENTS.md` 是指向 `global/AGENTS.md` 的软链，不是第二份内容。作用是让**治理仓自己**也落在同一套约束下：任何支持项目级 `AGENTS.md` 的工具（Codex、pi、opencode、DeepSeek Harness、commandcode、WorkBuddy）在本仓干活时都会读到它，不依赖本机是否跑过分发。

## 分发目标

`~/.codex/AGENTS.md` 是全局规则的真源副本。下表标为软链的入口在 macOS/Linux 指向真源，在 Windows 上由分发器写入普通副本。

| 工具 | 本机路径 | 方式 |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | 内容副本（真源） |
| Codex | `~/.codex/ai-change-implementation-prompt.md` | 内容副本 |
| Codex | `~/.codex/check-commit-attribution.sh` | 内容副本，可复制进项目仓库 |
| 所有工具 | `~/.codex/git-hooks/`（旧版 `commit-msg` 及兼容转发文件） | 内容副本 + 可执行位 |
| Claude Code | `~/.claude/CLAUDE.md` | 软链 |
| pi | `~/.pi/agent/AGENTS.md` | 软链 |
| opencode | `~/.config/opencode/AGENTS.md` | 软链 |
| DeepSeek Harness | `$DSH_HOME/AGENTS.md`（默认 `~/.dsh/AGENTS.md`） | 软链 |
| commandcode | `~/.commandcode/AGENTS.md` | 软链 |
| omp | `~/.omp/agent/AGENTS.md` | 软链 |
| WorkBuddy | `~/.workbuddy-ai/rules/agent-governance.md` | 生成文件（带 frontmatter） |
| OrbStack VM 共享入口 | `~/Documents/work/CLAUDE.md` | 内容副本（非软链：VM 内 Claude Code 等经挂载共享的 work 目录读取祖先 `CLAUDE.md`，挂载拓扑无关） |

WorkBuddy 需要单独处理：它的用户级规则是 `<configDir>/rules/*.md`，必须带 `alwaysApply` frontmatter 才会全量注入，且正文上限 40000 字符（超限会被静默丢弃，因此分发前先校验长度）。它的工作区级入口是项目根目录的 `AGENTS.md` / `CODEBUDDY.md` / `.codebuddy/CODEBUDDY.md` 以及 `.codebuddy/rules/*.md`。本仓不分发项目级文件，只在**自己**根目录放一个 `AGENTS.md` 软链（见上）。

`DSH_HOME` 与 `WORKBUDDY_CONFIG_DIR` 只在指向 `$HOME` 之下时才被采用，避免误写到真实用户目录；确需安装到外部目录时设 `AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS=1`。

> 本仓分发个人全局规则和全局 Skills。项目设置、项目 hook、权限、token 和个人 memory 由各项目或本机工具维护。
> `~/.claude/settings.json`、`settings.local.json`、`~/.workbuddy-ai/{SOUL,IDENTITY,USER,MEMORY}.md` 和其他本机配置由个人自行维护，分发脚本不碰。

## Git 归属的执行点

项目在自身 `commit-msg` 的最后一步接入归属检查器，由 CI 对新增提交再次校验。这样 Git 继续按原有配置选择项目钩子，项目可以在检查前完成提交消息的改写。

- 分发迁移旧版由治理仓直接写入的全局 `core.hooksPath`，保留其他 Git 配置。来自系统配置或包含文件的旧覆盖会报出，需在其来源处理。
- 已接入 `~/.codex/git-hooks/commit-msg` 的项目可以保留该入口。新接入建议直接调用下方的检查器命令。
- `--check` 校验受管文件、执行位和旧全局覆盖。项目的执行链与 CI 须分别验证。

治理仓在本地把 `core.hooksPath` 指向 `.githooks`，用 `--governance` 模式描述本政策。

## 修改全局约束

1. 修改 `global/`、分发脚本、检查脚本或测试。
2. **bump `VERSION`**（严格递增的 SemVer）。
3. 先跑相关回归。获得全量测试授权后，运行 `bash tests/run-all.sh`；CI 还会核对当前提交的版本与规则树。
4. 提交并推送；其他设备执行 `git pull` 和 `bash scripts/distribute.sh`。

## 分发到设备

```bash
bash scripts/distribute.sh
bash scripts/distribute.sh --check          # 比对当前工作树、执行位和旧全局覆盖
bash scripts/distribute.sh --list-targets   # 只看目标清单，不安装
```

分发门禁失败时中止，受管副本保持原状：

1. 规则路径无未提交改动；
2. `VERSION` 格式合法并递增，其提交包含规则修改，最终规则树与该提交一致；
3. 本地检查：脚本语法 + 非递归测试套件（`tests/distribute.sh` 自身不参与，避免递归）；
4. 配置了 origin 时，必须能 fetch 并找到跟踪分支或远端默认分支，且本地仓不落后该分支。

安装规则：

- 安装、回滚和校验均预检目标类型、父目录及重复或嵌套路径。受管普通文件拒绝软链，约定为软链的工具入口可以保留链接。若显式允许外部目标，仍须使用无跳转且父目录为普通目录的绝对路径。
- 安装前对全部受管路径 + `.gov-version` 做一次**整组快照**，存于 `~/.codex/.gov-backup/<时间戳>/`。
- 内容一致时跳过，不产生冗余快照；不一致时先快照当前状态再覆盖。
- 软链目标若原是普通文件，同样随整组快照保存后再替换为软链。

回滚到最近一次分发前的整组状态。若分发中断，确认操作已经退出后再处理遗留锁目录：

```bash
bash scripts/distribute.sh --rollback
```

## 全局 Skills

统一安装先分发规则，再同步 [Skills 清单](skills/manifest.json)。安装条件、同步目标、冲突接管和回退见 [全局 Skills 使用说明](skills/README.md)。如果规则已分发而 Skills 同步失败，解决同步错误后可单独重跑 `python3 scripts/skills.py sync`。

## 项目级 AI 约束

每个项目仓库维护自己的项目级 AI 约束，通常放在项目根目录的 `AGENTS.md` 或 `CLAUDE.md`，并与项目自己的 Spec、架构文档和测试说明一起演进。

项目级文件负责项目专属内容，例如技术栈、目录、构建命令、模块边界、业务规则和发布流程；不要把这些内容写进本仓的全局规则。

项目仓库的 `AI-GOVERNANCE.md` 是本仓 `templates/project/AI-GOVERNANCE.md` 的生成物，不是第二份可手改真源。公共规则合入治理仓并发布相应版本后，更新消费项目的快照。向 Git 项目写入时会检查已获取的 origin 默认分支和现有快照的 Git 状态。

```bash
# 1. 在治理仓发布已通过检查的新版本
# 2. 从模板重新生成三仓快照
bash scripts/sync-project-governance.sh
# 3. 只校验不写入
bash scripts/sync-project-governance.sh --check
```

`--root` 可指定 monorepo 根目录；默认是 `$HOME/Documents/work/personal-project/hengqin`。生成器不会触碰各仓 `AGENTS.md`、specs、业务代码或 Git 历史。

项目交付物和 Git/协作记录不得披露 AI 参与、模型、供应商、Agent、Bot、生成归属或类似自动化身份信息；历史提交不重写。治理仓规则源可以使用必要的治理术语来定义这条约束。

要让项目仓库获得同等的 commit 归属检查，把检查器复制进项目，接上 `commit-msg` hook 与 CI；本仓不替项目安装 hook：

```bash
cp ~/.codex/check-commit-attribution.sh <project>/scripts/
# 项目 commit-msg 的最后一步，在项目改写消息后执行
exec bash "$repo_root/scripts/check-commit-attribution.sh" --message "$1"
```

治理仓自身描述这条政策的提交用 `--governance` 模式（只查 trailer 与身份，跳过 message 披露短语）。

## 设备更新

新设备或已有设备都执行：

```bash
cd agent-governance
git pull --ff-only
bash scripts/install.sh
```

首次使用见 [`onboarding.md`](onboarding.md)。本仓不保存设计文档或历史资料；规则、脚本和检查的当前行为以代码、测试和提交历史为准。
