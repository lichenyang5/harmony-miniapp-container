# mpsdk HAR

从 AtomicMPSDK 迁入的在线 H5 小程序容器 SDK，包含 LINE 与 VK 适配。当前工程验证范围见 [根 README](../README.md) 和 [验证记录](../docs/validation.md)。原账号协议专项资料和旧宿主未迁入，不以本次迁移代表这些功能已验证。

## 接入

通过根 `tools/build.ps1` 生成 HAR。宿主模块依赖 `file:../libs/mpsdk.har`，声明 INTERNET 和选定能力需要的权限。

在 `UIAbility.onCreate` 的异步业务之前调用 `MiniAppSDK.initialize(this.context.getApplicationContext())`。SDK 自动监听宿主生命周期，无需重复转发 onForeground/onBackground。

```typescript
import { MiniAppContainer, MiniAppSDK, MiniAppInfo, MiniAppNavigationController } from 'mpsdk';
```

宿主向 `MiniAppContainer` 提供 `appId`、`vendor`、`url` 和可选 Adapter。通过 `onNavigationReady` 保存导航句柄，在 `onClose` 退出承载页，在 `onError` 展示稳定错误。实际接入见 `entry/src/main/ets/pages/MiniAppPage.ets`。

## 边界

- 每次挂载独立 Session、Binding 和导航控制器，同一 appId 不作为实例唯一键。
- 切换启动信息需移除旧容器，再创建新容器。
- `goBack()` 处理网页历史，`handleBackPress()` 保留厂商返回策略，`refresh()` 刷新当前页面。`goHome()` 指小程序入口，不是宿主首页。
- `onNavigationReady` 仅代表控制器绑定，不代表登录或网页加载完成。
- SDK 校验会话和 documentId，丢弃过期异步结果；这不代表已经取消系统扫码页。
- `MiniAppLifecycleController` 支持宿主选择状态；本项目只使用单实例页面，不启用保活栈。
- `jsOnDocStart` / `jsOnDocEnd` 为宿主脚本配置；必需厂商初始化脚本保留。当前宿主添加 VK 加载图标替换，并仅在 Debug 下添加 LINE 扫码诊断面板。
- 默认不忽略 SSL 错误；宿主禁用网页定位。来源判断不等于签名验证或网页存储/进程隔离。

完整公共导出以 `Index.ets` 为准。内部注册表、Binding、日志配置与能力工具不作为宿主 API。

## 结构与验证

`core` 管理初始化与会话，`web` 管理 ArkWeb、脚本、请求和 scheme，`vendors` 适配协议，`capabilities` 提供原生能力，`logging/utils` 提供基础支持。资源必须随 HAR 一起打包。

运行根迁移套件验证本项目范围；保留的 `tests/vk-response.test.cjs` 有原始缺失引用，不能作为当前绿色入口。Node 使用平台替身，HAR 构建与 UnitTestBuild 仅证明编译，真机登录及硬件调用需独立验收。

[LINE 接入范围](readme_line.md) · [VK 接入范围](readme_vk.md)
