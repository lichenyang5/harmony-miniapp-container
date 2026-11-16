# 迁移范围与来源

## 本次工程边界

目标是普通 API 24 HAP 接入独立 HAR，验证选定 LINE/VK 小程序及少量原生能力，不进行上架、完整 API 兼容或 LINE CLIENT 账号协议联调。

SDK 来源为已有 AtomicMPSDK 工程中的 `atomicmpsdk/mpsdk`。保留 `Index.ets`、`src`、`tests`、模块构建配置和厂商代码；工具链模型版本从 6.0.2 调整为 6.1.1。SDK 业务实现未因迁移重写。公共接入文档已按本工程路径重新整理，原专项逆向资料、接口报告和旧宿主未迁入。

新增工作包括：精简宿主、目录与路由校验、LINE WEB / VK Adapter 接入、应用级初始化、导航与退出处理、签名隔离、打包 HAR 构建流程、选定能力回归及网页联调样例。介绍项目时需区分已有 SDK 实现与本次集成工作。

## 保留与排除

- 保留 core、web、vendors、capabilities、utils、logging 和 SDK 资源，避免在迁移阶段同时裁剪静态依赖。
- 仅启用 LINE WEB 和默认 VK Adapter。LINE 原生注册/账号 RPC、支付、广告、健康与传感器等不在验收范围。
- 未引入 AtomicPlatform、atmicwebsdk、AtomicPlatformScript、卡片、元服务胶囊、翻译、vConsole、广告 UI、完整目录或 LINE 保活栈。
- SDK 未声明其他业务工程依赖，宿主不用源仓库绝对路径。

## 配置剥离

- 保留目标工程 AppScope 和 API 24 产品配置、`installationFree: false`。
- 源仓库的签名、证书、设备信息、登录态和 IDE 配置不迁移。
- 目标工程原有签名迁至 `.local/signing.json`，原配置备份位于 `.local/build-profile.json5`，两者均被 Git 忽略。模板只含占位符。
- 此操作不改写迁移前的 Git 历史。旧提交中已存在的配置不因此被历史删除。
- 构建生成的 BuildProfile、缓存、HAP 和 HAR 不作为源码提交；发布或分享 HAR 时需单独明确版本和构建模式。
- OHPM 根据当前源码/打包依赖重新生成本地解析结果，不迁入源依赖目录。

## 后续维护

在 `mpsdk` 修改 SDK 后运行根构建脚本重新打包。不要修改 `oh_modules` 的解包副本，也不要修改生成的 BuildProfile。先保留可工作的源码，再通过打包 HAR 验证消费行为。

源 SDK 的既有测试有缺失引用、旧断言以及旧宿主路径耦合，未通过删除断言或伪造旧宿主来制造全量通过。本项目单独提供有明确范围的迁移回归；原测试保留以便后续修复。
