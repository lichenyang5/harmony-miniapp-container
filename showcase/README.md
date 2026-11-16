# 面试展示包

## 下载

前往 [面试展示 v1.0 Release](https://github.com/lichenyang5/harmony-miniapp-container/releases/tag/showcase-v1.0.0)，下载 [完整展示包 ZIP](https://github.com/lichenyang5/harmony-miniapp-container/releases/download/showcase-v1.0.0/miniapp-interview-showcase.zip)。完整解压后再打开 `index.html`。

也可单独下载 [LINE 视频](https://github.com/lichenyang5/harmony-miniapp-container/releases/download/showcase-v1.0.0/line-business.mp4)、[VK 视频](https://github.com/lichenyang5/harmony-miniapp-container/releases/download/showcase-v1.0.0/vk-business.mp4) 和 [SHA256 校验文件](https://github.com/lichenyang5/harmony-miniapp-container/releases/download/showcase-v1.0.0/SHA256SUMS.txt)。GitHub 自动生成的 Source code 压缩包不包含视频；面试展示请使用名为 `miniapp-interview-showcase.zip` 的附件。

## 使用

双击本目录的 **index.html**，选择 LINE 或 VK 即可播放。页面支持按章节跳转，并同步显示该步骤的讲解要点。请完整解压展示包，保留 `videos`、`posters`、`subtitles` 与页面的相对位置。

视频是 **1080p / 30 fps / H.264 MP4 静音字幕版**，字幕和步骤说明已烧录进画面，单独发送 MP4 也能展示；无需字体安装、字幕插件或登录播放服务。可按 [完整讲解稿](interview-script.md) 现场口述。

| 素材 | 内容 | 大致时长 |
| --- | --- | --- |
| [LINE 业务录屏](videos/line-business.mp4) | 打开天气、公开地区搜索、保存涉谷、预报切换、刷新、返回、重开与关闭 | 1 分 14 秒 |
| [VK 业务录屏](videos/vk-business.mp4) | 两步表单、实际计算、二维裁切、系统/宿主返回、关闭、重开与历史恢复 | 2 分 03 秒 |
| [讲解稿](interview-script.md) | 开场、逐平台说明、收尾与常见追问 | 可按面试时间选读 |

## 推荐展示顺序

1. 用约 20 秒说明个人职责：新宿主、独立 HAR 接入、导航与生命周期接入、联调与验证。
2. 播放 LINE，说明 WEB 业务浏览、地区偏好及返回规则；本次录屏用公开邮编 `1500002` 的涉谷区，保留此前验证的 `1600022` 新宿区。
3. 播放 VK，说明已有登录态下的参数计算、二维业务详情及两种返回；历史记录含 `InterviewDemo` 标记。
4. 用约 20 秒收尾：业务视频证明承载与操作流程，扫码/振动的原生桥接另有 API 测试入口和验收记录。

总展示约 4 分钟，可暂停视频展开技术细节。讲稿的较长解释适合暂停后补充，按章节显示的短讲解适合随播口述。

## 素材与剪辑说明

- 录制日期：2026-11-16；API 26 真机，普通 HarmonyOS HAP 消费独立 HAR。
- 原片为连续真机操作：LINE 约 164 秒，VK 约 306 秒，保存于仓库忽略目录 `.local/showcase/raw/`。
- 展示版去掉状态栏、录屏计时与调试坐标栏；省略部分空闲等待，对加载片段作 2～4 倍加速，部分导航作 0.5 倍慢放。相关位置有文字说明，精确区间见 `edit-plan.json`（仓库中）及 `manifest.json`。
- 没有重绘业务 UI 或用截图拼接冒充操作。不得将剪辑后的时长当作真实加载耗时、性能优化数据或长期稳定性证据。
- LINE 本次操作未要求登录，不能表述为 LINE 账号认证通过。VK 复用已有官方登录态，不是全新登录验收。
- 第三方页面、业务算法和数据不属于个人原创。VK 可选 3D 模型不列入通过项；视频仅演示已确认的二维流程。
- 两段成片无音轨。原片录制关闭了麦克风，导出展示版时也移除了系统音轨。

## 文件说明

- `index.html`、`chapters.js`：无外部依赖的离线播放入口与章节信息。
- `videos/*.mp4`：可直接展示或单独发送的视频。
- `posters/*.jpg`：从成片提取的封面。
- `subtitles/*.srt`、`*.vtt`：可编辑的中文字幕。
- `manifest.json`：时长、大小、SHA256 及章节与原片区间。
- `interview-script.md`：可照读和按需展开的讲稿。

视频和 ZIP 默认不进 Git。新克隆仓库时，只有播放页和说明不会自动得到视频，请下载上述完整展示包；也可将两段 MP4 放入克隆目录的 `showcase/videos/`。SHA256 可用 PowerShell 的 `Get-FileHash -Algorithm SHA256 <文件路径>` 核对，Release 校验文件列出两段 MP4 和完整 ZIP 的摘要。

## 检查与复现

成片已完整解码检查，并抽取各章节和导航前后的关键帧核对画面、字幕及范围。播放页的资源路径、章节跳转与平台切换逻辑另做代码检查；内置浏览器因 `file:` 协议安全策略未能实际打开本地页，不将其标为浏览器实测通过。可使用本机 Chrome 或 Edge 打开，或直接播放 MP4。

本次临时录制助手已从项目源码移除，正常签名 HAP 已重新构建并安装。构建不再包含该助手；后续运行项目无需录屏授权。

开发复现：在仓库根目录保留对应原片与 `showcase/edit-plan.json`，安装可用的 FFmpeg/FFprobe，执行 `node tools/build-showcase.cjs`。原片不随展示包分发，避免混淆编辑版与原始验收材料。
