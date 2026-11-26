# 本仓的工作区入口

本文件只做一件事：把在本仓干活的 AI 指到真源，不复制真源内容。

## 唯一真源

**`global/AGENTS.md`** —— 个人全局 AI 开发约束的唯一正文。任何规则改动都改这里。

## 为什么这里是指针而不是软链

本仓过去把根 `AGENTS.md` 做成指向 `global/AGENTS.md` 的软链。那会让同一份 20KB 规则
在一次会话里被注入多遍：工具按**路径**去重，软链绕过了去重，于是 `~/.dsh/AGENTS.md`、
工作区 `AGENTS.md`、`global/AGENTS.md` 三份内容同时进入上下文。实测每会话多耗约 1 万 token，
而 ETH Zurich SRI Lab 的实证结论是 context 文件不提升任务成功率、反而增加 20% 以上成本。

改成指针后：本仓的工作区入口只有几百字节，真源只在真正需要时被读取。

## 在本仓干活时

1. 改全局约束 → `global/AGENTS.md`；改详细流程 → `skills/local/ai-change-flow/SKILL.md` 及 `skills/local/ai-change-flow/references/full-flow.md`。
2. 改完 `bump VERSION`，再跑 `bash scripts/gov check version`。
3. 验证：`bash scripts/gov test`（即 `tests/run-all.sh`）；分发状态：`bash scripts/gov distribute --check`。
4. 不要直接编辑本机副本（`~/.codex/AGENTS.md` 等），它们会被下次分发覆盖。

详细流程（L2 变更、非显然 Bug、独立方案复核）见 `skills/local/ai-change-flow/SKILL.md`
及其 `skills/local/ai-change-flow/references/full-flow.md`，按需读取。
