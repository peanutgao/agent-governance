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
每个禁改区建议配**主 owner + 备 owner 两人**：只挂一人时，本人的改动无人可批（GitHub 不允许自审），门禁必然被 bypass 绕过。

## 2. AI 禁改区

AI 在这些区域**只能产出改动方案 / 写到独立分支或草稿 PR**，不能合并、不能碰主干；必须由对应 owner 批准后才落地。

### 2.1 当前强制力（重要，别当成已经有保护）

三个业务仓都是**个人账号下的私有仓**，GitHub Free 不提供 branch protection——实测
`GET /repos/{owner}/{repo}/branches/master/protection` 返回 `403 Upgrade to GitHub Pro`。
因此当前状态是：

| 想要的门禁 | 现在是否生效 |
|---|---|
| 主干不可直接 push | ❌ 无 |
| PR 强制 review | ❌ 无 |
| CODEOWNERS 强制 owner approve | ❌ 无（仅自动 @ 请求 review） |
| CI 跑起来并留下红/绿记录 | ✅ 有 |
| 本地 git hook | ✅ 有（`--no-verify` 可绕） |

**结论：禁改区目前靠 PR 模板 + 人工把关，`.github/CODEOWNERS` 是提示不是门禁。**
文档里不得把它写成「硬约束」。要变成真门禁，需仓库 owner 升级计划或迁入 Org 后开启
"Require review from Code Owners" + 分支保护。

### 2.2 禁改区清单

清单与真实目录**必须逐条对得上**：CODEOWNERS 里写一条不存在的路径，GitHub 静默忽略，
看起来有保护实际没有（曾发生过 `src/modules/entitlement/` 这种不存在的条目）。

**hengqin-backend**

| 禁改区 | 路径 | 风险 |
|---|---|---|
| payment | `src/modules/payment/` | 计费/订阅/幂等/双扣 |
| credits | `src/modules/credits/` | 额度授予/消耗 |
| refund | `src/modules/refund/` | 退款/债务 |
| auth | `src/modules/auth/` | 访问控制边界 |
| activation | `src/modules/activation/` | 激活态 |
| feature-config | `src/core/feature-config/` | 付费墙开关；**entitlement 实际由它 + activation 承载，没有独立 entitlement 模块** |
| migrations | `src/migrations/` | 数据不可逆 |
| releases | `src/modules/releases/` | 发布通道 |
| 发布门禁链 | `scripts/release-check.sh`、`scripts/check-env-safety.sh`、`scripts/check-doc-links.sh` | 改任一环等于放宽发布门禁 |

**hengqin-desktop**

| 禁改区 | 路径 | 风险 |
|---|---|---|
| security 域 | `src/main/security/` | 凭据/安全边界 |
| 登录 token | `src/main/services/auth/` | 与 security/ 的 token store 同一条链 |
| preload | `src/preload/` | 主/渲染进程唯一能力出口，放宽即放宽整个沙箱 |
| 自动更新 | `src/main/services/update/` | **供应链**：可向全部客户端推任意代码 |
| 打包与签名 | `electron-builder.config.cjs`、`scripts/validate-release-signing.cjs`、`scripts/verify-release-artifacts.cjs`、`scripts/harden-macos-info-plist.cjs`、`scripts/validate-package-env.cjs`、`scripts/api-url-policy.cjs` | 发布产物完整性 |

**三仓共同**

| 禁改区 | 路径 | 风险 |
|---|---|---|
| 业务真相 | `specs/` 与 `**/spec/` | spec 是业务真相；`**/spec/` 覆盖模块内 colocated spec，避免第一次 colocate 就脱离保护 |
| 治理自身 | `/.github/`（含 CODEOWNERS、workflows） | 不保护 CODEOWNERS 自己，任何人都能把自己改成 owner |

> ⚠️ 仓库外的 `e-commerce-toolkits/scripts/release-check.sh`（父目录版，全仓发布总入口）
> 位于**非 git 目录**，既不受任何保护也无法分发给团队。归属未定，见「待决」。

### 2.3 例外必须留痕

例外仅限 owner 明确授权。**口头授权不算**——授权必须以可追溯形式落在 commit 或 PR 上：

```
Governance-Exception: <禁改区> | approved-by=@<owner> | reason=<一句话>
```

没有这行 trailer 的禁改区改动，一律按未授权处理（后续可由 CI 检测该 trailer）。

## 3. AI 改动守则

每个 AI 改动必须：
1. **自验**：typecheck / lint / 相关测试通过，结果写进 PR 的「验证证据」表（贴真实命令与输出，不写「已通过」）
2. **标 author**：`Co-Authored-By: <AI 模型名>`
3. **走 PR**：不直接推主干
4. **不碰禁改区**：触碰必须有 owner 批准 + §2.3 的 trailer
5. **决策引用 spec / ADR**（Requirement ID）

## 4. 规则变更流程

| 规则层 | 变更方式 |
|---|---|
| 全局基线 | agent-governance PR + ≥1 reviewer 批准 + **bump VERSION**（`scripts/check-version-bump.sh` 拦截忘记 bump）→ 各成员跑 `distribute.sh` |
| 项目规则 | 各项目 git PR + 模块 owner / 技术负责人评审 |
| 业务规则 | 先 Change Proposal → 澄清 → 决策 → **更新权威 spec** → 再实现 |

## 5. spec 模型

- **一个模块一份 spec**（可拆 overview / creation / refund 多文件），一条规则一个权威源
- **迭代中原地更新到最新**；历史进 ADR / Git，spec 只留当前真相
- `approved` = 冻结目标（未实现）；`active` = 当前行为真相
- Requirement ID 分配后**保持稳定**，跨 spec / 实现 / 测试引用
- 改 spec 走 Change Proposal + 评审（`specs/` 与 `**/spec/` 在禁改区）

### plan 文档生命周期

- **plan（`docs/plans/`）是一次性过程文档，不是业务真相**；实施完成后其价值已沉淀进 `specs/`（业务规则）+ `docs/adr/`（决策理由）。
- **清理流程**：①迁移内容（业务规则→spec、决策理由→ADR）→ ②归档（`docs/archive/` 或标记 `_superseded`）→ ③在 `scripts/check-doc-links.sh` 的 `BANNED` 登记（防回退 + 防断链）→ ④物理删除。
- **保留条件**：未收尾的 plan、尚未迁移进 ADR 的决策理由——先迁移再删。
- **目的**：docs 主线保持精简，新成员只读 AGENTS.md + specs，不被过时 plan 干扰。

## 6. 分发与个人层边界

- 全局基线经 `scripts/distribute.sh` 手动下发；分发前自动跑 `check-version-bump.sh`，
  并在配置了 origin 时检查本地仓是否落后（避免把旧规则装成「最新」）
- **`~/.claude/settings.json`、`settings.local.json`、Claude memory 全部是个人层，分发脚本一律不碰**
- **团队共享的钩子/权限放各项目的 `.claude/settings.json`**（进项目 git，天然走 PR 评审、天然只对该项目生效），
  不再经全局分发——分发版曾设计成「仅当本机不存在才安装」，而每个人都已有该文件，等于永远不生效
- 🔴 **禁止把本机 `~/.claude/settings.json` 提交进任何仓库**：该文件常含明文 API key 与代理配置

## 7. AI 数据与执行边界（团队特定部分）

**行为规则的权威源是全局基线 `global/AGENTS.md` 的「AI 数据与执行边界」**（生产只读、三类数据不得投喂、远端不可逆操作要人确认）。本节只补本团队特定的通道清单与落地方式，不复述规则正文。

### 7.1 已批准的模型通道

源代码可以走第三方 AI 中转，但**只能走下列通道**；新增需技术负责人批准并更新本表。

| 通道 | 说明 |
|---|---|
| Anthropic 官方 API / Claude Code 默认端点 | 默认可用 |
| `https://opencode.ai/zen` | 团队当前在用；第三方中转，落到 deepseek / glm / grok 等非 Anthropic 模型 |

全局基线里的三类禁投喂数据，在**任何**通道下都不得发送。

### 7.2 机器拦截落地

各项目 `.claude/hooks/guard-destructive.sh`（PreToolUse(Bash) 钩子，在 `.claude/settings.json` 挂载，随项目 git 分发，对所有成员生效）拦截：

- force push、删远端分支/tag、重写历史
- 本仓生产脚本：`deploy-docker.sh`、`init-production-env.sh`
- 执行数据库迁移（`migration:run` / `migration:revert`）

用钩子而非 `permissions.deny`：deny 是**前缀匹配**，拦得住 `git push --force …`，拦不住 `git push origin --force`；钩子按整条命令做正则判断。触发时返回退出码 2，命令不执行，AI 收到拦截原因。

**生产数据库的读/写在命令层无法可靠区分**，全局基线里的生产写入禁令靠契约与人审，钩子只兜住部署脚本与迁移这两个确定信号。钩子与 `.claude/` 属禁改区，放宽规则须 owner 批准。
