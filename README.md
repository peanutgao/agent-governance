# agent-governance — 个人多设备 AI 开发约束

个人跨设备共享的全局 AI 开发约束仓库。macOS、Linux 和 Windows 原生的新机入口见 [一键部署](onboarding.md#新设备一键部署)。已经拉取本仓的设备可执行 `bash scripts/install.sh`，安装全局 AI 约束和常用 Skills。

项目级约束、架构、Spec、Contract、测试和发布说明由各项目仓库自己维护。本仓库不收集项目代码，也不替项目维护项目级 AI 约束。

## 结构

```text
AGENTS.md                              # 指针文件 → global/AGENTS.md（本仓自身的工作区级入口）
global/
├── AGENTS.md                          # 个人全局通用约束（唯一正文）
└── git-hooks/                         # 全局 git 钩子（commit-msg 归属门禁 + 转发层）
onboarding.md                          # 多设备初始化和更新
templates/project/AI-GOVERNANCE.md     # 项目仓库携带的公共治理快照模板
templates/project/kit/                 # 语言无关的轻量自包含项目治理脚手架模板
skills/                                # 全局 Skills 清单与仓内本机版本（含 ai-change-flow、new-project-bootstrap）
scripts/install.sh                     # 安装全局规则和清单中的 Skills
scripts/distribute.sh                  # 分发全局入口（--check / --rollback / --list-targets）
scripts/sync-project-governance.sh     # 从模板生成/更新项目仓 AI-GOVERNANCE.md（--check / --root / --repos）
scripts/init-project-governance.sh     # 轻量初始化新项目的自包含治理骨架（--target / --apps / --add-app / --dry-run）
scripts/check-commit-attribution.sh    # commit 归属检查（--governance / --print-policy）
scripts/check-rule-paths.sh            # 规则内路径可达性检查（默认查仓内引用，--installed 查本机入口）
scripts/check-version-bump.sh          # 规则改动版本递增检查
tests/run-all.sh                       # 全部测试的唯一入口
VERSION                                # 基线版本号
```

根目录的 `AGENTS.md` 是指向 `global/AGENTS.md` 的**轻量指针文件**（不是软链，也不是第二份正文）。改为指针可避免支持项目级 `AGENTS.md` 的工具把同一份 20KB 规则按工作区路径和用户级路径重复注入多遍；任何工具在本仓干活时都能通过指针找到真源与校验命令，`tests/distribute.sh` 会守住这个不变量。

## 分发目标

`~/.codex/AGENTS.md` 是全局规则的真源副本。下表标为软链的入口在 macOS/Linux 指向真源，在 Windows 上由分发器写入普通副本。

| 工具 | 本机路径 | 方式 |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | 内容副本（真源） |
| Codex | `~/.codex/check-commit-attribution.sh` | 内容副本，可复制进项目仓库 |
| 所有工具 | `~/.codex/git-hooks/`（旧版 `commit-msg` 及兼容转发文件） | 内容副本 + 可执行位 |
| Claude Code | `~/.claude/CLAUDE.md` | 软链 |
| pi | `~/.pi/agent/AGENTS.md` | 软链 |
| opencode | `~/.config/opencode/AGENTS.md` | 软链 |
| DeepSeek Harness | `$DSH_HOME/AGENTS.md`（默认 `~/.dsh/AGENTS.md`） | 软链 |
| commandcode | `~/.commandcode/AGENTS.md` | 软链 |
| omp | `~/.omp/agent/AGENTS.md` | 软链 |
| Zed | `~/.config/zed/AGENTS.md` | 软链 |
| Amp | `~/.config/amp/AGENTS.md` | 软链 |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` | 内容副本（只认这个文件名） |
| WorkBuddy | `~/.workbuddy-ai/rules/agent-governance.md` | 生成文件（带 frontmatter） |
| OrbStack VM 共享入口 | `~/Documents/work/CLAUDE.md` | 内容副本（非软链：VM 内 Claude Code 等经挂载共享的 work 目录读取祖先 `CLAUDE.md`，挂载拓扑无关） |

WorkBuddy 需要单独处理：它的用户级规则是 `<configDir>/rules/*.md`，必须带 `alwaysApply` frontmatter 才会全量注入，且正文上限 40000 字符（超限会被静默丢弃，因此分发前先校验长度）。它的工作区级入口是项目根目录的 `AGENTS.md` / `CODEBUDDY.md` / `.codebuddy/CODEBUDDY.md` 以及 `.codebuddy/rules/*.md`。本仓不分发项目级文件，只在**自己**根目录放一个轻量 `AGENTS.md` 指针文件（见上）。

`CLAUDE_CONFIG_DIR`、`PI_CODING_AGENT_DIR`、`XDG_CONFIG_HOME`、`OPENCODE_CONFIG_DIR`、`DSH_HOME` 与 `WORKBUDDY_CONFIG_DIR` 只在指向 `$HOME` 之下时才被采用，避免误写到真实用户目录之外；确需安装到外部目录时设 `AGENT_GOVERNANCE_ALLOW_EXTERNAL_TARGETS=1`。

> 本仓分发个人全局规则和全局 Skills。项目设置、项目 hook、权限、token 和个人 memory 由各项目或本机工具维护。
> `~/.claude/settings.json`、`settings.local.json`、`~/.workbuddy-ai/` 下的 SOUL、IDENTITY、USER、MEMORY 个人文件 和其他本机配置由个人自行维护，分发脚本不碰。

### 能力边界：这是上下文约束，不是强制门禁

本仓分发的全部是 Markdown 规则和 git 钩子。Markdown 进入模型上下文后**不构成无条件阻断**——Claude Code 官方明确说 CLAUDE.md 是上下文而非强制配置，要阻断某个动作得用 `PreToolUse` hook 或 `permissions.deny`。

本仓不接管 `settings.json`，理由是可验证的：

- 回滚按受管路径做**整文件**快照恢复，部分受管会覆盖你分发后手改的内容；
- JSON 里追加带标记的 `permissions` 块会产生重复键，解析器静默保留后者，你原有的 `permissions` 规则会被无声丢弃；
- 本机 `settings.json` 的 `env` 含凭据键，纳入快照意味着把凭据复制进备份目录。

需要硬门禁时请自行在工具配置里接入（Claude Code 的 `PreToolUse` hook、Codex 的 `approval_policy` + `sandbox_mode`、Copilot 的 content exclusion）。本仓提供的是流程与边界约定，不是沙箱。

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
- 安装前对全部受管路径 + `.gov-version` 做一次**整组快照**，存于 `~/.codex/.gov-backup/` 下的时间戳目录，默认保留最近 10 份（可用 `AGENT_GOVERNANCE_BACKUP_KEEP` 调整）。
- 内容一致且无待清理退役路径时跳过，不产生冗余快照；不一致时先快照当前状态再覆盖。
- 软链目标若原是普通文件，同样随整组快照保存后再替换为软链。
- `--check` 同步校验受管副本、钩子执行位、旧全局覆盖与退役路径残留。

回滚到最近一次分发前的整组状态。若分发中断，确认操作已经退出后再处理遗留锁目录：

```bash
bash scripts/distribute.sh --rollback
```

## 全局 Skills

统一安装先分发规则，再同步 [Skills 清单](skills/manifest.json)。安装条件、同步目标、冲突接管和回退见 [全局 Skills 使用说明](skills/README.md)。如果规则已分发而 Skills 同步失败，解决同步错误后可单独重跑 `python3 scripts/skills.py sync`。

### 详细流程作为 Skill，不再单独分发文件

L2 变更、非显然 Bug、需求变更门禁和独立方案复核的完整流程是 `ai-change-flow` Skill，正文在其 `references/full-flow.md`。它随 Skills 清单同步到各工具的 skills 目录，按渐进加载生效：只有任务命中触发条件时才读入，不占用每个会话的常驻上下文。

过去的做法是把 1449 行的流程文件分发到 `~/.codex/`，再在 `AGENTS.md` 里写一句「按需读取」。那依赖模型自觉，既不是机制，也让规则体积失控。改成 Skill 后：

| 情形 | 加载 |
|---|---|
| L2 变更、根因不明的 Bug、需求变更 | `ai-change-flow` Skill |
| 不清楚应该实现什么 | `grilling` Skill |
| L0 / 普通 L1 | 只读 `global/AGENTS.md` |

### 规则长度与路径门禁

工具对用户级规则文件普遍有正文上限，且超限时**静默丢弃**而不是报错——规则看起来装好了、实际不生效。分发前会拦住超限内容（单文件 ≤ 24000 字节且 WorkBuddy 规则 ≤ 40000 字符，见 `scripts/distribute.sh --list-targets` 末尾输出的当前上限）。`scripts/check-rule-paths.sh` 默认静态校验规则和文档内引用的仓内路径（CI 可直接运行），`--installed` 模式另行检查本机已分发入口是否可达。

## 项目级 AI 约束

每个项目仓库维护自己的项目级 AI 约束，通常放在项目根目录的 `AGENTS.md` 或 `CLAUDE.md`，并与项目自己的 Spec、架构文档和测试说明一起演进。

项目级文件负责项目专属内容，例如技术栈、目录、构建命令、模块边界、业务规则和发布流程；不要把这些内容写进本仓的全局规则。

### 轻量初始化团队级自包含项目治理骨架（语言无关）

新项目需要让不同成员、不同 AI 工具（Antigravity / WorkBuddy / ZCode / Codex / Cursor / Claude Code / Copilot）在**不安装本仓**的前提下遵守同一套规范与 Spec 防遗忘门禁时，运行轻量建项脚手架（不覆盖已有文件）：

```bash
# 1. 初始化单端新项目（支持 --dry-run 预览）
bash scripts/init-project-governance.sh --target /path/to/new-project --project-name MyProject

# 1b. 初始化多端 Monorepo（顶层共有 docs/overview.md + docs/contracts/ + docs/specs/，各端独立 AGENTS.md / tech-stack / Spec 索引，根 AGENTS.md 自动带多端路由表）
bash scripts/init-project-governance.sh --target /path/to/test-project --project-name test-project \
  --apps test-project-backend,test-project-client-ios,test-project-admin,test-project-frontend
# 后续给已初始化的多端项目新增子端：
bash scripts/init-project-governance.sh --target /path/to/test-project --add-app test-project-client-android

# 2. 团队成员克隆业务仓后启用本地 commit-msg 钩子（Spec 同步 + Commit 归属）
bash <project>/scripts/governance/install-hooks.sh
```

- **高信号极简落盘**：只放全工具通用的 `<project>/AGENTS.md`（+ `<project>/CLAUDE.md` 与 `<project>/.github/copilot-instructions.md` 薄指针）、`<project>/AI-GOVERNANCE.md`、`<project>/docs/` 精简骨架（`overview.md`、`contracts/`、`architecture/tech-stack.md`、`specs/`、`todos/`、`adr/`）、`<project>/.github/CODEOWNERS`（保护治理门禁与依赖清单）、`<project>/.github/PULL_REQUEST_TEMPLATE.md`、`<project>/.github/workflows/ai-governance.yml`，以及仅 2 个轻量门禁脚本（`check-spec-sync.py` 与本仓同源的 `check-commit-attribution.sh`）。
- **零自研语言解析器**：Design Token 防硬编码、组件二次封装防绕过由各端成熟原生 Linter（ESLint / Stylelint / Checkstyle / SwiftLint / Detekt 等）承接；`<project>/AI-GOVERNANCE.md` 后续升级统一继续使用下方的 `scripts/sync-project-governance.sh`。从零新建项目可配合本地 Skill `new-project-bootstrap`（位于 `skills/local/new-project-bootstrap/SKILL.md`）按 6 阶段门禁起盘。

### 同步单文件公共治理快照（既有项目向后兼容）

项目仓库的 `AI-GOVERNANCE.md` 是本仓 `templates/project/AI-GOVERNANCE.md` 的生成物，不是第二份可手改真源。公共规则合入治理仓并发布相应版本后，更新消费项目的快照。向 Git 项目写入时会检查远端默认分支新鲜度与现有快照的 Git 状态。

```bash
# 1. 在治理仓发布已通过检查的新版本
# 2. 从模板重新生成目标项目快照（可用 --root 或环境变量 PROJECT_GOVERNANCE_ROOT）
bash scripts/sync-project-governance.sh --root /path/to/workspace
# 3. 只校验不写入
bash scripts/sync-project-governance.sh --check --root /path/to/workspace
```

通过 `--root` 或 `PROJECT_GOVERNANCE_ROOT` 指定目标项目根目录；未传 `--repos`（或 `PROJECT_GOVERNANCE_REPOS`）时，自动发现根目录下含 `.git`、`AI-GOVERNANCE.md`、`AGENTS.md` 或 `CLAUDE.md` 的子目录。生成器不会触碰各仓 `AGENTS.md`、specs、业务代码或 Git 历史。

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
