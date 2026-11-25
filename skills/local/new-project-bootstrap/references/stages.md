# 新建项目 6 阶段详细门禁与基建分流清单

按当前所处阶段查阅对应章节，避免整篇塞入无关上下文。

## Stage 0：项目画像、目标与 Non-Goals

进入 Stage 1 前，通过 `grilling` 确认以下四项（一次一问，不猜测）：

1. **核心目标与 Non-Goals**：首期最小闭环要解决什么问题，明确列出至少 2–3 条首期**不做**的范围（防止需求膨胀和 AI 顺手造大框架）。
2. **项目运行形态**：
   - 带 UI 客户端（Web / iOS / Android / 桌面端）—— 必走 Design Token + 基础组件二次封装；
   - 服务端 / CLI / SDK（Java / Kotlin / Go / Python / Rust 等）—— 必走分层边界 + 核心三方库薄封装；
   - 全栈 / 多端 Monorepo —— 明确子端目录划分与跨端共享契约位置。
3. **目录布局确认**：
   - **单端项目**：文档收口在 `<project>/docs/`（`overview.md`、`contracts/`、`architecture/tech-stack.md`、`specs/`、`todos/`、`adr/`），源码保留语言原生根布局（如 `src/`、`app/`、`Sources/`）；
   - **多端 Monorepo**（如 `<project>` 下含 `<project>-backend`、`<project>-client-ios`、`<project>-admin`、`<project>-frontend`）：
     - **顶层 `docs/` 放共有真源**：项目整体情况与术语（`docs/overview.md`）、跨端共享 API/Event/Schema/Token 契约（`docs/contracts/`）、跨端业务 Spec（`docs/specs/`）、总计划（`docs/todos/`）、全局 ADR（`docs/adr/`）；
     - **各端放端内代码与极简入口**：每个端有 `<app>/AGENTS.md`、`<app>/CLAUDE.md`、`<app>/docs/architecture/tech-stack.md` 与 `<app>/docs/specs/`；顶层 `AGENTS.md` 维护多端路由表，确保 Antigravity / WorkBuddy / ZCode / Codex / Cursor / Claude Code / Copilot 全工具都能准确命中对应端规则。
   - **多仓工作区**（每个端独立 Git 仓）：各端仓库分别独立执行 `init-project-governance.sh`，并在 `docs/overview.md` 标注共享契约仓位置。
4. **安全、数据与合规红线**：明确禁改区路径（鉴权、资金、迁移、发布、依赖清单）并对应写入 `<project>/.github/CODEOWNERS`。

## Stage 1：仓库宪法与轻量治理落盘

1. 在 `agent-governance` 仓库根目录执行建项脚手架：
   ```bash
   # 单端项目
   bash scripts/init-project-governance.sh --target <project> --project-name <name>

   # 多端 Monorepo（支持嵌套路径如 client/ios）
   bash scripts/init-project-governance.sh --target <project> --project-name <name> \
     --apps <name>-backend,<name>-client-ios,<name>-admin,<name>-frontend

   # 后续在已初始化的多端项目里新增端
   bash scripts/init-project-governance.sh --target <project> --add-app <name>-client-android
   ```
2. 激活本地 `commit-msg` 钩子（Spec 同步 + Commit 归属）：
   ```bash
   bash <project>/scripts/governance/install-hooks.sh
   ```
3. 补全 `<project>/docs/overview.md`、`<project>/AGENTS.md`（及各端 `<app>/AGENTS.md`）中的真实构建/测试/原生 Lint 命令，并把 `<project>/.github/CODEOWNERS` 中的 `@team-leads` 替换为真实负责人。
4. 后续公共基线升级继续使用 `bash scripts/sync-project-governance.sh --root <workspace>` 同步 `<project>/AI-GOVERNANCE.md`。

## Stage 2：成熟开源选型、轻量 ADR、首版 Spec & Todo

1. **优先成熟开源方案**：针对核心基础设施域（UI 底座、网络、校验、日志、ORM/持久化、状态管理、测试框架），列出候选对比（社区成熟度、近 12 个月发布活性、类型/接口契约、维护成本），确认后登记到 `<project>/docs/architecture/tech-stack.md`（多端写各自 `<app>/docs/architecture/tech-stack.md`），明确**禁止自研领域**。
2. **锁定架构 ADR**：把不可轻易逆转的架构决定（分层边界、依赖方向、封装契约）记录到 `<project>/docs/adr/<Module>/`。
3. **落首版 Spec 与 Todo**：确认后的首期核心需求写入 `<project>/docs/specs/<Module>/` 并登记索引；用 `superpowers` 拆解出可执行、带验收命令的 `<project>/docs/todos/001-bootstrap.md`。
4. **独立方案复核**：新项目基础架构强制命中独立方案复核门禁（见 `ai-change-flow` Skill），独立 Reviewer 审查通过后才进入 Stage 3。

## Stage 3：最小基建、二次封装与原生 Linter 先行（Foundation First）

**核心原则：只建首期业务真实会用到的最小封装集合，不提前空造几十个尚未使用的抽象或组件。**

### A. 带 UI 项目（Web / iOS / Android-Kotlin / 桌面）必建项
1. **两层 Design Token**：先建 Primitive（基础色板/字阶/间距）+ Semantic（意图语义 Token），业务层只消费 Semantic Token。
2. **首期必需基础组件二次封装**：仅封装首期页面真要用的基础组件（如 Button、Input、Dialog、Toast、页面容器），屏蔽底层 UI 库细节并锁定 Token。
3. **原生 Linter 硬门禁**：在项目自有 Linter 中配置防硬编码与防绕过规则（报错文案直接指路封装入口），并写入 `<project>/.github/workflows/ai-governance.yml`：
   - Web/TS：ESLint `no-restricted-imports`（放行封装层）+ Stylelint `color-no-hex` / `var(--token)`；
   - iOS Swift：SwiftLint `custom_rules`（禁硬编码 `Color(`/`UIColor(red:` 与绕过封装）；
   - Android/Kotlin：Detekt `ForbiddenImport` / `ForbiddenMethodCall`（禁硬编码色值与直引底层组件）。

### B. 全项目通用（含 Java / Kotlin / Go / Python 服务端及客户端）必建项
1. **核心三方库薄封装 / 防腐层**：按实际需要落地统一封装（网络客户端、结构化日志、统一错误模型、强类型配置、存储或鉴权适配），业务层不得裸调底层库。
2. **原生 Linter / 分层门禁**：配置对应生态规则（如 Java Checkstyle `IllegalImport` / ArchUnit、Kotlin Detekt、golangci-lint、ruff）拦截裸调与越层调用。
3. **登记目录地图与反证校验**：把已建好的 Token、封装组件、三方库封装与公共工具目录登记到 `docs/architecture/tech-stack.md`；用一条临时违规代码验证原生 Linter 确实报错拦截后再清理。

## Stage 4：Walking Skeleton 端到端贯通验收

进入正式业务功能开发前，先跑通 1 条极薄的端到端链路：
- **带 UI 项目**：1 个最小页面/路由，完全通过 Semantic Token 与二次封装组件渲染，走通构建与单测；
- **服务端项目**：1 个最小健康检查接口，走通路由 → Service → 统一错误与日志封装 → 单测与构建；
- **全绿验收信号**：构建、单测、原生 Linter、`check-spec-sync.py` 与 `commit-msg` 钩子全部真实通过。

## Stage 5：放行进入常规业务开发

Stage 0–4 全部验收通过后，将 `<project>/docs/todos/001-bootstrap.md` 标为 `Status: ready-to-close` 并勾完收尾，转入常规 Spec-Driven 迭代：
- 新功能 / 改需求：先更新 `docs/specs/`（或 `docs/contracts/`）与 `docs/todos/` → 再写代码；
- 写代码前：先查 `docs/architecture/tech-stack.md` 指向的封装与公共目录，优先复用既有能力。
