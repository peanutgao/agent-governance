# Portable AI Governance

> baseline-version: __BASELINE_VERSION__
> baseline-content-sha256: __BASELINE_HASH__
> source: agent-governance

<!-- BEGIN SHARED-AI-GOVERNANCE: __BASELINE_VERSION__ -->

本文件是项目仓库携带的公共 AI 工程治理快照。同步时将版本号写入 header，将内容 hash 写入边界标记；baseline-content-sha256 是把自身 hash 字段保留为 __BASELINE_HASH__ 后计算的 SHA-256。它不包含具体项目的技术栈、业务规则或代码路径；项目特有规则由同仓库 AGENTS.md 维护。

## 1. 规则边界

- 本仓库的 AGENTS.md、AI-GOVERNANCE.md、项目 Spec、Contract、代码和测试共同构成工作上下文。
- 本文件只描述跨项目共同的工程治理规则。
- 项目特有架构、安全、技术栈、命令、目录和发布规则以本项目 AGENTS.md 为准。
- 业务规则以批准的 Spec、API/Event/Data Contract 和明确批准的需求变更为准。
- 不依赖父目录的 AGENTS.md、CLAUDE.md、~/.codex 或任何个人机器文件才能执行本规则。
- 规则冲突时，系统与安全红线优先；其后是数据正确性、批准的业务 Spec、项目 AGENTS.md 和其他最佳实践。

## 2. 正确性来源

开始任何任务前必须回答：

~~~text
What defines correctness for this task?
~~~

合法的业务真相来源按优先级为：

1. Approved / Active Spec；
2. 明确批准的需求变更；
3. API / Event / Data Contract；
4. Architecture / Design 约束；
5. 项目 AGENTS.md 中的项目规则。

以下内容不能自动定义业务正确性：

- 现有代码；
- 现有测试；
- README；
- 示例代码；
- 历史计划；
- Git 历史；
- AI 推断；
- 行业惯例。

如果找不到真相来源，必须将 Truth Source 标记为 undefined，进入需求澄清，不得直接实现。

## 3. 开工上下文

按任务需要读取：

1. 本仓库 AGENTS.md；
2. 项目架构和安全规则；
3. 相关模块 Spec；
4. API / Event / Data Contract；
5. 相关实现；
6. 相关测试；
7. 仅在需要历史原因时读取 ADR 或归档计划。

不要为了节省时间跳过直接相关的 Spec、Contract、测试或项目规则。不要一次加载无关的整个仓库。

## 4. 任务分类

每个任务先分类，不得默认所有问题都是代码 Bug：

~~~text
A. New Feature
B. Requirement Change
C. Implementation Bug
D. Missing Requirement
E. Incorrect Requirement
F. Architecture Limitation
G. Data Issue
H. External Dependency Issue
I. Non-behavioral Change
~~~

分类必须写入任务或 PR 记录。实现过程中如果分类发生变化，必须停止当前路径并重新规划。

## 5. 需求变更门禁

任何改变外部可见行为的修改都属于 Requirement Change，包括：

- 用户可见行为；
- API；
- Event；
- 状态；
- 权限；
- 金额；
- 业务计算；
- 数据保留；
- 默认策略；
- 通知；
- 状态转换；
- 第三方集成；
- 兼容性行为；
- 文件格式；
- 持久化模型。

处理顺序固定为：

~~~text
Change Proposal
→ 逐条澄清
→ 明确决策
→ 更新权威 Spec
→ 更新 Design / Contract
→ 重新规划
→ 实现
~~~

未确认的 Change Proposal 不是正式业务真相，不能作为实现依据。

## 6. Bug 和架构问题

Implementation Bug 的处理方式：

~~~text
复现 Expected / Actual
→ 对照 Approved Spec
→ 定位根因和影响面
→ 最小修复
→ 回归验证
~~~

禁止通过 catch 吞错、条件绕过、延迟、重试、复制另一套逻辑或兜底假数据掩盖根因。

如果 Spec 本身不正确，重分类为 Incorrect Requirement，停止普通 Bug 修复流程，先更新权威 Spec。

如果正确需求无法由现有架构安全实现，重分类为 Architecture Limitation，先写 Design Proposal、Impact Analysis 和 ADR，再更新 Contract、重新规划和实现。

## 7. Impact Analysis

行为变更实施前至少检查：

- Canonical Spec；
- Dependent Specs；
- Domain modules；
- State machines；
- Permissions；
- API/Event contracts；
- Data model / migrations；
- Backend；
- Frontend；
- Tests；
- Logging / monitoring；
- Compatibility / migration；
- Documentation。

输出：

~~~text
Source of truth:
Affected:
Possibly affected:
Not affected:
~~~

跨项目变更不得只在一个消费端仓库内完成。拥有共享 Contract 的仓库必须列出所有消费端，并链接对应同步变更。

## 8. 先更新知识再实现

正式业务行为变化：

- 先更新 Spec；
- 涉及架构时先更新 Design / Architecture / ADR；
- 涉及外部结构时先更新 API / Event / Data Contract；
- 然后才能修改实现、测试和文档。

不要为了让测试变绿而修改测试期望。只有权威需求已经正式变化时，才可以同步修改测试。

## 9. 文档同步

修改以下任一内容时，必须检查并按职责同步：

- API 路由；
- IPC 通道；
- Service 接口；
- Event；
- 文件格式；
- 数据 Schema；
- 目录或分层；
- 端口；
- 环境变量；
- 启动命令；
- 业务规则；
- 数据模型；
- 计费或权限；
- 部署；
- 模型下载；
- 发布流程；
- 旧入口或旧术语。

文档职责：

- AGENTS.md：工程规则、架构红线、命令和门禁；
- specs/：当前业务行为和契约；
- traceability：Requirement ID 到实现和测试的精确映射；
- domain map：架构事实和依赖；
- README / guides：入口、使用、部署和排障说明；
- plans：仍在实施的过程文档；
- ADR：历史决策和被拒方案；
- CONTEXT：领域术语。

README、计划、审查报告、对话摘要不能覆盖权威 Spec。

## 10. 代码质量

实现类变更完成前必须确认：

- 没有未引用的 import、变量、函数、分支、配置项或文件；
- 没有重复三次仍未抽取的逻辑；
- 没有为单一实现新增抽象层、工厂、策略、注册表或未来扩展点；
- 没有无证据的判空、catch 兜底、重试、降级或 fallback；
- 没有空函数、桩实现、未接通路径或 TODO 未实现占位；
- 没有明知项目已有实现仍重写一套；
- 新代码遵守本项目的分层和依赖方向；
- 有加载态时提交类入口不能重复触发；
- 没有为极低概率并发路径添加无证据的锁、定时器或状态机。

## 11. 数据、安全和不可逆操作

以下内容不得出现在对话、日志、Issue、PR 或提示词中：

- 生产密钥、API key、token、证书、私钥、数据库口令；
- 客户手机号、邮箱、地址、身份信息；
- 真实订单、支付流水和对账明细。

生产环境：

- 可以读取日志、SELECT、容器状态和非敏感配置；
- 不得执行 UPDATE、DELETE、迁移、部署、重启或生产配置写入；
- 这些操作只输出方案和命令，交由人执行。

未经明确授权不得执行：

- force push；
- 删除远端分支或 tag；
- 重写已推送历史；
- 清理或重置用户工作树；
- 覆盖无法恢复的数据。

## 12. Git 提交作者归属

项目禁止 AI、模型、Agent 或 Bot 作为 Git commit 的 author、committer 或 co-author 出现。

新提交禁止出现以下 trailer 或等价合作作者声明：

~~~text
Co-Authored-By:
Co-authored-by:
Co-Author:
Coauthor:
~~~

也禁止已知 AI/Bot 名称或服务域名出现在 author/committer 字段中，包括但不限于：

~~~text
Claude
GPT
ChatGPT
OpenAI
Anthropic
Codex
Copilot
Cursor
Codeium
Gemini
CommandCode
anthropic.com
openai.com
commandcode.ai
~~~

> 该清单与 `scripts/check-commit-attribution.sh` 的 KNOWN_AI_IDENTITY_REGEX 保持一致；变更须两处同步。

AI 参与只能记录在 PR、Issue、审查报告或任务总结中。

~~~text
Governance-Exception: ...
~~~

是 owner 审批记录，不是作者归属声明，可以继续使用。

历史提交不重写。检查新提交时只检查当前 PR 或 push 新增的 commit，不因历史旧记录失败。

## 13. 测试、审查和收尾

完成前必须：

- 运行与改动相关的真实验证命令；
- 不使用“应该通过”“已验证”等替代真实输出；
- 自审完整 diff；
- 清理调试代码、临时日志和无效注释；
- 检查错误处理、安全边界和相关文档；
- 搜索旧参数、旧状态、旧 API、旧 Event 和旧术语；
- 处理或明确记录每个残留引用；
- 对高风险、跨模块、权限、安全、数据和非显然 Bug 取得独立 reviewer 审查。

结束时输出：

~~~text
Classification:
Truth Source:
Changes:
Spec / Design / Contract Updates:
Tests:
Verification:
Remaining Risks / Follow-ups:
~~~

并逐项 Reconciliation：

~~~text
Spec:
Design:
Contract:
Code:
Tests:
~~~

任一项存在未解决问题，不得宣称任务完成。

<!-- END SHARED-AI-GOVERNANCE: __BASELINE_VERSION__ -->
