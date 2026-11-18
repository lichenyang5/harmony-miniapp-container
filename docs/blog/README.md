# HarmonyOS 小程序容器实战系列

这组文章记录将已有 AtomicMPSDK 集成到新 HarmonyOS 宿主的过程，围绕独立 HAR、LINE WEB、VK 官方网页登录、原生桥接和真机业务验证展开。文章按掘金技术实战的形式编写，包含问题背景、实际实现、代码片段、排障过程和适用边界。

编写日期为 2026-11-18，代码基线为 [`showcase-v1.0.0`](https://github.com/lichenyang5/harmony-miniapp-container/tree/showcase-v1.0.0)，设备验收与录制发生于 2026-11-16。文中的“我”对应本项目集成工作的作者；原 SDK 的会话、协议和 Handler 均按复用实现介绍。

| 顺序 | 完整文章 | 建议标签 | 主要回答的问题 |
| --- | --- | --- | --- |
| 01 | [从新宿主到 LINE VK 业务闭环](01-project-and-architecture.md) | HarmonyOS、ArkTS、架构 | 项目做了什么，分层如何安排，哪些工作是本次新增 |
| 02 | [独立 HAR 构建与宿主集成](02-har-build-and-integration.md) | HarmonyOS、工程化、SDK | 为什么源码能跑还不够，如何切换依赖并处理构建失败 |
| 03 | [VK 官方网页登录与登录态复用](03-vk-login-and-identity.md) | HarmonyOS、WebView、登录 | 谁负责登录，登录后如何回到小程序，iframe 身份有什么用 |
| 04 | [LINE WEB 模式与原生扫码联调](04-line-web-and-scan.md) | HarmonyOS、JavaScript、调试 | WEB 与 CLIENT 有何区别，为什么初始化成功却不能扫码 |
| 05 | [JSBridge 回包与容器生命周期](05-bridge-navigation-and-lifecycle.md) | HarmonyOS、异步、WebView | 请求如何关联，页面切换后如何处理迟到结果，返回与关闭如何区分 |
| 06 | [真实业务验收与面试展示](06-business-validation-and-showcase.md) | HarmonyOS、测试、项目实战 | 如何从 API 测试进入业务流程，怎样交付可下载的展示材料 |

每篇可以独立阅读。想先理解登录，直接读第 03、04 篇；准备源码面试，优先读第 02、05 篇。

## 发布时的使用方式

正文已经保存在各 Markdown 文件中，可复制到掘金编辑器。代码片段均标明是源码节选还是原理示意；源码链接固定到已有标签，避免读者以后点到变化后的实现。发布后可将文章间的本地链接替换成对应掘金链接。

图使用 Mermaid 保存。若编辑器不渲染 Mermaid，可将图导出为图片后插入，或保留旁边的文字链路。系列不依赖图片才能读懂，也没有使用账号、Token 或真实登录回调参数作为示例。

建议按编号发布。第 01 篇建立背景，第 02 篇讲工程交付，第 03、04 篇讲厂商差异，第 05 篇深入异步与资源，第 06 篇给出可运行的业务证据。

## 登录部分的阅读要点

VK 的网页登录由官方页面处理；已有 SDK 在部分移动网页场景保存待返回地址，观察页面跳转，再识别带启动参数的小程序 iframe。页面中的登录标志只用于导航辅助，不能作为账号认证凭据，`IDENTITY_ACCEPTED` 也不代表完成了密码学验签。当前宿主未提供原生 Token 授权回调，原生 AuthToken Handler 也未注册接管。

LINE 当前显式使用 WEB 模式，默认 `forceLogin` 为 false。SDK 保留官方网页登录辅助和 CLIENT 账号实现，但存在源码不代表本项目已经启用和验收。天气业务未要求登录，不能用它证明 LINE 登录成功。第 04 篇还解释了 SDK 中上下文归一化补丁的存在及其兼容风险，避免把“没有修改 isInClient”误解为“完全没有页面兼容脚本”。

## 项目与演示

- [GitHub 仓库](https://github.com/lichenyang5/harmony-miniapp-container)
- [视频与完整展示包 Release](https://github.com/lichenyang5/harmony-miniapp-container/releases/tag/showcase-v1.0.0)
- [项目架构与贡献边界](../portfolio.md)
- [分层验证记录](../validation.md)
- [面试讲解稿](../../showcase/interview-script.md)

文章使用的构建、测试与真机结论以以上基线为准，远端业务界面变化后需要重新检查。当前交付为普通 HAP，`installationFree` 为 false，最低 API 24，在 API 26 真机验证；系列没有将其表述为已发布的元服务产品。
