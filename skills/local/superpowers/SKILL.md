---
name: superpowers
description: "Opt-in structured planning and execution workflow for new projects, major refactors, or complex L2 changes: brainstorming, design validation, implementation planning, and verification. Load on demand for substantial upfront planning; do not force onto routine L0/L1 tasks."
---

# Superpowers

按需使用的结构化规划与实施流程，配合 `global/AGENTS.md` 的「新项目与大重构的前期规划」与 `ai-change-flow` 使用。

> 本 Skill 是**可选流程工具**，不是固定前置步骤：
> - L0 文案/文档修改与普通 L1 局部实现直接按 `global/AGENTS.md` 执行，不套用本流程；
> - 本 Skill 不得覆盖 `global/AGENTS.md` 的安全、授权与 Git 归属底线（**严禁自动 `git commit`**，不为简单任务额外新建冗余文档）；
> - 本 Skill 不替代「实现前的独立方案复核」，命中前置复核门禁时仍须先通过独立复核。

## 适用场景

- 从零搭建新项目；
- 跨模块重构或实质改写架构；
- 目标明确但存在多个可行架构方案、需要分阶段拆解与验收的 L2 复杂任务。

## 核心阶段（按任务需要裁剪）

### 1. Brainstorming（需求澄清与方案探索）
- 业务目标、边界或验收条件不清时，先按 `grilling` 逐问澄清，禁止猜测落地；
- 需求明确后，搜索仓库已有组件、服务和约定，列出 2–3 个候选方案及取舍，推荐最简可行方案；
- 已确认的业务行为写入项目约定的 `specs/<Module>/` 并同步索引；未确认内容不进 Spec。

### 2. Design Validation（设计确认与独立复核）
- 将关键架构决定拆成易评审的小块（边界、数据流、失败路径、兼容与迁移影响），与用户对齐；
- 命中 `global/AGENTS.md` / `ai-change-flow` 独立方案复核条件时，由独立 reviewer 对抗性复核通过后再进入实现；
- 需要长期保留的架构或契约决策写入项目约定的 `docs/adr/<Module>/`。

### 3. Implementation Planning（可执行任务拆解）
- 将已确认设计拆为顺序清晰、可独立验证的 todo，落到项目已有计划文件或既有文档结构下（不强制在根目录散落 `design.md`/`plan.md`）；
- 每个任务写明：目标、精确文件/模块范围、依赖、具体验证命令与预期信号；
- 坚持 YAGNI 与最小连贯改动，不夹带无关重构或推测性抽象。

### 4. Implementation & Testing（实现与相称验证）
- 存在合适测试接缝时优先采用测试驱动（先写失败测试，再做最小实现，最后重构）；没有合适测试接缝时不强行造无价值桩测试，改用可观测的针对性验证；
- 严格遵守「只改范围内文件、不吞错掩盖根因、验证先局部后整体」；
- 绝不在未经用户明确授权时执行 `git commit` 或全量破坏性操作。

### 5. Parallel Subagents（可选，严守并行门禁）
- 默认单 Agent 串行实施；仅在需求冻结、子任务无共享可变状态、拆分经用户确认且使用 worktree/分区隔离时，才派发并行子 Agent；
- 合并后必须重新审查集成点并做跨模块验证。

### 6. Review & Handoff（对抗性复核与收尾）
- 宣称完成前执行系统性对抗性复核（根因、边界、反例、回归与验证证据），必要时跑 `code-review` 双轴审查；
- 保留工作区改动，汇报 `git status` / `git diff` 摘要、实际执行的验证结果和剩余风险，由用户决定后续提交或合并。

## 参考资料

- 阶段模板与检查清单见 `references/workflow.md`；
- 设计、测试与代码质量准则见 `references/best_practices.md`。按需读取，不必整篇加载。
