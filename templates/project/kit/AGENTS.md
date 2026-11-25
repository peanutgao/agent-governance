# __PROJECT_NAME__ — 项目工程规范入口

本文件是 `__PROJECT_NAME__` 对所有开发者与 AI 工具（Antigravity / WorkBuddy / ZCode / Codex / Cursor / Claude Code / Copilot 等）的唯一项目级规则地图。

## 必读顺序（编码前）

1. 公共工程治理基线：[AI-GOVERNANCE.md](AI-GOVERNANCE.md)（任务分类、分级、需求变更门禁、独立复核、提交归属）
2. 项目总览与术语：[docs/overview.md](docs/overview.md)（产品目标、Non-Goals、多端分工与术语）
3. 跨端共享契约：[docs/contracts/README.md](docs/contracts/README.md)（共享 API / Event / Schema / Design Token 契约）
4. 开源选型与封装地图：[docs/architecture/tech-stack.md](docs/architecture/tech-stack.md)（已批准开源库、封装与公共能力目录——写代码前先检视对应目录复用）
5. 业务规格与 Todo：[docs/specs/README.md](docs/specs/README.md)、[docs/todos/README.md](docs/todos/README.md)、[docs/adr/README.md](docs/adr/README.md)
__APPS_ROUTING_SECTION__
## 常用命令（按项目实际填写）

```bash
# 构建 / 启动
# <填写项目构建命令>

# 测试
# <填写项目测试命令>

# 原生 Lint / 静态检查（同步写入 .github/workflows/ai-governance.yml）
# <填写项目原生 Lint / Typecheck 命令，如 eslint / stylelint / checkstyle / swiftlint / detekt>
```

## 不可协商红线

1. **先查复用，禁止绕过封装**：写业务代码前先查 `docs/architecture/tech-stack.md` 指向的 Token、二次封装组件、公共工具与三方库封装目录；有成熟开源库优先选用并登记，不自造重型轮子。
2. **代码规范交给原生 Linter 强制拦截**：Design Token 防硬编码、禁止直引底层 UI/HTTP 库等约束统一配置在项目原生 Linter 并在 CI 执行。
3. **先文档后实现，改需求必更 Spec**：新需求调研定案后先落 `docs/specs/<Module>/` 与 `docs/todos/<task>.md`；改需求前先更 Spec。仅 L0、恢复既有 Spec 的 L1 Bug、纯内部重构可在 commit 或 PR 中用 `Spec-Exempt: <类型> | reason=<原因>` 豁免。
4. **基建先于业务**：新项目或新模块先搭好最小 Token / 组件 / 三方库封装层并跑通构建与原生 Lint，再写业务功能。

## 首次拉取仓库

```bash
bash scripts/governance/install-hooks.sh
```
