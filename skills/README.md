# 全局 Skills 同步

在 macOS 或 Linux 的治理仓根目录使用 Python 3.9 或更新版本。首次获取上游 Skill 还需要 `curl`、npm、Node.js 22.20 或更新版本，以及可访问 GitHub 和 npm 的网络。

```bash
python3 scripts/skills.py plan
python3 scripts/skills.py sync
python3 scripts/skills.py status
python3 scripts/skills.py rollback
```

- `plan` 只读，列出每个工具的有效路径及下一步。已有相同内容标为 `reuse`，本命令已安装的相同内容标为 `ready`。不同内容标为 `conflict`，软链同时显示它的目标。
- `sync` 安装缺失项，更新本命令安装且当前内容仍匹配记录的项。存在未接管冲突时保留这些路径，并以退出码 1 报告。重复同步在内容一致时跳过。
- `status` 核对清单和本机内容。需要同步或存在冲突时退出码为 1。
- `rollback` 撤销最近一次有变更的同步并恢复原目录、文件或软链。可以连续回退。待恢复路径若被外部修改，会报出路径并保留快照。检测到上次操作中断时，下一次 `sync` 或 `rollback` 会先恢复中断事务。

要接管预览里指定的现有名称，用打印出来的 `TOOL:SKILL` 标识。可重复传入多个 `--adopt`。例如：

```bash
python3 scripts/skills.py sync --adopt codex:grilling --adopt claude-code:code-review
```

快照存于 `~/.local/state/agent-governance/skills`。清单移除或目标路径发生变化后，已有受管路径显示为 `retained`，需要清理时根据快照回退对应安装。检验另一台设备的默认路径时，可以传入一个已创建的临时目录 `--home <目录>`。

需要通过本机代理获取 GitHub 源时，在 `sync` 传入 `--proxy <代理地址>`。npm 仍按其自身的网络配置访问注册表。

## 分发路径

| 工具 | 默认目录 |
|---|---|
| Codex | `~/.agents/skills`，已存在的 `~/.codex/skills` 同名项也会检查 |
| Claude Code | `~/.claude/skills` |
| pi | `~/.pi/agent/skills` |
| OpenCode | `~/.config/opencode/skills` |
| DeepSeek Harness | `~/.dsh/skills` |
| Command Code | `~/.commandcode/skills` |
| omp | `~/.omp/agent/skills` |
| WorkBuddy AI | `~/.workbuddy-ai/skills` |

已配置自定义目录时以 `plan` 输出为准。在 OrbStack 内运行的工具应在 VM 内运行同步。状态检查覆盖表中的物理目录。项目级 Skills、额外插件，以及 OpenCode 的平铺或分组 Skill 也可能提供同名定义，验收时以新会话实际发现的来源为准。

## 更新来源

以 [manifest.json](manifest.json) 为清单。自改版在 `local/` 下保留上游许可证。升级原版时选择上游 Git 提交，保持 Vercel Skills CLI 锁版，用临时工作目录分发并核对 `SKILL.md`、附带资料和新摘要。摘要使用 `scripts/skills.py` 的 `skill_key` 对 Vercel CLI 安装得到的目录计算。

当前原版 `codebase-design` 与 `diagnosing-bugs` 锁定在 [Matt Pocock Skills v1.3.2 对应提交](https://github.com/mattpocock/skills/commit/d1478fcb140db0b93c0c8df17bcfd311844749d0)。`grilling` 保留一次一问和事实核对。`code-review` 从项目现有文档读取规则和 Spec，并根据工具能力执行两路审查。项目要求独立审查时，单会话复核应明确标记其状态。
