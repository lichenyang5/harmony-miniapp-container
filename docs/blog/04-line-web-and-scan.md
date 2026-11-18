# 鸿蒙小程序容器实战 04 LINE WEB 模式与原生扫码联调

接入 LINE 时，我遇到的一个典型现象是：测试页面已经显示 LIFF 初始化完成，扫码按钮却仍然不能使用。

这个问题适合说明容器联调的一条思路：先判断请求有没有真正走到桥接层，再检查原生实现。页面主动拦截、代理未安装和系统能力失败，需要不同的处理方法。

## 当前使用的是 WEB 模式

宿主显式创建适配器：

```typescript
new LineAdapter({ mode: LineMode.WEB })
```

已有 SDK 同时保留 WEB、WEB_HOOK 和 CLIENT 实现。本项目选择 WEB 运行路径，使用官方网页与兼容脚本，并把部分方法代理到原生。

其中 `openWindow`、`closeWindow`、`scanCode` 和 `scanCodeV2` 注册了对应处理。不能因为 SDK 目录里有更多 Handler，就把它们都算作当前已验证能力。

## LIFF 初始化与账号登录分别判断

`liff.init()` 完成，代表 LIFF 初始化流程完成；`liff.isLoggedIn()` 查询登录状态；`liff.isInClient()` 用于判断是否处于 LIFF browser。它们回答不同的问题，具体使用方式见 [LIFF API reference](https://developers.line.biz/en/reference/liff/)。

对于自己控制的 LIFF 网页，官方提供 `liff.login()` 以及初始化时的 `withLoginOnExternalBrowser` 选项，用于外部浏览器登录流程，见 [Developing a LIFF app](https://developers.line.biz/en/docs/liff/developing-liff-apps/)。

本项目加载的是已有第三方小程序，因此不能假设可以任意修改它的初始化代码。

当前 `LineAdapter` 默认 `forceLogin: false`。SDK 中虽有等待 LIFF 就绪后调用官方 `liff.login()` 的辅助脚本，但只有配置强制登录时才加入。当前宿主没有启用它。

另一个容易误判的点是 `LineAdapter.login()`。在当前源码中，非 CLIENT 模式的 `requestLogin()` 返回已完成的结果。因此在 WEB 模式下调用它，并不能证明发生过真实账号认证。

这也是为什么我把本次 LINE 结果写成“WEB 原生扫码通过，天气业务无需登录浏览通过”，而没有写成“LINE 登录已接入成功”。

读源码时还会看到 LIFF 协议上下文中的 `featureToken`。SDK 按现有策略核对已建立的上下文，它与账号登录使用的 access token 职责不同；`LineAppState` 的注释也明确说明这不是原生账号状态。不能因为桥接请求通过，就推导出账号认证已完成。

## 从按钮到系统扫码之间有两道门

当前远端 API 测试台会先检查 `inLineClient`。在 WEB 环境中，这个条件不满足，页面就不会继续调用扫码 API。

```text
点击测试台按钮
        ↓
测试台检查客户端环境
        ↓ 不满足
页面提前结束

此时原生扫码 Handler 可能一次都没有收到请求
```

如果只看按钮失败，很容易把时间花在权限或 Scan Kit 上。更有效的排查顺序是先确认桥层是否记录到请求，再判断系统能力是否被调用。

我会把现象与执行阶段对应起来，而不是把所有失败都归为“LINE 不兼容”：

| 观察到的状态 | 下一步检查 |
| --- | --- |
| LIFF 尚未初始化完成 | 先检查入口、页面加载与初始化结果 |
| 测试台按钮提示客户端条件不满足，桥层没有对应请求 | 检查页面前置判断，用受限诊断入口验证真实 API |
| 已有 handlerStarted，但系统页未正常完成 | 检查前台状态、占用与能力错误 |
| 已有 handlerCompleted，但网页未显示结果 | 检查回包提交、文档变化与页面接收 |

这些状态用于选择下一层排查；单条日志本身不证明后续阶段成功。扫码成功仍需看到网页中的实际文本。

## 用受限诊断入口验证真实 API

我的处理方式是增加宿主 Debug 面板。它绕开的是测试台按钮自己的前置判断，点击后仍调用真实 `liff.scanCodeV2()`。

面板只在 Debug 构建、LINE 厂商且 ID 为选定测试应用时注入。页面内还会等待 `liff.ready`，核对 `liff.getContext().liffId`，用户点击后才启动扫描。

下面是宿主中的条件，按源码排版：

```typescript
if (BuildProfile.DEBUG &&
    params.vendor === 'line' &&
    params.appId === '2012241484-PibjtMII') {
  app.jsOnDocEnd = lineBridgeDiagnostics(params.appId);
}
```

面板调用的核心片段也很直接：

```javascript
var value = await liff.scanCodeV2();
result.textContent = '扫码结果 / Result: ' + value.value;
```

没有返回预置文本，也没有把 `liff.isInClient()` 改成 true。天气业务入口和 Release 构建不注入这个面板，避免联调工具影响正常业务页面。

## 页面兼容补丁需要如实说明

“没有修改 isInClient”并不意味着 SDK 完全不修改页面环境。

当前 WEB 路径使用兼容 UA，还会执行上下文归一化脚本：读取 LIFF 存储中的 context，将 `external` 类型按 `webContextType` 归一化；当前默认值为 `none`。源码还包装了 `Storage.prototype.setItem` 处理后续写入。

这属于已有 SDK 的兼容措施，与我新增的扫码面板是两件事。它依赖 LIFF 的存储组织，未来版本变化时可能失效，需要独立回归。公开介绍项目时，应该把代理、兼容补丁和诊断入口分别说明。

原生代理的存在也不能推导出整个宿主等价于官方 LINE 客户端。

## 原生扫码如何恢复成 LINE 结果

当前运行的 WEB 扩展 Handler 是 `ExtScanCodeV2Handler`。它通过共用的 `CodeReaderTools` 调用系统 Scan Kit，指定 QR_CODE，然后把结果组织成 LINE 方法需要的对象。

```text
liff.scanCodeV2
    → SDK 网页代理
    → LineBridgeProxy
    → ExtScanCodeV2Handler
    → 系统扫码页
    → { value: 实际识别文本 }
    → 网页 Promise 完成
```

本项目的 `scanCodeV2` 取消分支返回 LIFF 错误，真机页面显示 `UNKNOWN`。旧版 `scanCode` 在源码中有不同取消语义，不能把一个方法的测试结论直接套给另一个方法。

系统结果也只作为字符串回传，不自动打开二维码中的链接。扫描内容和后续业务操作属于两步。

## 验证要同时观察三处

一次扫码成功，我会检查系统扫码页面确实打开、SDK 完成处理与回包、网页显示真实识别文本。取消后还会重试，确认下一次调用能够再次启动系统页。

测试二维码使用无个人信息的文本。公开文章和演示只保留必要的状态，避免展示真实回调参数、账号或凭据。

这次真机验证支持选定 LINE WEB 扩展扫码链路，不代表其他 LINE API 或 CLIENT 账号模式已通过。

## 天气业务怎样补上使用场景

随后我接入 Yahoo! 天气小程序，完成公开地区搜索、保存、今日与明日切换、刷新、关闭和重开偏好恢复。

这次业务没有要求登录，不能把地区偏好恢复解释为账号云同步。业务页也没有扫码诊断面板，业务承载和原生扫码使用各自的证据。

这里还有一个导航细节：日期切换只改变页内状态，没有建立可回退的网页历史。因此当前从业务根页返回会退出容器，不能承诺返回键逐步撤销每次日期切换。

## 源码与下一篇

- [LINE Adapter 与默认配置](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/vendors/line/LineAdapter.ets)
- [WEB 模式初始化与 Handler 注册](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/vendors/line/LineVendor.ets)
- [Debug 诊断入口](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/entry/src/main/ets/model/LineBridgeDiagnostics.ets)
- [scanCodeV2 扩展 Handler](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/vendors/line/handlers/ext/ExtScanCodeV2Handler.ets)
- [下一篇 JSBridge 回包与容器生命周期](https://github.com/lichenyang5/harmony-miniapp-container/blob/main/docs/blog/05-bridge-navigation-and-lifecycle.md)
