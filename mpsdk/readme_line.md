# LINE：本项目接入范围

当前宿主显式使用 `new LineAdapter({ mode: LineMode.WEB })`。WEB_HOOK 和 CLIENT 实现保留为 SDK 静态依赖，不列为本次运行验收范围。

WEB 模式使用兼容 UA 和官方网页登录，代理 `openWindow`、`closeWindow`、`scanCode`、`scanCodeV2` 到原生。SDK 不因代理而把 `liff.isInClient()` 变成 true，也不以宿主身份伪造官方登录或 Token。

选择真实 LIFF ID，并使用 `https://miniapp.line.me/<ID>` 或 `https://liff.line.me/<ID>`。引导页跳转由 SDK 处理。当前 API 测试入口已显示 LIFF 初始化完成，但未登录；另已接入 Yahoo! 天气业务入口，完成无需登录的地区搜索、保存、预报切换和容器导航验证，详见 [业务操作卡](../docs/line-business-demo.md)。

## 扫码验证

使用 `liff.scanCodeV2()` 真实调用。原生通过系统 Scan Kit 仅扫描 QR，成功返回 `{ value }`，取消以 LIFF 错误拒绝，不伪造扫码文本。重复调用受共享占用限制，切页/销毁后迟到结果不回传。

现有远端测试台有 `inLineClient` 前置条件，会在调用前拒绝 WEB 模式。当前 Debug 宿主仅对 API 测试入口 `2012241484-PibjtMII` 添加独立扫码面板，在 LIFF 初始化且 ID 匹配后显示，用户点击才调用真实 API，不改变环境标识。Release 和业务入口不添加。该面板仅用于联调，结果不写日志。

自有 Endpoint 也可使用 [最小测试页](../examples/README.md)，避免测试台自身的客户端条件掩盖扩展桥接。

CLIENT 模式的账号恢复、注册、LIFF 发行、授权及原生子窗口不在本次验收范围。SDK 内部 browser/scheme/window 生命周期仍随模块保留，不代表全部经过设备验证。

[公共接入](README.md) · [验证记录](../docs/validation.md)
