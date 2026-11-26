# 多项目 AI Agent 上下文工程：详细实施方案

> 版本：1.1（已与 `agent-governance` 工具链对齐）｜日期：2026-11-24｜状态：通用实施蓝图（存量项目按 P0–P5 增量接入；新建项目可直接经本仓 [`scripts/gov`](../../scripts/gov)（`project init`）与 [`new-project-bootstrap`](../../skills/local/new-project-bootstrap/SKILL.md) Skill 落地）  
> 范围：前端、后端、移动端、单仓库、Monorepo、多仓库  
> 目标 Agent：Codex、Claude Code、OpenCode、Cursor、GitHub Copilot、Antigravity、WorkBuddy、ZCode  
> 设计目标：共享可信知识、按需检索、最小侵入、确定性防偏移门禁与可追溯验证；**不预设项目语言、目录或工具链**。

## 0. 执行摘要与决策

**推荐主方案（区分新建项目与存量老项目）：**

- **新建项目（单端 / 多端 Monorepo）**：优先按 [`new-project-bootstrap`](../../skills/local/new-project-bootstrap/SKILL.md) 6 阶段起盘，并用 `bash scripts/gov project init --target <project> [--apps ...]` 一键落盘精简 `AGENTS.md`（多端含路由表）、薄指针、`docs/{overview.md,contracts,specs,todos,adr,architecture/tech-stack.md}`、`.github/CODEOWNERS` 及 `check-spec-sync.py` + `check-commit-attribution.sh` 机械门禁。
- **存量老项目 / 跨多仓库改造**：按本方案第 1 节先做 **P0 只读盘点**，最小侵入接入 `AGENTS.md` 与文档导航，不强行重排老仓目录。

核心共同原则：

1. 每个仓库以根目录 `AGENTS.md` 作为**共享项目约束的唯一权威文本**；各 Agent 的兼容层（如 5 行 `CLAUDE.md` / `.github/copilot-instructions.md`）仅作指针，不维护重复正文。
2. 文档导航优先链接既有文档，不复制内容，不维护容易漂移的全量符号镜像。
3. 搜索遵循 `文件/文本 → 真实源码/契约 → 引用/类型 → Git → 跨仓库` 的逐步扩大顺序。首期**不部署 AOCI、向量库、全量自然语言索引或代码图谱**。
4. 区分「现状事实」与「业务正确性」：**当前代码怎么跑**看源码与真实测试，**业务应该怎么跑**看已批准的 Spec 与正式契约；两者冲突时报告并核查，不默认把现有代码当业务真相。
5. 跨仓库以**正式接口契约、版本、消费者清单和相关仓库实际代码**为依据；一个仓库无法证明其他仓库已兼容。
6. 代码规范与质量门禁优先使用**项目原生 Linter**（ESLint/Stylelint、Checkstyle、SwiftLint、Detekt 等）与既有 CI；没有确认真实命令前，不能写入假命令。
7. 分阶段上线，每阶段均设置证据、验收、回滚。**存量改造先选一个试点仓库与一组真实任务验收，再复制到其他仓库。**

### 0.1 必须区分三种内容

| 类别 | 示例 | 存放位置 | 准确性要求 |
|---|---|---|---|
| Agent 行为规则 | 修改前查调用方，不虚构 API | `AGENTS.md` | 团队审查；工具实际加载验证 |
| 已核实的项目知识 | 核心模块职责、状态不变量 | 既有 docs 或 `docs/ai/` | 引用源码、契约、提交或已确认设计 |
| 会话/任务记录 | 本次方案、未解决问题、运行结果 | Issue、PR、任务文档 | 标注状态；不自动升级为长期规则 |

**警告：** `AGENTS.md` 是给模型的指令，不是访问控制；Git/CI/沙箱/审批才是执行边界。项目文档也不是程序运行行为的替代证据。

---

## 1. 上线前盘点（P0，先执行）

### 1.1 盘点输入与产物

每个仓库先生成只读盘点记录，不立即创建文件。

| 盘点项 | 需要确认的事实 | 产物 |
|---|---|---|
| 仓库形态 | 单仓库、Monorepo、独立服务、多 Git 工作树 | 仓库登记表 |
| 已有 AI 规则 | `AGENTS.md`、`AGENTS.override.md`、`CLAUDE.md`、`CLAUDE.local.md`、`.claude/rules/`、OpenCode 配置 | 冲突与优先级清单 |
| 已有文档 | README、贡献指南、架构、ADR、API 规范 | 文档导航清单 |
| 语言/构建 | 包清单、锁文件、Xcode、Maven/Gradle、Go 模块等 | **已验证**的命令表 |
| 核心服务 | 入口、模块边界、接口消费者、数据存储 | 初步模块地图 |
| CI/测试 | 实际 job、测试环境与权限 | 验证能力矩阵 |
| 访问权限 | 哪些仓库/服务可被 Agent 访问 | 覆盖边界表 |
| 敏感信息 | 凭证、客户数据、机密接口、外部 MCP 权限 | 风险处置清单 |

### 1.2 安全的只读命令

以下命令在**选定仓库根目录**运行；它们只读取信息，不创建文件：

```bash
pwd
git rev-parse --show-toplevel
git status --short
find . -name AGENTS.md -o -name AGENTS.override.md -o -name CLAUDE.md -o -name CLAUDE.local.md
find . -type f \( -name package.json -o -name pnpm-lock.yaml -o -name go.mod -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts -o -name Package.swift -o -name '*.xcodeproj' \) -print
find . -maxdepth 3 -type f \( -name README.md -o -name CONTRIBUTING.md -o -name openapi.yaml -o -name openapi.json \) -print
```

注意：实际大仓库中应根据体量缩小 `find` 范围，并排除 `node_modules`、构建缓存等目录。上述 `find` 不对仓库内容作任何假设；它只列出找到的路径。**不要根据某个包清单推断测试命令，需打开真实配置核查。**

### 1.3 建议的登记表

| repo_id（团队分配） | Git URL | 维护人 | 类型 | 主语言 | 上游 | 下游 | 验证环境 | 状态 |
|---|---|---|---|---|---|---|---|---|
| 待填写 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 未盘点 |

**验收 G0：** 没有凭空填写的组件名、命令、分支、仓库路径；已有 AI 规则冲突已列出；未拥有访问权的仓库标注为不可验证。

---

## 2. 目标结构：新增最少文件，不重构现有代码

### 2.1 单仓库 / 服务仓库推荐布局

```text
<repo-root>/
├── AGENTS.md                    # 共享项目指令（唯一权威正文）
├── docs/                        # 若已有则复用
│   └── ai/                      # 仅在需要时创建
│       ├── INDEX.md             # 文档导航、状态和负责人
│       ├── architecture.md      # 经验证的系统地图（可选）
│       ├── contracts.md         # 接口契约入口和消费者（可选）
│       ├── workflows.md         # 构建/测试命令的已验证登记（可选）
│       └── decisions/           # ADR（可选）
└── <原有源码与配置，保持原样>
```

`docs/ai/` 是建议命名，不是任何 Agent 的内置特殊目录。已有 `docs/architecture/` 或 API 规范时，可以让 `INDEX.md` 指向它们，不应复制一份。

### 2.2 Monorepo

根目录一份共享 `AGENTS.md`；仅当子项目确有差异时在**实际存在的模块目录**增设局部 `AGENTS.md`。不预创建 `apps/`、`services/` 或其他假定目录。子项目文档从根索引链接到现有文档。工具对嵌套规则的发现时机不同，必须单独验收（见第 4 节）。

### 2.3 多仓库

每个仓库仍独立保存自己的 `AGENTS.md` 和知识链接。团队可以另建一个**可选**的工程治理仓库，保存跨仓库的真实登记清单、共享规范发布流程与审计结果，但**不把它当成各 Agent 会自动读取的全局配置**。跨仓库契约有明确 owner；部署在 API 提供方仓库或现有契约仓库均可，但必须确定唯一权威版本。

---

## 3. 直接可采用的项目级 AGENTS.md

> 此模板不含任何虚构的构建命令或路径。创建 `docs/ai/INDEX.md` 后才能保留对它的引用；如尚未创建，将对应句子删除。推荐项目规则以简洁、稳定为主。

```markdown
# Repository Agent Instructions

## Scope and source of truth
- Preserve the repository's existing architecture, terminology, and conventions.
- Never invent paths, commands, modules, APIs, dependencies, schemas, or credentials.
- Determine actual behavior from current source code, configuration, and executable checks.
- Use reviewed documents for architectural intent; report discrepancies instead of silently choosing a side.

## Before editing
- Confirm the requested change and acceptance criteria.
- Discover the smallest relevant scope through targeted search.
- Inspect implementations, call sites, public contracts, affected tests, and possible consumers.
- For cross-repository changes, identify accessible dependent repositories and explicitly list inaccessible ones.
- Read only task-relevant documentation from docs/ai/INDEX.md.

## Changes
- Prefer the smallest maintainable change that fully meets the requirement.
- Do not do unrelated refactoring or rename existing concepts without justification.
- Do not modify generated code by hand unless the repository explicitly requires it.
- Do not add production dependencies, alter public contracts, run destructive operations,
  or deploy without appropriate approval.

## Verification
- Determine build/test/lint commands from checked-in configurations and established CI.
- Run relevant checks available in the current environment.
- Inspect final diff for unrelated changes, security issues, and broken references.
- Mark checks accurately: PASS / FAIL / NOT RUN / BLOCKED.
- Never claim a check passed when it was not actually executed.

## Documentation
- Update verified architecture, business invariant, contract, or workflow docs when materially affected.
- Do not create per-file prose summaries or mirror implementation details without lasting value.
- Cite the source file, contract, decision, or commit supporting important new assertions.

## Final report
- Outcome and files changed
- Impacted contracts or consumers
- Checks executed with their results
- Unverified assumptions, blockers, and risks
```

**在创建规则时必须执行的一致性检查：** 确保 `docs/ai/INDEX.md` 存在；如已有其他规则，要人工合并而不是覆盖。生产仓库中建议对 `AGENTS.md` 设置 Code Owners 审核（如果平台支持）。

---

## 4. 主流 Agent 的真实适配与验证

> 已核对各工具当前规则加载机制。**共享同一份 `AGENTS.md` 正文 ≠ 所有工具的发现顺序与子目录扫描行为完全一致**。

| Agent | 已核实的加载行为 | 实施要点 | 不要做的事 |
|---|---|---|---|
| **Antigravity** | 原生自动读取工作区根 `AGENTS.md` | 根 `AGENTS.md` 保持精简高信号 | 不要把全局长规则软链复制到工作区造成重复注入 |
| **WorkBuddy** | 原生读取工作区根 `AGENTS.md`（及可选 `CODEBUDDY.md` / `.codebuddy/rules/`） | 统一使用根 `AGENTS.md`，不另抄第二份正文 | 同时维护内容分叉的 `CODEBUDDY.md` 与 `AGENTS.md` |
| **ZCode** | 原生读取工作区根 `AGENTS.md`，但**不自动扫描子目录**的嵌套 `AGENTS.md` | 多端 Monorepo 必须在根 `AGENTS.md` 写明**多端入口路由表**，引导按需读 `<app>/AGENTS.md` | 依赖子目录 `AGENTS.md` 自动生效而不写根路由表 |
| **Codex** | 支持 `~/.codex/AGENTS.md` 与项目目录链 `AGENTS.md`；`AGENTS.override.md` 优先级更高；有字节上限 | 检查已有 override/fallback 与字节预算；根目录及子端实测加载 | 只建根文件就假定无 override 干扰 |
| **Claude Code** | 新版（v2.1.277+）可直读 `AGENTS.md`，但工作目录或**祖先目录**存在 `CLAUDE.md` 时会优先读 `CLAUDE.md` | 团队版本不一或存在共享祖先 `CLAUDE.md`（如 `~/Documents/work/CLAUDE.md`）时，在项目根放 5 行极薄 `CLAUDE.md` 指针指向 `AGENTS.md` 与 `AI-GOVERNANCE.md` | 假设所有成员都已升级且无祖先 `CLAUDE.md` 遮蔽 |
| **Cursor** | 原生读取根与子目录 `AGENTS.md`（另有可选 `.cursor/rules/*.mdc`） | 通用规范放 `AGENTS.md`，不必把全部规则再编译一份 `.cursor/rules/` | 用多工具编译器制造 3 份重复副本 |
| **GitHub Copilot** | 新版支持 `AGENTS.md`，旧版仅认 `.github/copilot-instructions.md` | 根目录配 5 行 `.github/copilot-instructions.md` 薄指针指向 `AGENTS.md` | 在 `copilot-instructions.md` 里复制长正文 |
| **OpenCode** | 支持全局/项目/嵌套 `AGENTS.md` 与 `instructions` 配置，不自动消解冲突 | 统一走 `AGENTS.md`，不额外用 `instructions` 重复挂载 | 多处重复挂载导致上下文膨胀或规则冲突 |

### 4.1 Codex 落地

1. 检查实际 `CODEX_HOME`（如果未设置，通常为 `~/.codex`）。
2. 检查对应全局 `AGENTS.md`、`AGENTS.override.md`，以及项目根和子目录同名文件。
3. 项目根保留共享 `AGENTS.md`；暂不设置 `project_doc_fallback_filenames`、`project_doc_max_bytes`，除非经过需求验证。
4. 从仓库根启动新的 Codex 会话，要求它逐一列出**已加载的规则文件和路径**，并复述两条项目专有规则；在实际子目录再次验证。
5. 若存在 `AGENTS.override.md`，按官方优先级处理，避免误认为普通 `AGENTS.md` 生效。

### 4.2 Claude Code 落地

1. 检查安装版本是否支持原生 `AGENTS.md`。
2. 检查当前目录到父目录的 `CLAUDE.md`、`.claude/CLAUDE.md`、`CLAUDE.local.md`。
3. **首选：** 无冲突时仅使用 `AGENTS.md`。
4. **已有 `CLAUDE.md` 时：** 保留项目特有内容，在其中使用官方支持的 `@AGENTS.md` 导入；只保留一个权威规则正文。
5. 新建会话，用 `/context all` 核查实际加载的规则文件；再验证嵌套目录规则。如运行环境不允许读取，应记录为 BLOCKED。

可选的 Claude 兼容文件，只有在检查确有必要时才创建：

```markdown
@AGENTS.md

<!-- 此处仅保留真正的 Claude Code 专属配置或说明；不要复制通用规则 -->
```

**注意：** 文件导入会将内容带入上下文，不能视为“仅保留索引但不消耗 Token”。

### 4.3 OpenCode 落地

1. 确认项目根 `AGENTS.md` 正常加载。
2. 检查用户全局 `~/.config/opencode/AGENTS.md` 和项目配置中 `instructions` 的实际内容。
3. 若 `instructions` 已配置额外规则，检查是否与项目规则矛盾。
4. 从仓库根启动新会话，让 Agent 报告项目指令；读取子目录文件后，复核嵌套规则确实进入上下文。
5. 不为所有已有文档设置自动加载通配符，否则会抵消按需检索的设计。

### 4.4 统一加载验收用例

对每个 Agent、每个试点工作目录：

- **Case I-01**：根规则可加载；报告确切文件路径。
- **Case I-02**：专门设计的无副作用规则（例如“先列出待执行检查”）在只读演练中被遵循。
- **Case I-03**：已有 Claude/override/global 规则没有掩盖主规则。
- **Case I-04**：在子模块打开文件后，相关规则按该宿主的实际机制加载。
- **Case I-05**：不相关文档未被会话启动机制全文注入。

禁止仅凭 Agent 自述判断加载成功；尽可能对照宿主提供的上下文/日志/文件加载信息。

---

## 5. 知识库：如何从实际代码建立，而不是让 AI 脑补

### 5.1 先创建导航，不创建“空的完整知识库”

`docs/ai/INDEX.md` 初始模板：

```markdown
# Repository knowledge index

Status: INITIAL / REVIEWED / NEEDS_UPDATE
Owner: <待确认>
Reviewed against commit: <待确认>

## Current authoritative sources
| Topic | Source | Maintainer | Status |
|---|---|---|---|
| Architecture | <已存在的文档路径或待确认> | <待确认> | UNVERIFIED |
| API contracts | <已存在的规范文件或待确认> | <待确认> | UNVERIFIED |
| Build and tests | <已存在的 CI/脚本位置或待确认> | <待确认> | UNVERIFIED |

## Known gaps
- <尚无证据支持的模块/关系>

## Usage
Read only the sources relevant to the current task.
If a link or claim conflicts with current code, record the discrepancy.
```

文档中占位符必须保留 `UNVERIFIED`，直到能够提供证据；绝不能直接将其改成“已验证”。

### 5.2 四类知识与模板

**架构文档（可选）**：系统边界、入口、模块职责、调用依赖、主要运行路径、证据。  
**接口文档（可选）**：契约文件地址、版本与变更规则、提供方、已确认消费者；不复制完整 Schema。  
**业务不变量（可选）**：业务规则、触发条件、禁止状态、源码/产品依据、测试覆盖。  
**ADR（可选）**：决策上下文、选项、取舍、状态、批准人、日期、被取代的决策。

架构文档模板：

```markdown
# <系统或模块名称>
Status: DRAFT / REVIEWED / STALE
Owner: <负责人>
Verified revision: <Git commit>

## Boundary and responsibility
<只写已验证的职责>

## Entry points
- <实际存在的源文件/符号>

## Dependencies and consumers
- <有源码/契约证据的关系>

## Non-obvious constraints
- <历史决策、业务不变量；附证据>

## Verification and tests
- <真实路径及真实命令；未确认则写 UNVERIFIED>

## Open questions
- <无法确认的事项>
```

### 5.3 “先核查再写入”步骤

1. Agent 读取现有文档和实际源码，输出 **DRAFT**；每个重要声明关联源码路径、契约版本或 ADR。
2. Agent 使用引用/搜索检查最容易推翻结论的情况（例如多实现、运行时配置分支、历史接口）。
3. 维护人审查 DRAFT，区分事实、推断、未证实内容。
4. 通过审查才标记 **REVIEWED**，填写验证所针对的提交；后续源码更新不自动意味着文档失效，但需要按影响范围再核查。
5. 禁止把 Agent 的完整思考过程、一次性日志或每个函数注释自动汇入长期文档。

### 5.4 文档更新触发器

| 代码变更 | 需要核查的知识 | 默认动作 |
|---|---|---|
| 公共 API/Schema | 契约、消费者清单 | 必须评估 |
| 模块拆分与职责变化 | 架构、依赖图 | 必须评估 |
| 业务状态/规则变化 | 不变量与相关测试 | 必须评估 |
| 构建/测试步骤变化 | 工作流文档 | 必须评估 |
| 局部 UI 文案或简单局部修复 | 通常不涉及长期知识 | 不自动更新 |
| 单纯格式化 | 通常不涉及 | 不自动更新 |

**建议：** 每月做轻量巡检，但把它视为管理建议，而非默认安装的自动化任务。

---

## 6. 检索与上下文获取：明确的 Agent 执行算法

### 6.1 默认决策树

```text
接收需求
  ↓
确定验收条件与涉及仓库
  ↓
读取项目规则；INDEX 只用于导航
  ↓
rg/文件路径搜索最小范围
  ↓
读取当前源码、配置及已有测试
  ↓
查找调用方、实现、生成代码来源、API 契约
  ↓
必要时：LSP/语言工具 → Git 历史 → 跨仓库消费者
  ↓
输出证据、影响范围及待验证项
  ↓
实施最小修改 → 运行实际可用的检查
```

### 6.2 推荐搜索约定

- 优先搜索**文件名、已知符号、路由、接口路径、错误码、业务字段**。
- 先列命中路径，再查看必要代码范围；不要一次性读取整个大目录。
- `rg` 是文本检索；不能据此保证找全动态调用、反射、代码生成或运行时注入关系。
- 遇到精确符号依赖时采用当前语言的 LSP、IDE 或编译器查询能力；是否能在 Agent 中使用必须单独核实。
- 将 Git 历史作为辅助证据，不将某次提交说明当成现行实现的充分证明。

### 6.3 上下文停止条件

满足以下条件就停止扩张检索范围，进入修改：

1. 已找到对应实现及必需调用方；
2. 已确认涉及的公开契约和直接消费者（或明确无法访问）；
3. 已查到 relevant 的测试与可用验证方式；
4. 最主要的错误假设已通过反证检索排除；
5. 剩余未确认事项不影响开始安全、可回滚的修改。

如关键事实仍未确认，不应声明“完整理解系统”。

---

## 7. 跨仓库实施：仓库清单、契约、版本与变更序列

### 7.1 最小跨仓库元数据（团队自定义，非 Agent 内置配置）

只有出现稳定跨仓库开发需求时才新增，例如在可选的治理仓库维护 `repositories.yaml`：

```yaml
schema_version: 1
repositories: []
relationships: []
```

此空结构是**合法 YAML 初始骨架**，不制造不存在的前后端仓库；以下为字段模型，**不是已存在的数据**：

```yaml
schema_version: 1
repositories:
  - id: "<repo-id>"
    url: "<actual-git-url>"
    owner: "<team>"
    contracts:
      - "<existing-contract-location>"
relationships:
  - provider: "<repo-id>"
    consumer: "<repo-id>"
    contract: "<contract-id>"
    compatibility: "<documented-policy>"
```

使用时：先从**真实 Git URL、现有契约路径、团队确认的 owner** 填充；如果只获得一个仓库的访问权限，记录其他仓库为 `NOT_ACCESSIBLE`，不能声称跨仓库影响分析完成。

### 7.2 契约优先顺序

1. 现有正式机器可读契约（如 OpenAPI、Proto、GraphQL Schema、AsyncAPI 等）。
2. 由服务实际生成并经核对的契约（须标明生成源）。
3. 可追溯的正式 API 设计文档。
4. 若均不存在，先建立**契约缺口记录**，不要凭调用代码虚构一个“官方契约”。

### 7.3 跨仓库变更标准流程

```text
需求 → 找到契约 owner → 核实当前契约版本
    → 识别现有消费者 → 分类兼容性（新增/破坏性/数据迁移）
    → 形成服务端与客户端的发布顺序
    → 分仓库修改、测试、Review
    → 契约与集成验证 → 部署审批 → 观测与回滚
```

**兼容性基本原则：** 对公开接口的破坏性修改不能只依赖多个 PR 同时合并；必须结合实际部署顺序、客户端滞后版本、数据库迁移可逆性等条件设计迁移。对无法访问的消费者，明确列出风险而非假定兼容。

### 7.4 典型发布序列（条件性范式）

如接口需要由旧字段迁移至新字段，且系统确实支持双字段兼容，可考虑：

1. 提供方先兼容旧/新契约；
2. 更新各消费者；
3. 监测旧字段使用情况；
4. 在客户端最低版本与退出条件已验证后移除旧字段。

**这只是有条件的迁移范式**；不代表所有系统都支持双写、双读或灰度发布。

---

## 8. 开发、Review、验证流程的详细落地

### 8.1 任务分级

| 等级 | 判定特征 | 必须动作 |
|---|---|---|
| S：简单 | 局部、无公开契约变化、影响易确定 | 定位 → 修改 → 相关检查 |
| M：中等 | 跨模块、较多调用方、状态变化 | 简短影响分析 → 修改 → 测试 → Review |
| L：复杂 | 跨仓库、数据库迁移、公开 API、重要架构变化 | 先出方案与验证矩阵；审批 → 分步实施 → 契约/集成验证 → 回滚计划 |

### 8.2 S/M/L 统一输出合同

每次任务结束报告：

```text
Result: COMPLETE / PARTIAL / BLOCKED
Scope: <明确仓库/模块>
Files changed: <真实路径>
Contracts affected: <已核实的契约，或 NONE/UNKNOWN>
Validation:
  - <实际执行命令或步骤> : PASS / FAIL / NOT RUN / BLOCKED
Unverified: <无法核实的部分>
Risks and rollback: <风险与回滚依据>
Documentation: <已更新/无需更新/需补充审查>
```

### 8.3 真实命令登记（禁止猜测）

在 `docs/ai/workflows.md` 或既有开发文档维护：

| 检查名称 | 真实命令 | 执行目录 | 所需环境 | CI 证据 | 状态 |
|---|---|---|---|---|---|
| 编译 | 待盘点 | 待盘点 | 待盘点 | 待盘点 | UNVERIFIED |
| 单测 | 待盘点 | 待盘点 | 待盘点 | 待盘点 | UNVERIFIED |
| Lint/类型检查 | 待盘点 | 待盘点 | 待盘点 | 待盘点 | UNVERIFIED |
| 集成/契约 | 待盘点 | 待盘点 | 待盘点 | 待盘点 | UNVERIFIED |

Agent 只使用已验证条目。缺少运行环境时必须输出 BLOCKED，而不是改造项目来让其虚构命令成立。

### 8.4 Git/PR 阶段门禁

- **Preflight**：检查工作区是否已有用户未提交的修改；不得覆盖。
- **Before edit**：确认变更范围和契约影响。
- **After edit**：`git diff --check` 与 `git diff`，检查潜在敏感信息和无关变更。
- **Tests**：按上述真实命令登记运行，不用未确认的框架默认命令。
- **Documentation**：核查知识变更触发器。
- **Review**：对重要变更要求独立审查，核验反证与测试结果。
- **Merge**：沿用仓库已有分支保护、CI 和审批，不因 AI 开发而绕过。

### 8.5 CI 与确定性机械门禁落地

- **存量老仓库**：先盘点实际托管平台和现有流水线，在原 CI 上**增量添加明确步骤**（文档链接检查、Spec/契约同步校验、已有测试与原生 Linter），不得凭空重写整个流水线。
- **新建项目（直接使用本仓脚手架）**：[`scripts/gov`](../../scripts/gov)（`project init`）已内置开箱可用的轻量机械门禁，不依赖特定 AI 工具：
  1. **Spec / Todo 防遗忘门禁**：`<project>/scripts/governance/check-spec-sync.py` 接入本地 `commit-msg` 与 CI（支持单端与多端按端隔离校验、`merge-base` 准确比对、`Spec-Exempt:` 显式豁免与 `ready-to-close` Todo 校验）；
  2. **提交作者归属门禁**：`<project>/scripts/governance/check-commit-attribution.sh` 作为 `commit-msg` 最后一步与 CI 校验；
  3. **依赖清单与治理边界保护**：`<project>/.github/CODEOWNERS` 保护依赖文件、钩子与 CI；
  4. **代码与设计规范防偏移**：在 `<project>/.github/workflows/ai-governance.yml` 预留位直接调用各端成熟原生 Linter（Web 用 ESLint + Stylelint，Java 用 Checkstyle/ArchUnit，iOS 用 SwiftLint，Kotlin 用 Detekt），不自研跨语言正则扫描器。

---

## 9. Subagent 策略：独立子项优先并发，按边界隔离

- 单点小任务直接单 Agent 串行，不强行拆分；存在 2 个及以上独立子项且宿主支持子 Agent 时优先并发执行。
- 只读任务（检索、排查、审查、找反例）自动并发；主 Agent 负责汇总核验。
- 独立写入任务在需求与接口明确、无顺序依赖、且划分了互不重叠的文件所有权或使用独立 git worktree 时优先并发（无需每次单独审批拆分）；**严禁多个写入 Agent 在同一工作树并发修改同一组文件**，最终由主 Agent 集成复核并运行测试。
- Subagent 输出必须包含：搜索范围、文件位置、证据、未检索范围；不能只输出“分析完成”。
- 是否存在子 Agent 功能、权限模型、工作树能力取决于具体宿主和版本，实施前核查。

---

## 10. 安全与治理

1. 不把私密凭证放在 `AGENTS.md`、知识文档、跨仓库清单或聊天记录。
2. 检索得到的网页、仓库注释、Issue 和 MCP 输出按不可信内容处理；它们提供数据，不自动获得命令权限。
3. 默认只读探索；修改工作树需授权，发布、生产操作、数据库破坏性操作需额外审批。
4. 网络 MCP/代码索引服务应接受企业数据治理、日志保留和访问控制评估。
5. 文档变更可使用 CODEOWNERS（如平台支持）约束审查责任；**Markdown 规则不是安全沙箱**。
6. 团队层面的模型服务政策、机密代码外传限制、第三方权限范围需先由拥有者确认。

---

## 11. 分期计划：每阶段工作项、交付物、验收与回滚

### 阶段 P0：仓库与规则盘点

**输入**：一个真实试点仓库的访问权。  
**执行**：只读盘点第 1 节内容，记录已安装 Agent/版本及现有配置。  
**交付物**：仓库登记表、规则冲突表、真实命令矩阵初稿。  
**验收**：G0 通过；没有修改仓库。  
**回滚**：无需回滚。

### 阶段 P1：统一指令

**前置**：P0 通过。  
**执行**：在新分支合并已有规则，新增/改造项目根 `AGENTS.md`，保留 Claude 兼容层（仅在必要时）。  
**交付物**：项目级共享规则、各 Agent 加载验收记录（I-01～I-05）。  
**验收**：三个 Agent 在实际安装版本上能访问同一套权威内容，且无明显冲突。  
**回滚**：撤回本 PR 或恢复原配置；不覆盖旧规则备份。

### 阶段 P2：最小知识导航

**前置**：P1 通过。  
**执行**：仅创建 `docs/ai/INDEX.md`；引用现有架构、规范与契约；高价值缺口再新增独立文档。  
**交付物**：索引、一个核心模块事实表、证据引用。  
**验收**：链接真实可访问，文档事实可追溯，未确认项未标记 REVIEWED。  
**回滚**：删除新增知识文件或回退提交，原仓库代码不受影响。

### 阶段 P3：质量与变更闭环

**前置**：P2 通过；已拿到真实测试/CI 信息。  
**执行**：登记命令，落实 S/M/L 分级、PR 验证和文档同步检查。  
**交付物**：验证矩阵、Review 模板（可复用既有模板）、3 个已记录试点任务。  
**验收**：每个任务有准确 PASS/FAIL/BLOCKED，CI 未被绕过。  
**回滚**：撤回新增的非必要 CI 步骤，不改动既有测试体系。

### 阶段 P4：跨仓库试点（满足条件才启动）

**触发条件**：确有跨仓库调用，且能够访问相关代码/契约。  
**执行**：明确契约 owner，建立最小仓库关联清单，选择一次真实跨仓库变更验证。  
**交付物**：契约引用、提供方/消费者影响列表、兼容性及发布顺序、测试记录。  
**验收**：每个已声明影响关系都有证据；不可访问仓库显式列出。  
**回滚**：独立回退治理清单变更；代码按各仓库原有发布/回滚流程处理。

### 阶段 P5：高级检索是否引入的决策

**触发条件**：P1～P4 数据表明定位效率不足，且现有文本/LSP/Git 不能合理解决。  
**评估对象**：Sourcegraph、CodeGraph、AOCI-CODE、仓库语义检索、自定义 MCP。  
**验收**：相同任务、相近环境的对照试验，质量不下降且净收益足以覆盖索引和维护成本。  
**不通过时**：保持轻量方案，不因技术趋势增加复杂依赖。

### 里程碑清单

| 阶段 | 明确产物 | 是否需要真实仓库 | 完成条件 |
|---|---|---|---|
| P0 | 盘点结果 | 是 | 配置/命令/访问权已确认 |
| P1 | 统一规则 | 是 | 各 Agent 加载验证 |
| P2 | 知识入口与核心事实 | 是 | 路径与语义有证据 |
| P3 | 验证/Review 工作流 | 是 | 真实任务与 CI 记录 |
| P4 | 跨仓库依赖与契约 | 是，且多个仓库 | 消费者影响验证 |
| P5 | 高级工具选型报告 | 需要试点数据 | 明确采纳或不采纳 |

---

## 12. 成本与效果：避免凭主观印象选择工具

### 12.1 对照组

- **Baseline**：同一 Agent、同一代码版本、无新增项目知识（保留安全约束）。
- **Treatment**：使用共享 `AGENTS.md` + 知识索引 + 指定工作流。
- 后续可独立测量增加 LSP/语义检索前后的差异，不能把所有改动一次性混成一组。

### 12.2 建议任务集

至少选取不同类型的真实任务：单点 Bug、跨模块功能、历史回归、公开 API 变更，以及在具备条件时的跨仓库契约变更。每组记录输入、仓库提交、模型与宿主版本、权限、测试环境、任务成功率、人工修复次数、输入/输出 Token、耗时和文档维护成本。

### 12.3 判定准则

**硬约束**：功能/安全/兼容性质量不得下降，未验证结果不得被标记成功。  
**收益指标**：定位时间、重复检索次数、整体任务成本、后续会话复用率。  
**成本指标**：初始建档与审核成本、文档更新 PR 数量、规则冲突、误导性文档造成的返工。  
**结论格式**：采用/暂缓/拒绝，并列出依据、适用边界和剩余不确定性。**不要预先承诺 Token 降低百分比。**

---

## 13. 常见失败条件与反证检查

| 失败条件 | 表现 | 预防或补救 |
|---|---|---|
| 规则文件优先级冲突 | Agent 没按共享规则执行 | 按宿主核查加载源；删除重复正文 |
| 文档全文自动加载 | 上下文比原来更大 | 根规则只指向 INDEX；禁止全量 import |
| 语义总结过期 | Agent 修改错误模块 | 必查源码、配置、消费者；文档标 STALE |
| 仓库清单不完整 | 漏掉移动端消费者 | 以契约/流量/仓库实际代码补证；标出未知方 |
| “通用脚本”假定工具存在 | 无法运行或误改仓库 | 仅登记已确认命令，不统一重写技术栈 |
| LSP 不可用 | Agent 无法找到精确引用 | 回退文本搜索+IDE；不要声称已覆盖所有引用 |
| 多 Agent 并发写同文件 | 冲突和丢改动 | 只读并行；写入独立工作树，集中合并 |
| CI 未跑仍声称成功 | 质量信号虚假 | 验证结果必须包含命令和 PASS/FAIL/BLOCKED |
| 代码/文档无 owner | 资料长期失效 | 分配维护人和审核责任 |
| 默认访问多个仓库 | 查询失败、越权 | 先校验可访问仓库清单与权限边界 |

---

## 14. 可直接复用的 Agent 任务提示

### 14.1 第一次盘点（只读）

```text
请对当前 Git 仓库执行只读盘点，不修改任何文件。
1. 确认仓库根目录、状态、主要语言和真实构建定义。
2. 列出现有 AGENTS.md、AGENTS.override.md、CLAUDE.md、相关配置及可能冲突。
3. 找出现有文档、正式 API 契约、CI 和测试入口。
4. 输出“已核实事实 / 合理推断 / 尚未确认”三个部分，并引用具体文件路径。
5. 不虚构命令或模块，不主动部署任何索引和 MCP。
```

### 14.2 生成最小知识入口

```text
基于刚刚核实的仓库事实，在独立分支建立最小 AI 上下文知识入口。
优先链接现有文档，只为缺失且高价值的知识新增文件。
重要架构结论必须附真实源码或契约依据；未验证内容明确标记。
保留现有 AGENTS/CLAUDE 规则，不覆盖和复制。
修改后输出 diff、链接检查结果和需要人工审核的内容。
```

### 14.3 代码变更前的影响评估

```text
请先不要修改代码。根据需求按需检索相关源码、调用方、接口契约和测试。
给出最小改动方案、受影响仓库/模块、潜在兼容风险、验证命令及证据。
如果无法访问其他仓库或缺少运行环境，请直接标记未验证范围。
仅在影响边界足够清楚后实施修改。
```

### 14.4 文档变更核查

```text
请比较本次 Git diff 与当前知识索引，只报告受影响的架构、契约、业务约束或开发流程文档。
不要为局部代码修改自动生成逐函数摘要。
每项文档修改都必须有当前源码、正式契约或获批 ADR 的证据。
```

---

## 15. 本文档哪些部分已核实、哪些必须落到真实环境

**已核实（官方文档）：**

- Codex 支持目录链 `AGENTS.md`，并存在 override 和大小限制。
- Claude Code v2.1.277+ 支持原生读取 `AGENTS.md`，但存在 `CLAUDE.md`、本地文件及插件设置相关的条件。
- OpenCode 支持 `AGENTS.md`、嵌套规则和可选 `instructions`，并不自动解决规则冲突。
- OpenAI 公开的 Harness Engineering 实践采用简短指令入口与结构化仓库知识导航。

**需要真实项目才能核实：**

- 你的仓库、目录、实际 Agent 版本、全局规则与项目覆盖规则。
- 构建、测试、CI、代码生成、部署和权限。
- 前后端/移动端之间真实契约、消费者和发布兼容策略。
- 索引/RAG/LSP/MCP 在你的具体模型和运行环境中的净收益。

**因此本方案是完整实施流程与模板，不是已在你的所有项目部署和验证过的“最终配置”。**

---

## 16. 官方资料（核对日期：2026-11-22）

1. OpenAI — Harness Engineering：<https://openai.com/index/harness-engineering/>
2. OpenAI — Codex AGENTS.md 指南：<https://developers.openai.com/codex/guides/agents-md>
3. Anthropic — Claude Code Memory / AGENTS.md：<https://code.claude.com/docs/en/memory>
4. OpenCode — Instructions：<https://opencode.ai/docs/instructions>
5. AGENTS.md 通用约定：<https://agents.md/>

> 参考来源用于解释官方功能与设计依据。文中流程、文件命名、阶段门禁、模板与评估指标是本方案提出的工程建议，**不是上述产品的强制官方配置**。
