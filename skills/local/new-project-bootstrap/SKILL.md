---
name: new-project-bootstrap
description: Enterprise 6-stage greenfield project bootstrap workflow (clarify with Non-Goals, standard docs/ directory + lightweight self-contained project governance kit, open-source selection/ADR/Spec/Todo + independent review, foundation & wrapper layers + native linter before features, Walking Skeleton E2E gate). Use when creating a new project from scratch, setting up a new repository, or establishing initial project standards before business coding.
---

# 新建项目规范建项（6 阶段企业门禁）

本 Skill 用于**从零初始化新项目或新独立仓**，按企业 Golden Path / Walking Skeleton 范式执行严格的阶段门禁，防止直接跳进业务编码导致目录散乱、缺 Token/组件/三方库二次封装、缺 Spec/Todo、或不同成员用 AI 风格漂移。

**适用边界**：主要用于从零新建项目或重建架构骨架；**接手存量老项目接入规范**时，先按 [`references/existing-repo-onboarding.md`](references/existing-repo-onboarding.md) 执行 P0 只读盘点再最小侵入接入，不强拆老仓目录。日常迭代（L0/L1/L2 改动与 Bug 修复）走 `global/AGENTS.md` 与 `ai-change-flow` Skill，不加载本 Skill。

## 强制 6 阶段顺序（禁止跨阶段写业务代码）

```text
Stage 0: 项目画像、需求与非目标澄清（grilling）
   ↓
Stage 1: 规范目录骨架 + 接入轻量自包含项目治理（scripts/init-project-governance.sh）
   ↓
Stage 2: 成熟开源选型、轻量 ADR、首版 Spec & Todo → 独立方案复核
   ↓
Stage 3: 最小基建与二次封装层先行（Token / 基础组件 / 三方库封装 + 接入各端原生 Linter）
   ↓
Stage 4: Walking Skeleton 端到端贯通验收（构建 / 测试 / 原生 Lint / 治理门禁全绿）
   ↓
Stage 5: 放行进入常规业务模块开发
```

## 阶段执行要点与路由

| 阶段 | 必做交付物 | 关联能力 / 命令 | 放行条件 |
| --- | --- | --- | --- |
| **Stage 0 澄清** | 产品目标、**Non-Goals（明确不做）**、运行形态（单端 / 多端 Monorepo / 多仓）、技术栈与安全数据红线 | 调用 `grilling` 逐问确认 | 核心边界与首期范围无未决歧义 |
| **Stage 1 建骨架与门禁** | 根目录 `AGENTS.md`（多端含子端路由表）、`CLAUDE.md` 薄指针、`docs/{overview.md,contracts,architecture/tech-stack.md,specs,todos,adr}`、`.github/CODEOWNERS`、Spec 同步与归属门禁 | 单端：`bash scripts/init-project-governance.sh --target <project>`<br>多端：`--apps <backend,ios,admin,frontend>`（后续扩端 `--add-app`）+ `<project>/scripts/governance/install-hooks.sh` | `<project>/AGENTS.md`（及各端 `<app>/AGENTS.md`）填好命令；`CODEOWNERS` 替换为真实负责人；本地 `commit-msg` 钩子激活 |
| **Stage 2 选型与文档** | `<project>/docs/architecture/tech-stack.md`（成熟开源候选对比与封装目录地图）、基础架构 ADR、首期核心 `docs/specs/<Module>/` 与 `docs/todos/<task>.md` | 路由 `superpowers` 拆解 Todo；按 `ai-change-flow` 过**独立方案复核** | 用户确认 Spec/Todo 且独立方案复核 `PASS` |
| **Stage 3 基建先于业务** | 仅建**首期业务真需要的最小基建**：带 UI 先建两层 Design Token（Primitive + Semantic）与核心组件二次封装；全项目先建三方库薄封装（网络/日志/错误/配置/存储或鉴权）；配好本端**原生 Linter 防绕过规则**（ESLint/Stylelint、Checkstyle、SwiftLint、Detekt）并登记到 `tech-stack.md` 与 CI | 各端原生 Linter + `tech-stack.md` 目录地图 | 封装层落地、目录地图已登记、故意违规样例能被原生 Linter 真实拦截 |
| **Stage 4 Walking Skeleton** | 1 条极薄的端到端烟测链路（如健康检查接口，或 1 个只用 Token + 二次封装组件的最小页面） | 项目真实构建、单测、原生 Lint 与治理门禁 | 构建、测试、原生 Lint、Spec 与归属门禁全绿 |
| **Stage 5 放行业务** | 交接清单（已锁定选型、封装目录地图、首期 Todo 入口） | 切换常规迭代流程 | Stage 0–4 全部勾选通过 |

## 详细检查清单

- 新建项目 6 阶段逐项交付标准、跨端基建分流清单与原生 Linter 防绕过建议：[`references/stages.md`](references/stages.md)
- 存量老项目 P0 只读盘点、多工具加载实测验收（I-01～I-05）、大仓检索停止条件与多仓契约发布顺序：[`references/existing-repo-onboarding.md`](references/existing-repo-onboarding.md)

按当前场景按需读取，不整篇预加载。
