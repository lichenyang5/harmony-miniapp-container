# VK：本项目接入范围

当前宿主使用默认 `new VkAdapter()`。网页登录由 VK 处理，已注册请求经 `HosBridge` 原生代理执行，其余请求继续交给 VK。原生鉴权回调、商业广告及支付不启用。

必须从配置的 `https://vk.ru/app<ID>` 打开，经过真实 VK 顶层页面与 Mini App iframe 验证。独立访问一个普通 H5 测试页不等于通过完整 VK 链路。

## 首版验收 API

| API | 实现与预期 |
| --- | --- |
| `VKWebAppOpenCodeReader` | Scan Kit 系统页，返回 `code_data`，保留 request_id 与来源路由 |
| `VKWebAppTapticSelectionChanged` | 原生轻触振动，返回 result |
| `VKWebAppTapticImpactOccurred` | 原生振动，接受 light/medium/heavy，非法值返回 client 5 |
| `VKWebAppClose` | 释放当前容器并通知宿主返回列表 |

宿主声明 INTERNET、VIBRATE；系统扫码页不额外复制相机权限。真机扫码取消应按现有 VK 约定返回 User denied，后台调用、重复调用及能力不支持有各自错误映射。

页面代次、请求关联及资源释放随 SDK 保留。消息来源和启动参数检查不等于密码学验签，不提供进程或 Cookie 隔离。

当前候选已在真机完成官方登录并进入实际测试中心，振动成功回包、非法参数错误、扫码取消/重试及成功识码文本回传均已验证。测试使用实际小程序里的对应按钮；[最小网页](../examples/README.md) 是可选联调资源。

[公共接入](README.md) · [验证记录](../docs/validation.md)
