# 团队契约（Team Contract）

本文件是团队开发的核心契约：角色、AI 使用边界、禁改区、spec 模型、规则变更流程。
所有成员与 AI 均须遵守；与全局 `global/AGENTS.md` 冲突时，**更严格的一方生效**（本文件通常更具体）。

## 1. 角色（3-5 人轻量版）

| 角色 | 职责 | 门禁 |
|---|---|---|
| 需求发起人（产品/兼职） | 提需求、定目标与验收标准 | 需求管线阶段 1 |
| Spec 评审/冻结（技术负责人） | 评审并冻结 spec | `approved spec` 才可实现 |
| 模块 owner | 负责指定模块：review 该模块 PR、确认禁改区改动 | 该模块 PR 必须 owner approve |
| 发布审批（技术负责人） | 批准发布 | release-check 绿 + 确认 |

3-5 人无专职 QA：代码走「模块 owner + 交叉 review」，AI 辅助。

**模块 owner 划分**：`（待定，由技术负责人分配）`

## 2. AI 禁改区

AI 在这些区域**只能产出改动方案 / 写到独立分支或草稿 PR**，不能合并、不能碰 main；必须由对应 owner 批准后才落地。

| 禁改区 | 路径 | 风险 |
|---|---|---|
| payment | `backend/src/modules/payment/` | 计费/订阅/幂等/双扣 |
| credits | `backend/src/modules/credits/` | 额度授予/消耗 |
| refund | `backend/src/modules/refund/` | 退款/债务 |
| auth+activation+entitlement | `backend/src/modules/{auth,activation,entitlement}/` | 访问控制边界 |
| releases+CI | `backend/src/modules/releases/` + `.github/workflows/` + `scripts/release-check.sh` | 发布门禁 |
| migrations | `backend/src/migrations/` | 数据不可逆 |
| specs 权威文件 | `hengqin-{backend,desktop,admin}/specs/` | 业务真相 |
| security 域 | `desktop/src/main/security/` | 凭据/安全边界 |
| feature-config | `backend/src/core/feature-config/` | 付费墙开关 |

**硬约束（不靠 AI 自觉）**：
- CODEOWNERS：上述目录指定 owner，改动这些文件的 PR 自动 require owner approve
- 分支保护：main 不可直接 push，PR 强制 review
- （可选）pre-push hook 检测 diff 触碰禁改区但无 owner 标记时拦截

**例外**：仅 owner 在场并明确授权时临时豁免；**不设 AI 自行豁免的路径**。

## 3. AI 改动守则

每个 AI 改动必须：
1. **自验**：typecheck / lint / 相关测试通过
2. **标 author**：`Co-Authored-By: <AI>`
3. **走 PR**：不直接推 main
4. **不碰禁改区**（除非 owner 确认）
5. **决策引用 spec / ADR**（Requirement ID）

## 4. 规则变更流程

| 规则层 | 变更方式 |
|---|---|
| 全局基线 | hengqin-governance PR + ≥1 reviewer 批准 + **bump VERSION** → 各成员跑 `distribute.sh` |
| 项目规则 | 各项目 git PR + 模块 owner / 技术负责人评审 |
| 业务规则 | 先 Change Proposal → 澄清 → 决策 → **更新权威 spec** → 再实现 |

## 5. spec 模型

- **一个模块一份 spec**（可拆 overview / creation / refund 多文件），一条规则一个权威源
- **迭代中原地更新到最新**；历史进 ADR / Git，spec 只留当前真相
- `approved` = 冻结目标（未实现）；`active` = 当前行为真相
- Requirement ID 分配后**保持稳定**，跨 spec / 实现 / 测试引用
- 改 spec 走 Change Proposal + 评审（`specs/` 在禁改区）

### plan 文档生命周期

- **plan（`docs/plans/`）是一次性过程文档，不是业务真相**；实施完成后其价值已沉淀进 `specs/`（业务规则）+ `docs/adr/`（决策理由）。
- **清理流程**：①迁移内容（业务规则→spec、决策理由→ADR）→ ②归档（`docs/archive/` 或标记 `_superseded`）→ ③在 `scripts/check-doc-links.sh` 的 `BANNED` 登记（防回退 + 防断链）→ ④物理删除。
- **保留条件**：未收尾的 plan、尚未迁移进 ADR 的决策理由——先迁移再删。
- **目的**：docs 主线保持精简，新成员只读 AGENTS.md + specs，不被过时 plan 干扰。

## 6. 分发与个人层边界

- 全局基线经 `scripts/distribute.sh` 手动下发，版本提示见 VERSION
- **本机 `settings.local.json` / Claude memory 为个人层，分发不覆盖**
- 团队共享钩子/权限放 `global/settings.json`（分发仅首次安装，已有个人版则跳过）
