# 验证记录

日期：2026-11-16。以下仅描述本次执行的证据，不把平台替身或编译通过当作真机能力通过。

## 已执行

| 项目 | 结果 | 边界 |
| --- | --- | --- |
| 源 SDK 汇总测试入口 | 启动失败 | 引用缺失的 `mini-app-navigateTo.test.cjs` |
| 源基线选定测试 | 30/31 通过 | `line-scan-code` 的旧断言要求 WEB 无代理，与现实现不一致 |
| 源 `supported-handlers` 专项 | 16/20 通过 | 文档切换缓存、两个 AndroidBridge 缓存测试、排除名单测试失败 |
| 本工程迁移回归 | 44/44 通过 | 真实 SDK/注入脚本 + 平台替身，不证明设备硬件；含 4 项 VK 图标替换范围与清理测试 |
| API 24 HAR 构建 | 通过 | 生成 bytecode HAR、保留 normalized OHM URL |
| 源码 HAR 宿主构建 | 通过 | 使用本地独立签名配置 |
| 打包 HAR 宿主构建 | 通过 | `entry` 依赖 `libs/mpsdk.har`，不依赖源码模块路径 |
| ArkTS `UnitTestBuild` | 通过 | 仅测试编译，未在真机执行 Hypium 套件 |
| 真机安装、启动与首页 | 通过 | 已连接设备 API 26；应用最低 API 24 |
| 真机 VK 登录和小程序加载 | 通过 | 用户完成官方登录，目标测试中心显示；SDK 记录 IDENTITY_ACCEPTED |
| 真机 VK 登录后转场图标 | 通过 | 中间小羊图标替换为宿主本地 login_transition_icon.png；原 PNG 按比例完整显示，随后测试中心正常加载；源文件与项目资源 SHA256 一致 |
| 真机 VK 振动成功回包 | 通过 | light 调用原生 API 完成，网页显示 result: true；原生耗时 5ms、网页统计 24ms，不代表主观触感测量 |
| 真机 VK 振动非法参数 | 通过 | style: invalid 返回 client_error / error_code: 5 / Invalid params，网页显示对应失败 |
| 真机 VK 扫码启动、取消与重试 | 通过 | 系统扫码页打开；取消返回 client_error / error_code: 4 / User denied；随后能重新打开 |
| 真机 VK 成功识码回包 | 通过 | 网页显示实际 code_data，原生 requestStarted/requestCompleted 对应同一请求；不自动打开识别链接 |
| 真机 VK 前后台恢复 | 通过一次 | 同一 Session 记录 FOREGROUND→BACKGROUND→FOREGROUND，原扫码成功结果保留 |
| 真机 VK 容器重复挂载关闭 | 10/10 通过 | 每次确认返回宿主首页并重新创建 WebView，SDK 记录旧 Session 关闭与新 Session 创建；未等待每轮网页完整加载，不代表 10 次完整登录或内存泄漏测量 |
| 真机 LINE 入口 | API 测试台显示 LIFF 已初始化 | 显示未登录、外部浏览器；不表示原生 API 已验收 |
| 真机 LINE 原生扫码启动、取消与重试 | 通过 | Debug 面板调用真实 scanCodeV2；系统扫码页打开，取消后网页显示 UNKNOWN，SDK 记录 deliveryCompleted；再次点击重新进入系统扫码页 |
| 真机 LINE 成功识码回包 | 通过 | 用户扫描测试二维码；handlerCompleted、deliveryCompleted 与网页显示的实际识别文本一致，不自动打开扫码链接 |
| 真机 VK → 关闭 → LINE | 通过一次 | 可切换且为新 Session，不代替重复稳定性测试 |

迁移回归入口为 `tests/migration.test.cjs`，覆盖宿主创建销毁、独立会话生命周期、LINE 引导页跳转、参数校验、脚本安装时序、目录校验与安全启动映射，以及新增的 LINE WEB 实际代理→原生替身→回包、取消重试、迟到结果和 VK 扫码/振动/错误映射。LINE 文档 ready 会发布 features，测试明确在此之后开始统计能力回包。

迁移过程中曾暴露构建进程缺少 Java 路径，已由 `tools/build.ps1` 配置 DevEco JBR。继承 SDK 仍有废弃 API、Function.bind 和非选定权限的编译警告；打包 HAR 资源编译出现重复资源警告但构建通过，尚未将其解释为运行失败。

## 核心验收结论

本次普通 HAP 接入打包 HAR、加载两个选定小程序以及 LINE 扫码 / VK 扫码与振动的目标已达成。成功、取消重试、VK 非法参数回包均有真机证据；前后台恢复一次及十轮快速挂载关闭也已验证。

LINE 选定网页中的扫码测试卡存在 `inLineClient` 前置条件，WEB 模式会被测试台自身阻止。当前通过 Debug 宿主面板调用真实 API，不伪造客户端状态；也可使用自有 Endpoint 的最小测试页。后续替换应用或升级 SDK 时应重新验收。

后续扩展回归（本次未执行）：断网恢复、真机操作中销毁后的迟到结果、长期内存/性能测量、十轮完整网页加载，以及对外演示录屏。迟到结果目前有平台替身回归，不能替代相应真机场景。截图与 UI 快照仅保存于本地忽略目录，不提交登录态或个人信息。

用户名、密码、验证码由用户在设备上输入，不写入测试配置或仓库。LINE 未登录但其 WEB 扩展扫码已通过，VK 已完成官方登录；本记录按实际验证的 API 和分支限定范围，不宣称完整客户端 API 兼容。

## 复现

```powershell
./tools/build.ps1 -Task Tests
./tools/build.ps1 -Task Hap
# 查看继承失败，不属于绿色迁移套件：
node --test mpsdk/tests/supported-handlers.test.cjs
node --test mpsdk/tests/line-scan-code.test.cjs
node --test mpsdk/tests/vk-response.test.cjs
```

单独运行 Node 命令前需设置 `TYPESCRIPT_PATH`，指向 DevEco 的 `tools/ohpm/node_modules/typescript`。官方登录、远端内容与权限必须在真机单独验证。
