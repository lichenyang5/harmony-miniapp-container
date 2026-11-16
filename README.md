# HarmonyOS Mini App Container

普通 HarmonyOS HAP，通过独立 `mpsdk.har` 加载选定的 LINE/VK H5 小程序。首版范围为 LINE WEB 扫码、VK 扫码与振动，以及容器导航、生命周期和错误处理；不包含元服务发布和完整客户端 API 兼容。

## 目录

- `entry/`：精简宿主、两个 API 测试入口与 LINE/VK 各一个业务入口、返回/刷新/关闭。
- `mpsdk/`：从 AtomicMPSDK 迁入的 HAR 源码、资源及原有测试。
- `libs/mpsdk.har`：本地构建的打包 HAR，默认不提交。
- `tests/`：本项目的迁移回归入口。
- `examples/`：可部署到自有测试应用 Endpoint 的最小网页测试页。
- `tools/`：构建、依赖选择、签名配置模板。

## 构建

使用 DevEco Studio 6.1.1 / HarmonyOS API 24。当前 `compatibleSdkVersion` 为 24，运行设备也需满足此版本。

在 PowerShell 设置本机 `DEVECO_STUDIO_HOME`，然后从仓库根目录执行：

```powershell
./tools/build.ps1 -Task Hap
./tools/build.ps1 -Task Tests
```

脚本配置 SDK、JBR 和 TypeScript 路径，先同步源码 HAR 模块，构建 `libs/mpsdk.har`，再切换到打包 HAR 并构建宿主。新克隆必须先运行脚本生成 HAR，不能直接对缺失 HAR 的工程执行 OHPM 同步。Windows 需具备创建本地依赖链接的权限。Node 使用支持 `node:test` 的版本，本次迁移测试使用 Node 22。

`entry/oh-package.json5` 最终依赖为 `file:../libs/mpsdk.har`。SDK 源码修改后重新运行构建脚本，避免继续使用旧 HAR。

签名只在本地配置：复制 `tools/signing.example.json` 到 `.local/signing.json`，填写自己 DevEco 生成的签名字段。根 `hvigorfile.ts` 将它注入构建上下文；没有本地签名时生成 unsigned HAP。此次迁移已将本机原有签名保存在被忽略的 `.local/` 中。

输出位于 `entry/build/default/outputs/default/`。连接自己的设备后通过 DevEco 运行 `entry`，或使用 HDC 安装 signed HAP 并启动 AppScope 中的应用标识。

## 候选小程序

编辑 `entry/src/main/resources/rawfile/miniapps.json` 并重新构建。当前候选：

| 厂商 | ID | 模式 |
| --- | --- | --- |
| LINE | `2012241484-PibjtMII` | WEB |
| VK | `54769936` | 默认 Adapter / 官方网页登录 |
| VK 壁纸用量计算器 | `54638228` | 真实业务工具 / 复用已有 VK 登录态 |
| LINE · Yahoo! 天气 | `2009013997-MX3EzKQv` | WEB / 本次业务浏览未要求登录 |

宿主只接受数字 VK ID 的官方 `/app<ID>` 地址，以及真实 LIFF ID 的 `miniapp.line.me` / `liff.line.me` 地址。别名、任意 H5、自定义脚本与 SSL 豁免不通过路由参数转交。前两个入口为真实平台 API 测试小程序；后两个分别为 VK 计算工具与 LINE 天气业务，选定流程已有真机证据。目录没有写死这些 ID，可添加其他符合规则的真实入口后重新构建，但需逐应用验证兼容性。

宿主只申请 INTERNET 和 VIBRATE。系统 Scan Kit 扫码页不额外复制原工程的相机、定位、麦克风或传感器权限。SDK 中其他能力保留编译依赖，但不列为本项目已验证能力。

## 接入和验证

- [SDK 公共接入](mpsdk/README.md)
- [LINE 范围](mpsdk/readme_line.md)、[VK 范围](mpsdk/readme_vk.md)
- [迁移边界与来源](docs/migration.md)
- [验证记录及待完成项](docs/validation.md)
- [网页能力测试页](examples/README.md)
- [真实 VK 业务小程序与面试操作卡](docs/vk-business-demo.md)
- [真实 LINE 天气小程序与面试操作卡](docs/line-business-demo.md)

## 求职展示

面试时可直接下载 [完整展示包 ZIP](https://github.com/lichenyang5/harmony-miniapp-container/releases/download/showcase-v1.0.0/miniapp-interview-showcase.zip)，解压后打开 `index.html`，按章节播放两段真机视频并查看讲解要点。[Release 页面](https://github.com/lichenyang5/harmony-miniapp-container/releases/tag/showcase-v1.0.0) 同时提供单独 MP4 和 SHA256 校验文件。

- [项目架构、技术难点、贡献边界与演示步骤](docs/portfolio.md)
- [可用于简历的项目描述与面试口述](docs/resume.md)
- [LINE / VK 真机录屏、离线展示页与讲解稿](showcase/README.md)

展示定位为基于已有 SDK 的多厂商容器集成与原生能力联调。原 SDK 的协议、会话和原生 Handler 实现与本项目新增的宿主、构建、诊断及回归工作分别说明，避免将迁移规模等同于个人原创研发规模。

## 当前验收结果

当前通过 HAR 构建、打包 HAR 宿主签名构建、44 项迁移回归及 ArkTS 测试编译。LINE Debug 面板的系统扫码、取消、重试与成功文本回传均已通过；VK 已完成官方登录，振动成功/非法参数与扫码取消、重试、成功文本回传均已通过。详见验证记录。

另已在 API 26 真机接入 VK 壁纸用量计算器：复用已有登录态，完成两步表单、10 卷/28 条结果、二维裁切详情、宿主/系统返回、关闭释放及重开历史恢复。本次未重新验收全新登录，可选 3D 模型未显示，不纳入演示通过项；远端冷加载较慢，演示前需预检。

LINE Yahoo! 天气已完成地区搜索、新宿偏好保存、今日/明日预报切换、刷新和重开恢复、宿主/系统返回及关闭释放。本次业务浏览未要求登录，不代表 LINE 账号登录通过；日期切换属于页内状态，当前无网页历史时宿主返回退出容器。扫码诊断面板仅保留在原 API 测试入口，业务页不添加。

VK 登录后加载页的居中图标使用宿主资源 `entry/src/main/resources/base/media/login_transition_icon.png`。宿主仅在选定官方 VK 应用路径的顶层页面替换唯一居中加载图片，不修改平台配置或业务 iframe；原图片尺寸保留，新图按完整比例显示。网页加载布局变化后需重新检查匹配条件。
