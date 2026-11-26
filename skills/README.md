# 全局 Skills 同步

在 macOS、Linux 或 Windows 的治理仓根目录使用 Python 3.9 或更新版本。新设备可用 [一键部署入口](../onboarding.md#新设备一键部署) 准备运行时。首次获取上游 Skill 还需要 `curl`、npm、Node.js 22.20 或更新版本，以及可访问 GitHub 和 npm 的网络。

```bash
python3 scripts/skills.py plan
python3 scripts/skills.py sync
python3 scripts/skills.py sync --adopt-all
python3 scripts/skills.py status
python3 scripts/skills.py prune
python3 scripts/skills.py rollback
```

- `plan` 只读，列出每个工具的有效路径及下一步。已有相同内容标为 `reuse`，本命令已安装的相同内容标为 `ready`。不同内容标为 `conflict`，软链同时显示它的目标。
- `sync` 默认安装缺失项，更新本命令安装且当前内容仍匹配记录的项；存在未接管冲突时保留这些路径，并以退出码 1 报告。重复同步在内容一致时跳过。
- `sync --adopt-all` 自动接管并覆盖所有同名冲突路径（仍先创建事务快照以支持 `rollback`），同时保留指向其他受管工具主目录的内部软链（`linked`）；Windows NTFS 重解析点/目录联接点仍按路径安全边界拒绝。不能与 `--adopt` 同时使用。
- `status` 核对清单和本机内容。需要同步或存在冲突时退出码为 1。
- `prune` 以事务方式清理清单中已移除的 `retained` 受管路径（仍做内容校验与整组快照，可通过 `rollback` 恢复；已被外部修改的路径拒绝删除并报错）。
- `rollback` 撤销最近一次有变更的同步或清理并恢复原目录、文件或软链。可以连续回退（默认保留最近 10 份事务快照，可用 `AGENT_GOVERNANCE_SKILLS_BACKUP_KEEP` 调整）。待恢复路径若被外部修改，会报出路径并保留快照。检测到上次操作中断时，下一次 `sync`、`prune` 或 `rollback` 会先恢复中断事务。

要只接管预览里指定的部分现有名称，用打印出来的 `TOOL:SKILL` 标识（可重复传入多个 `--adopt`）；一键部署入口 `scripts/install.sh` 默认使用 `sync --adopt-all` 直接接管全部同名冲突：

```bash
python3 scripts/skills.py sync --adopt codex:grilling --adopt claude-code:code-review
python3 scripts/skills.py sync --adopt-all
```

快照存于 `~/.local/state/agent-governance/skills`，默认保留最近 10 次事务快照。清单移除或目标路径发生变化后，已有受管路径显示为 `retained`，可用 `python3 scripts/skills.py prune` 事务化清理或用 `rollback` 回退。检验另一台设备的默认路径时，可以传入一个已创建的临时目录 `--home <目录>`。

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

`bash scripts/install.sh` 默认以 `skills.py sync --adopt-all` 同步 [清单](manifest.json) 中的全部 Skills（自动覆盖同名旧副本并保留事务快照），具体名称和来源见清单。`code-review`、`grilling`、`evaluate-business-value`、`superpowers`、`ai-change-flow`、`new-project-bootstrap` 使用仓内的本机版本。

GitHub 源的 `path` 为 `.` 时，从仓库根目录读取 Skill。根目录源可用 `upstreamName` 声明上游名称，安装时使用清单中的名称，摘要以调整名称后的目录为准。Windows 摘要按文件内容校验，源包含 Unix 可执行位时用 `windowsDigest` 记录对应的 Windows 摘要。

当前原版 `codebase-design` 与 `diagnosing-bugs` 锁定在 [Matt Pocock Skills v1.3.2 对应提交](https://github.com/mattpocock/skills/commit/d1478fcb140db0b93c0c8df17bcfd311844749d0)。`grilling` 保留一次一问和事实核对。`code-review` 从项目现有文档读取规则和 Spec，并根据工具能力执行两路审查。项目要求独立审查时，单会话复核应明确标记其状态。
