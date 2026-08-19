# 新成员 onboarding

从零到能提第一个 PR。预计 1-2 小时（不含依赖下载）。

## 1. 环境

| 项 | 版本 | 说明 |
|---|---|---|
| Node.js | `24.11.1`（见各仓 `.nvmrc`） | release-check 会硬校验 `>=24.11.1 <25` |
| npm | `>=11.12.1` | 同上 |
| MySQL / Redis | backend 本地依赖 | 详见 `hengqin-backend/AGENTS.md` |

## 2. clone 四个仓

三个业务仓互相独立，desktop 与 admin 启动时都连 backend。

```bash
git clone git@github.com:peanutgao/hengqin-backend.git
git clone git@github.com:peanutgao/hengqin-desktop.git
git clone git@github.com:peanutgao/hengqin-admin.git
git clone https://github.com/peanutgao/agent-governance.git   # 规则仓
```

## 3. 装全局规则基线

```bash
cd agent-governance && bash scripts/distribute.sh
```

装完后：

- `~/.codex/AGENTS.md` = 全局过程基线（Codex 读）
- `~/.claude/CLAUDE.md` → 软链接到同一文件（Claude Code 读）
- `~/.codex/.gov-version` = 已装版本号

**不要直接编辑这两个文件**——它们会被下次分发覆盖。改规则走治理仓 PR（见 `team-contract.md` §4）。
个人配置放 `~/.claude/settings.json` / `settings.local.json`，分发脚本不碰。
🔴 **`~/.claude/settings.json` 常含明文 API key，绝不要提交进任何仓库。**

## 4. 必读（按顺序，约 40 分钟）

1. `agent-governance/team-contract.md` — 角色、AI 禁改区、AI 改动守则
2. `~/.codex/AGENTS.md` — 全局过程基线（SDD、需求管线、Bug 根因门禁、代码质量红线）
3. `e-commerce-toolkits/AGENTS.md` — 仓库总览与架构边界
4. 你要动的那个子项目的 `AGENTS.md` — 本地命令、目录、分层
5. 你要动的那个模块的 spec（`specs/<域>/`）— **业务真相，代码不是**

## 5. 本地跑起来

需要 3 个终端（desktop / admin 都依赖 backend 先起）：

```bash
cd hengqin-backend && npm ci && npm run dev      # 127.0.0.1:50001
cd hengqin-desktop && npm ci && npm run dev      # Vite 127.0.0.1:50002
cd hengqin-admin   && npm ci && npm run dev      # 127.0.0.1:50003
```

## 6. 第一个 PR

1. 从 `dev` 切分支（**主干是 `dev`，`master` 是可发布分支**；不要直接推任何一个）
2. 改动前先确认业务真相：对应 spec 是 `approved` / `active` 吗？不确定就先问，不要猜
3. 提交信息 `<type>: <subject>`，type = `feat|fix|refactor|docs|test|chore|perf`，**不加 scope**
4. 自验：`npm run lint` + `npm test`（结果要贴进 PR）
5. 提 PR，按模板逐项填——「验证证据」表贴**真实命令与输出**，不写「已通过」
6. 用了 AI 就在「AI 参与」节说明，并给 commit 带 `Co-Authored-By: <模型名>`
7. 碰到禁改区（`team-contract.md` §2.2）→ 先找 owner，别自己合

## 7. 发布前

```bash
cd e-commerce-toolkits && ./scripts/release-check.sh
```
