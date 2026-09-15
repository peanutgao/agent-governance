# 多设备使用说明

`agent-governance` 是个人跨设备共享的全局 AI 开发约束仓库。每台设备只需要拉取本仓并运行分发脚本，不需要把项目代码复制到本仓。

## 新设备

```bash
git clone <agent-governance-repository-url>
cd agent-governance
git config core.hooksPath .githooks   # 启用治理仓 commit-msg 检查
bash scripts/distribute.sh
```

分发脚本会安装：

- `~/.codex/AGENTS.md`：全局通用 AI 开发约束；
- `~/.codex/ai-change-implementation-prompt.md`：复杂任务按需读取的详细流程；
- `~/.claude/CLAUDE.md`：软链接到 `~/.codex/AGENTS.md`；
- `~/.codex/.gov-version`：已安装版本号。

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

## 使用项目

进入具体项目后，先读取项目自己的 AI 约束入口，再按项目说明读取架构、Spec、Contract、测试和命令：

```bash
cd /path/to/project
sed -n '1,240p' AGENTS.md
```

项目的 AI 约束、Spec 和文档不由本仓分发或覆盖。
