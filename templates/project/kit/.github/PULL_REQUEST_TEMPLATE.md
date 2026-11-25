## 变更摘要

- **变更级别**：`L0` / `L1` / `L2`
- **关联 Spec / 契约**：`docs/specs/...` 或 `docs/contracts/...`
- **Spec 豁免（仅 L0 / L1-bug / internal-refactor）**：<!-- Spec-Exempt: L1-bug | reason=恢复既有 Spec 行为 -->
- **关联 Todo**：`docs/todos/...`（如有）

## 规范与复用自查

- [ ] 已检索 `docs/architecture/tech-stack.md` 及封装/公共目录，优先复用已有 Token、二次封装组件、既有方法与批准开源库
- [ ] 未绕过项目封装层，原生 Linter 与构建/测试均已真实通过
- [ ] 如新增第三方依赖，已在 `docs/architecture/tech-stack.md`（或 ADR）记录候选对比与选型结论
- [ ] 如新增需求或修改需求，已同步更新对应 `docs/specs/`（或 `docs/contracts/`）与 Todo 清单

## 验证证据

```text
# 粘贴实际执行的构建 / 测试 / 原生 Lint 命令与结果
```
