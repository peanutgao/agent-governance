# 开源选型与封装目录地图

本文件是项目技术栈与可复用能力目录的精简地图。编写业务代码前先查此表，并直接检索对应封装/公共目录复用既有实现。

## 1. 已批准开源库与封装目录

| 能力域 | 批准开源库 | 项目封装 / 公共目录 | 禁止行为（用原生 Linter 拦截） |
| --- | --- | --- | --- |
| Design Token / 主题 | _按项目填写_ | _如 `src/tokens/`_ | 业务层禁止硬编码颜色/间距/字号 |
| 基础 UI 组件 | _按项目填写_ | _如 `src/components/ui/`_ | 业务层禁止直引底层 UI 库绕过封装 |
| 网络请求 | _按项目填写_ | _如 `src/infra/http/`_ | 禁止裸调 `fetch` / `URLSession.shared` / `new RestTemplate()` |
| 日志与错误模型 | _按项目填写_ | _如 `src/infra/logger/`_ | 禁止散落原始打印或吞错 |
| 公共工具 / Hooks | _按项目填写_ | _如 `src/utils/`, `src/hooks/`_ | 禁止重复造已有工具函数 |

## 2. 依赖准入与防自研

- 不自研 HTTP 客户端、DI 容器、事件总线、复杂校验器、日期时间库或认证加密协议；优先采用成熟开源方案。
- 引入新第三方依赖前按 `AI-GOVERNANCE.md` §13 给出候选对比，更新本表（或 ADR）并通过 `.github/CODEOWNERS` 评审。

## 3. 原生 Linter 防漂移推荐配置（接入 CI）

- **Web / TS**：ESLint `no-restricted-imports`（放行封装目录、报错文案指路封装入口）+ Stylelint `color-no-hex` / `var(--token)`
- **Java**：Checkstyle `IllegalImport` / `RegexpSinglelineJava`（或 ArchUnit 分层测试）
- **iOS Swift**：SwiftLint `custom_rules`（禁硬编码 `Color(`/`UIColor(red:`、禁裸 `URLSession.shared`）
- **Kotlin**：Detekt `ForbiddenImport` / `ForbiddenMethodCall`（含 Compose/XML Token 与组件封装防绕过）
