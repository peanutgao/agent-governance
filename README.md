# hengqin-governance — 团队 AI 治理仓

全局 AI 约束的唯一真源，经 `scripts/distribute.sh` 下发到每位开发者电脑。
项目级约束在各项目 git（AGENTS.md / specs / docs/agent）。

## 结构

```
global/
├── AGENTS.md                          # 语言无关过程基线（所有项目通用）
├── ai-change-implementation-prompt.md # SDD 全文
├── settings.json                      # 团队共享钩子/权限
└── skills/                            # 团队共享技能（可选，暂未启用）
team-contract.md                       # 团队契约：角色 / AI 禁改区 / AI 改动守则 / 规则变更流程
scripts/distribute.sh                  # 分发脚本
VERSION                                # 基线版本号（语义化，规则变更后 bump）
```

## 规则变更流程

任何全局规则改动必须：

1. 开分支 → 改 `global/` 或 `team-contract.md` → 提 PR
2. 至少 1 名 reviewer 批准（**规则变更不可自行合并**）
3. 合并后 **bump `VERSION`**（语义化版本）
4. 各成员跑 `bash scripts/distribute.sh` 更新本机

## 分发说明

```bash
bash scripts/distribute.sh
```

- 安装到 `~/.codex/AGENTS.md`（`~/.claude/CLAUDE.md` 软链接指向同一文件）
- 只写团队层；**绝不覆盖** `~/.codex/settings.local.json` 与 Claude memory
- 输出「当前安装版本 → 最新版本」，有新版时提示
- 幂等、失败可回滚（安装前自动备份旧版本到 `~/.codex/AGENTS.md.bak-<时间戳>`）

## 团队契约

角色定义、AI 禁改区、AI 改动守则、spec 模型见 [`team-contract.md`](team-contract.md)。
