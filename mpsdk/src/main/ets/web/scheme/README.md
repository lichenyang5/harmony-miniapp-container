# WebView 协议处理

`WebSchemeDispatcher` 是 SDK 内部的 WebView scheme 分发能力，不负责页面路由、浏览历史或窗口 UI。模块不依赖
MiniAppSession、VendorBinding 或 ArkWeb 控件，也没有新增 HAR 公共导出。

普通 WebView 可以直接创建 `WebSchemeHandler<WebSchemeRequest>[]` 和对应分发器。请求只含原始 `url`、`isMainFrame`
；调用方可通过泛型扩展自己的上下文字段，分发器不解释它们。

```typescript
const dispatcher = new WebSchemeDispatcher<WebSchemeRequest>(handlers);
const decision = dispatcher.dispatch({ url: address, isMainFrame: true });
const intercept = decision !== WebSchemeDecision.PASS;
```

- `PASS`：交回 WebView，不再自动调用后续处理器。
- `CONSUME`：请求已接管，停止分发并拦截 WebView 加载。
- `BLOCK`：拒绝请求，停止分发并拦截 WebView 加载。

处理器按创建时的顺序注册，id 必须唯一。分发器先调用 `supports(request): boolean`，仅在返回 true 时调用 `handle(request, chain)`。
匹配方法必须同步且无副作用；同一处理器可匹配多种协议，也可按 host、path 等条件选择请求。分发器保留原始请求，不解析 URL，
全部不支持时放行。匹配或处理异常、非法返回值（包括 Promise）均按 BLOCK 处理；异步操作由处理器自行启动，但必须同步返回处理决定。

处理器不处理当前请求时，使用 `return chain.proceed()` 从下一个处理器继续匹配；下游结果沿调用链返回，链末尾为 PASS。
不再将返回 PASS 隐式解释为续传，避免显式续传后重复调用下游。链始终传递原请求，不允许替换地址或上下文。

```typescript
handle(request: WebSchemeRequest, chain: WebSchemeChain): WebSchemeDecision {
  if (!this.acceptsRoute(request.url)) {
    return chain.proceed();
  }
  this.openTarget(request.url);
  return WebSchemeDecision.CONSUME;
}
```

每个 chain 只允许在当前 handle 的同步调用内续传一次。重复或迟到调用返回 BLOCK，不再执行下游；重复调用也会使当前处理结果变为 BLOCK。
处理结束时清除续传闭包，保存 chain 不会继续持有请求上下文。链只控制本次同步分发，不等待或去重原生异步操作。

每个 WebView 使用独立实例。调用方负责在上下文失效时调用 `reset()`，在释放时调用 `dispose()`；reset 保留注册，dispose
幂等。匹配或处理期间发生 reset/dispose 会阻止旧请求继续。单个清理钩子失败不影响其他处理器，构造失败也会释放传入的处理器。

小程序通过 `SessionWebSchemeRequest` 增加 documentId，由 Session 检查页面有效性，并在文档切换及关闭时驱动生命周期。厂商使用
`VendorBinding.createWebSchemeHandlers()` 创建本次会话的处理器；这些接入约定不属于通用模块的创建前提。
