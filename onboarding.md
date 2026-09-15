# 多设备使用说明

`agent-governance` 是个人跨设备共享的全局 AI 开发约束仓库。每台设备只需要拉取本仓并运行分发脚本，不需要把项目代码复制到本仓。

## 新设备

```bash
git clone <agent-governance-repository-url>
cd agent-governance
git config core.hooksPath .githooks   # 启用治理仓 commit-msg 检查
bash scripts/distribute.sh
```

分发脚本会安装（`~/.codex/AGENTS.md` 是唯一真源副本，其余工具入口都是指向它的软链）：

- `~/.codex/AGENTS.md`：全局通用 AI 开发约束；
- `~/.codex/ai-change-implementation-prompt.md`：复杂任务按需读取的详细流程；
- `~/.codex/check-commit-attribution.sh`：commit 归属检查器，可复制进项目仓库；
- `~/.claude/CLAUDE.md`、`~/.pi/agent/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.dsh/AGENTS.md`、`~/.commandcode/AGENTS.md`：软链到真源；
- `~/.workbuddy-ai/rules/agent-governance.md`：WorkBuddy 用户级规则（带 frontmatter，是生成文件不是软链）；
- `~/.codex/.gov-version`：已安装版本号。

用 `bash scripts/distribute.sh --list-targets` 可以只查看目标清单，不安装。

本仓根目录的 `AGENTS.md` 是指向 `global/AGENTS.md` 的软链，让治理仓自己受同一套约束。它不是分发产物，随仓库一起 clone 下来；如果丢了（例如被某次打包或复制操作解成普通文件），用 `ln -sf global/AGENTS.md AGENTS.md` 重建，`tests/distribute.sh` 会检查它。

不要直接编辑这些分发文件；它们会被下次分发覆盖。要修改全局约束，回到 `agent-governance` 修改、提交并推送。

个人配置放在 `~/.claude/settings.json`、`settings.local.json` 和其他本机配置中，分发脚本不碰。不要把 token、API key 或个人 memory 提交进任何仓库。

## 已有设备更新

在任意设备执行：

```bash
cd agent-governance
git pull --ff-only
bash scripts/distribute.sh
```

如果分发脚本提示规则文件有未提交修改，先检查本机是否手工编辑过治理源文件；不要用本机副本覆盖治理仓规则。

## 本地校验与回滚

```bash
bash tests/run-all.sh                      # 全部测试套件
bash scripts/distribute.sh --list-targets  # 只看目标清单，不安装
bash scripts/distribute.sh --rollback      # 回到最近一次分发前的整组状态
```

分发门禁包含「本地仓不落后 origin」：origin 存在但 fetch 失败会直接中止，不会把本地旧规则装成「已是最新」。

## 使用项目

进入具体项目后，先读取项目自己的 AI 约束入口，再按项目说明读取架构、Spec、Contract、测试和命令：

```bash
cd /path/to/project
sed -n '1,240p' AGENTS.md
```

项目的 AI 约束、Spec 和文档不由本仓分发或覆盖。
