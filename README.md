# agent-governance — 团队 AI 治理仓

全局 AI 约束的唯一真源，经 `scripts/distribute.sh` 下发到每位开发者电脑。
项目级约束在各项目 git（AGENTS.md / specs / docs/agent）。

## 结构

```
global/
├── AGENTS.md                          # 语言无关过程基线（所有项目通用）
└── ai-change-implementation-prompt.md # SDD 全文
team-contract.md                       # 团队契约：角色 / AI 禁改区 / AI 改动守则 / 规则变更流程
onboarding.md                          # 新成员从零到第一个 PR
scripts/distribute.sh                  # 分发（支持 --rollback）
scripts/check-version-bump.sh          # 规则改了没 bump VERSION 就拦下
VERSION                                # 基线版本号（语义化，规则变更后 bump）
```

> 团队共享的钩子/权限**不在这里**，放各项目的 `.claude/settings.json`（进项目 git，
> 天然走 PR 评审、只对该项目生效）。`~/.claude/settings.json` 是个人层，分发脚本不碰。

## 规则变更流程

1. 开分支 → 改 `global/` 或 `team-contract.md` → 提 PR
2. 至少 1 名 reviewer 批准（**规则变更不可自行合并**）
3. **bump `VERSION`**（语义化版本）——忘了会被 `check-version-bump.sh` 拦下
4. 各成员跑 `bash scripts/distribute.sh` 更新本机

## 分发

```bash
bash scripts/distribute.sh
```

分发前门禁：规则文件无未提交改动 → VERSION 已 bump → 本地仓不落后 origin。
安装到 `~/.codex/AGENTS.md`（`~/.claude/CLAUDE.md` 软链接指向同一文件）。
内容一致时跳过，不产生冗余备份；覆盖前自动备份为 `~/.codex/AGENTS.md.bak-<时间戳>`。

回滚到最近一次备份：

```bash
bash scripts/distribute.sh --rollback
```

## 团队契约

角色定义、AI 禁改区（含当前强制力的真实状况）、AI 改动守则、spec 模型见
[`team-contract.md`](team-contract.md)。新成员先读 [`onboarding.md`](onboarding.md)。
