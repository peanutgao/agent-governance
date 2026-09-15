# agent-governance — 个人多设备 AI 开发约束

个人跨设备共享的全局 AI 开发约束仓库。每台设备拉取本仓后执行 `scripts/distribute.sh`，更新本机的全局 AI 约束。

项目级约束、架构、Spec、Contract、测试和发布说明由各项目仓库自己维护。本仓库不收集项目代码，也不替项目维护项目级 AI 约束。

## 结构

```text
global/
├── AGENTS.md                          # 个人全局通用约束
└── ai-change-implementation-prompt.md # 复杂任务按需读取的详细流程
onboarding.md                          # 多设备初始化和更新
scripts/distribute.sh                  # 分发（支持 --rollback）
scripts/check-commit-attribution.sh    # 治理仓 commit 归属检查
scripts/check-version-bump.sh          # 规则改动检查
VERSION                                # 基线版本号
```

> 本仓只分发个人全局规则，不分发项目设置、项目 hook、权限、token 或个人 memory。
> `~/.claude/settings.json`、`settings.local.json` 和其他本机配置由个人自行维护，分发脚本不碰。

## 修改全局约束

1. 修改 `global/`、分发脚本或相关检查脚本。
2. **bump `VERSION`**（语义化版本）。
3. 运行语法、测试和 `git diff --check`。
4. 提交并推送；其他设备执行 `git pull` 和 `bash scripts/distribute.sh`。

## 分发到设备

```bash
bash scripts/distribute.sh
```

分发前门禁：规则文件无未提交改动 → VERSION 已更新 → 本地仓不落后 origin。

安装到：

- `~/.codex/AGENTS.md`；
- `~/.codex/ai-change-implementation-prompt.md`；
- `~/.claude/CLAUDE.md` 软链接到 `~/.codex/AGENTS.md`。

内容一致时跳过，不产生冗余备份；覆盖前自动备份为 `~/.codex/*.bak-<时间戳>`。

项目交付物和 Git/协作记录不得披露 AI 参与、模型、供应商、Agent、Bot、生成归属或类似自动化身份信息；历史提交不重写。治理仓规则源可以使用必要的治理术语来定义这条约束。

回滚到最近一次备份：

```bash
bash scripts/distribute.sh --rollback
```

## 项目级 AI 约束

每个项目仓库维护自己的项目级 AI 约束，通常放在项目根目录的 `AGENTS.md` 或 `CLAUDE.md`，并与项目自己的 Spec、架构文档和测试说明一起演进。

项目级文件负责项目专属内容，例如技术栈、目录、构建命令、模块边界、业务规则和发布流程；不要把这些内容写进本仓的全局规则。

本仓不复制或覆盖任何项目仓库文件。

## 设备更新

新设备或已有设备都执行：

```bash
cd agent-governance
git pull --ff-only
bash scripts/distribute.sh
```

首次使用见 [`onboarding.md`](onboarding.md)。本仓不保存设计文档或历史资料；规则、脚本和检查的当前行为以代码、测试和提交历史为准。
