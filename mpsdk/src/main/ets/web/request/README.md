# Web 资源请求处理

`WebRequestDispatcher` 是内部同步分发器，不解析 URL、不代发 HTTP、不依赖 Session。处理器的注册、单次续传、重入失效和清理语义参考相邻的 `WebSchemeDispatcher`。

Session 按 SDK Binding 工厂、宿主工厂的顺序收集处理器，id 在整条链中唯一。每次挂载创建独立实例，文档切换 reset，关闭 dispose；同一 appId 的多个容器不共享处理器。

按数组顺序调用 supports，匹配后调用 handle。`chain.proceed()` 在当前同步 handle 中只能调用一次；上游可检查下游结果并替换响应。直接返回 PASS 停止整条链，不隐式执行后续处理器。链末尾返回 PASS。

`WebRequestDecision.respond(response)` 返回自定义 WebResourceResponse；PASS 转为 onInterceptRequest 的 undefined；BLOCK 转为空 403。异常、重复或迟到续传、分发中上下文失效均 BLOCK；普通参数和返回类型由 ArkTS 编译器约束。注册失败释放整批对象，单个清理失败不阻断其他清理。

异步响应必须同步返回未就绪的 WebResourceResponse，后续填充并标记 ready。处理器负责超时及 reset/dispose 时终止挂起响应和任务；分发器不拥有响应中的异步操作。

该机制不是服务端响应修改回调：需要处理器自行获取并构造响应。onInterceptRequest 不能直接读取 POST body，也不保证收到已被 CSP 拦截的请求；需要请求体时评估 WebSchemeHandler。
