# 多设备使用说明

`agent-governance` 是个人跨设备共享的全局 AI 开发约束仓库。每台设备拉取本仓并运行安装脚本，即可部署全局规则和常用 Skills。

## 新设备一键部署

部署入口安装全局规则、清单中的 Skills，以及安装所需的 Git、Python 和 Node.js/npm。运行时可用时直接复用，否则用 conda-forge 在当前用户目录创建专用运行时。支持 macOS、Linux 和 Windows 原生的 x64、ARM64。首次部署需要访问 GitHub、conda-forge 和 npm。

**macOS / Linux** 在终端粘贴整段。系统需能运行 Bash、curl、tar，解包可用 bzip2 并支持 SHA-256 校验。

```bash
(
  launcher="$(mktemp)" || exit 1
  trap 'rm -f "$launcher"' EXIT
  curl -fsSL --proto '=https' https://raw.githubusercontent.com/peanutgao/agent-governance/main/scripts/bootstrap.sh -o "$launcher" &&
    bash "$launcher"
)
```

**Windows 原生** 在 PowerShell（5.1 或更新版本）粘贴整段。系统需提供 Windows tar，部署不要求管理员权限或开发者模式。

```powershell
$launcher = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-governance-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    Invoke-WebRequest -UseBasicParsing -ErrorAction Stop -Uri "https://raw.githubusercontent.com/peanutgao/agent-governance/main/scripts/bootstrap.ps1" -OutFile $launcher
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher
    if ($LASTEXITCODE -ne 0) { throw "部署失败，退出码 $LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $launcher) { Remove-Item -LiteralPath $launcher }
}
```

两种入口都从 GitHub 的 `main` 拉取完整仓库到用户目录下的 `.local/share/agent-governance/bootstrap/repo`。再次运行同一命令会快进更新并分发。AI 客户端由设备自行安装。PowerShell 执行策略仅对上面启动的子进程生效。

已经自行克隆仓库且运行时齐备时，可以从仓库根目录直接运行 `bash scripts/install.sh`。Windows 从 PowerShell 运行 `scripts/bootstrap.ps1`，可一并准备所需运行时。

安装脚本先分发以下全局规则，再以 `--adopt-all` 自动接管并把 [清单中的 Skills](skills/manifest.json) 同步到 [各工具的全局 Skills 目录](skills/README.md#分发路径)（覆盖前自动建事务快照，可用 `skills.py rollback` 回退）。首次安装的依赖见 [Skills 使用说明](skills/README.md)。

- `~/.codex/AGENTS.md`：全局通用 AI 开发约束；
- `~/.codex/check-commit-attribution.sh`：commit 归属检查器，可复制进项目仓库；
- `~/.claude/CLAUDE.md`、`~/.pi/agent/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.dsh/AGENTS.md`、`~/.commandcode/AGENTS.md`、`~/.omp/agent/AGENTS.md`、`~/.config/zed/AGENTS.md`、`~/.config/amp/AGENTS.md`：Unix 上是指向真源的软链，Windows 上是普通文件副本；
- `~/.copilot/copilot-instructions.md`：GitHub Copilot CLI 的个人级入口（内容副本，它不读 AGENTS.md）；
- `~/.workbuddy-ai/rules/agent-governance.md`：WorkBuddy 用户级规则（带 frontmatter，是生成文件不是软链）；
- `~/Documents/work/CLAUDE.md`：OrbStack 虚拟机共享 work 目录入口（普通文件副本，供 VM 内工具经挂载读取）；
- `~/.codex/.gov-version`：已安装版本号。

用 `bash scripts/distribute.sh --list-targets` 可以只查看目标清单，不安装。

本仓根目录的 `AGENTS.md` 是指向 `global/AGENTS.md` 的轻量指针文件（非软链、非正文副本），避免工具把同一份规则按不同路径重复注入上下文。它不是分发产物，随仓库一起 clone 下来，`tests/distribute.sh` 会守住它。

不要直接编辑这些分发文件；它们会被下次分发覆盖。要修改全局约束，回到 `agent-governance` 修改、提交并推送。

个人配置放在 `~/.claude/settings.json`、`settings.local.json` 和其他本机配置中，分发脚本不碰。不要把 token、API key 或个人 memory 提交进任何仓库。

## 已有设备更新

在任意设备执行：

```bash
cd agent-governance
git pull --ff-only
bash scripts/install.sh
```

如果分发脚本提示规则文件有未提交修改，先检查本机是否手工编辑过治理源文件；不要用本机副本覆盖治理仓规则。

## 本地校验与回滚

```bash
bash tests/run-all.sh                     # 已明确授权时执行全部测试套件
bash scripts/distribute.sh --list-targets  # 只看目标清单，不安装
bash scripts/distribute.sh --rollback      # 回到最近一次分发前的整组状态
```

分发门禁包含「本地仓不落后 origin」：origin 存在但 fetch 失败会直接中止，不会把本地旧规则装成「已是最新」。

`--check` 校验受管副本与版本号是否与治理仓一致。各项目需自行接入提交归属检查。`--rollback` 先核对完整快照清单，恢复全部受管目标。

## 使用项目

进入具体项目后，先读取项目自己的 AI 约束入口，再按项目说明读取架构、Spec、Contract、测试和命令：

```bash
cd /path/to/project
sed -n '1,240p' AGENTS.md
```

项目的 AI 约束、Spec 和文档不由本仓分发或覆盖。

### 从空仓库开始

用首个可运行、可验收的功能确定项目起步约束：

1. 确认首个功能的目标、验收条件和已知限制。查找可以沿用的模板、组件和依赖，写下候选路径和取舍。
2. 第一次决定模块边界、依赖方向或基础技术选型时，按 `ai-change-flow` Skill 的「独立方案复核」核对方案。把通过复核的架构边界、复用入口、第一条可执行的验证命令和文档索引记录到项目的 `AGENTS.md`。
3. 为首批已批准的业务行为建立 Spec。在架构文档记录已确定的模块归属与依赖方向，把需要长期保留的决策和理由写入 ADR。文档按项目采用的目录约定维护。
