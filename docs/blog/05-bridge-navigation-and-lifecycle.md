# 鸿蒙小程序容器实战 05 JSBridge 回包与容器生命周期

网页调用原生能力，最直观的演示是点一下按钮，系统扫码页打开，再把文本显示回网页。

继续往下做，就会遇到异步边界：用户在扫码过程中离开容器，网页刷新后换了文档，或者快速打开下一个应用。系统能力完成时，原来的接收页面可能已经不存在。

本项目复用原 SDK 的请求关联、文档代次与会话机制。我负责把它们接入新宿主，并用回归与真机流程验证选定行为。本文沿着一次请求说明这套机制为什么需要这些状态。

## 请求进入原生之前先确定路由

以 VK 扫码为例，小程序通过网页协议向顶层承载页发送消息。下面只是结构示意，ID 和扫码文本均为测试示例：

```json
{
  "type": "vk-connect",
  "handler": "VKWebAppOpenCodeReader",
  "params": { "request_id": 42 }
}
```

SDK 在接收文档中验证消息来源，随后调用原生 `HosBridge.onInterceptRequest`。`VkBridgeProtocol` 解析协议，`VkEventRegistry` 查找已注册 Handler。

找到 Handler 才原生接管；普通未接管请求继续原有网页处理路径。关闭等具有宿主副作用的方法还有单独的失效和格式保护，不能把全部方法概括成无条件透传。

原生方法完成后，结果仍按 VK 事件格式回去，而不是只返回一个裸字符串：

```json
{
  "type": "VKWebAppOpenCodeReaderResult",
  "data": { "code_data": "INTERVIEW-DEMO", "request_id": 42 }
}
```

小程序原本等待的请求关联关系因此可以继续工作。VK Bridge 的公开调用方式可参考 [官方 vk-bridge 仓库](https://github.com/VKCOM/vk-bridge/blob/master/packages/core/README.md)。

## request_id 与 replyId 分别解决什么问题

`request_id` 属于厂商请求协议，用于业务侧关联结果。SDK 网页脚本还会生成一个页面内的 `replyId`，用它保存当前消息的来源窗口、origin 和等待状态。

```text
request_id → 厂商协议中的请求关联
replyId    → 当前网页脚本保存的回包路由
```

这两个 ID 没有必要相同。一个服务于上层 API，另一个服务于跨窗口消息投递。

回包时，脚本从 Map 取出保存的来源，移除等待项，再向该窗口的已保存 origin 发送。页面隐藏离开时会清理等待项和计时器。

这样可以避免一个原生结果被错误地发送给另一个 iframe，也避免把后来的页面误当成原请求页面。

## 系统能力结果还要转换厂商语义

系统扫码返回的文本，对 LINE 和 VK 来说字段不同：

| 场景 | 当前适配结果 |
| --- | --- |
| LINE scanCodeV2 成功 | `{ value }` |
| VK 扫码成功 | `{ code_data }`，再包装事件与关联 ID |
| LINE scanCodeV2 用户取消 | LIFF 错误，当前页面显示 UNKNOWN |
| VK 扫码用户取消 | client_error，error_code 为 4 |
| VK 振动 style 非法 | client_error，error_code 为 5 |

所以共用 `CodeReaderTools` 很合理，但不能让它负责所有平台的错误外壳。系统能力层给出内部结果与错误，厂商 Handler 再映射协议。

这也让测试可以分层：能力层检查占用和系统异常，协议层检查字段与错误，最终再用真机确认设备行为。

当前宿主只声明 INTERNET 和 VIBRATE。扫码使用系统 Scan Kit 页面，没有照搬源工程的相机、定位和麦克风等权限。其他能力即便仍在 SDK 中，也需要根据实际调用单独接入和验收。

## 文档没变和会话没关都要检查

`VkBridgeProxy.dispatch` 在异步处理前保存当前 Session、documentId 和 documentGeneration；处理完成后再次核对。

源码中的关键判断如下：

```typescript
if (this.session !== session ||
    session.getDocumentId() !== documentId ||
    this.documentGeneration !== generation ||
    !this.registry.isActiveFor(session)) {
  SdkLogger.warn(TAG, 'responseDropped', logContext);
  return;
}
```

只检查“组件还在不在”不够。同一个容器可能已经刷新到另一个文档；只检查 URL 也不够，同一个地址可以属于两次不同的加载。

LINE 有自己的文档就绪和有效性检查，在 Handler 完成后确认原页面仍然有效，再提交 LIFF 回包。两种厂商实现不同，但都需要将异步结果限制在原请求上下文中。

当前迟到结果有平台替身回归。销毁过程中真实系统扫码结果迟到的设备场景仍需补测，不能把代码判断和自动回归写成全部真机情形均已覆盖。

## dispose 不等于系统调用立即结束

扫码页还有一个更细的资源问题。`CodeReaderTools` 使用 UIAbilityContext 级共享占用集合，防止同一宿主同时打开多个系统扫码调用。

调用开始时占用，真正的原生调用结束后在 `finally` 中释放。`dispose()` 只标记实例失效，不提前释放共享占用。

原因很直接：网页被销毁，不代表系统扫码页已经结束。如果销毁时就释放占用，下一个容器可能马上启动第二次调用，与尚未结束的第一次重叠。

因此需要同时处理两件事：旧结果不得投递给新页面，系统能力占用也不能过早释放。

## 宿主回调也可能晚到

新宿主的 `MiniAppPage` 使用 `active` 标志保护导航就绪、错误和关闭回调。

页面关闭时先标记失效，再移除 app 和导航引用、返回路由。后续到达的回调检查状态，避免再次修改已退出的页面。

这层保护负责宿主 UI；SDK 的会话与文档检查负责桥接上下文。两者各守自己的状态，不需要让宿主重复实现整套厂商协议。

## 返回与关闭的语义分别处理

宿主顶部返回与系统返回都会先交给导航控制器。不能简单地在任何时刻调用 WebView 后退，否则可能从小程序返回到登录页或平台首页。

VK 导航会检查当前和前一条历史是否仍属于同一小程序，并区分三个结果：

| 结果 | 当前处理 |
| --- | --- |
| BACKED | 已提交内部后退，或合并了短时间重复后退 |
| BOUNDARY | 到达小程序边界，请求关闭会话 |
| UNAVAILABLE | 当前无法安全判断，不贸然退到未知页面 |

这里 `goBack()` 返回 true 表示消费了请求，不保证已经发生一次可见的历史后退。读调用方代码时要保留这个语义。

LINE 当前优先处理可关闭的子窗口，再使用普通网页历史；根页没有可返回历史时，宿主退出容器。天气的今日与明日切换属于页内状态，因此不一定对应可退的一条历史。

## 关闭时沿资源所有权清理

`MiniAppContainer` 移除时关闭 Session；`MiniAppView.release` 还会停止加载、释放脚本安装器、取消生命周期监听、释放媒体权限对象、解绑导航，并尝试移除注册代理。

重复释放通过已有幂等判断处理。宿主主动关闭和 SDK 主动关闭可能接近发生，不能要求调用方永远只触发一次清理。

真机日志中的 `WebView.released`、`Session.closed` 有助于确认清理路径执行。但“执行过释放”与“长期无内存泄漏”是不同结论，后者仍需持续测量。

## 源码与下一篇

- [VK 请求处理与回包有效性](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/vendors/vk/VkBridgeProxy.ets)
- [共用扫码能力与占用](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/capabilities/media/CodeReaderTools.ets)
- [VK 导航边界](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/vendors/vk/VkNavigationController.ets)
- [WebView 资源释放](https://github.com/lichenyang5/harmony-miniapp-container/blob/showcase-v1.0.0/mpsdk/src/main/ets/web/MiniAppView.ets)
- [下一篇 真实业务验收与面试展示](06-business-validation-and-showcase.md)
