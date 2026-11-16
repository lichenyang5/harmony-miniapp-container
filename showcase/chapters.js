window.SHOWCASE = {
  "recordedOn": "2026-11-16",
  "format": "H.264 MP4, 1920×1080, 30 fps, silent",
  "editing": "Real device footage. Waiting may be shortened as specified in the edit plan. No simulated UI.",
  "videos": [
    {
      "id": "line",
      "title": "LINE 真实业务流程",
      "subtitle": "Yahoo! 天气 · LINE WEB · 真机录制",
      "file": "videos/line-business.mp4",
      "poster": "posters/line.jpg",
      "duration": 74.466667,
      "size": 1926264,
      "sha256": "c2e879aa7cc0077b1f9c80617497503469df3fbcac9191b886001b2df5a2a596",
      "sourceDuration": 163.624,
      "chapters": [
        {
          "start": 0,
          "end": 9.5,
          "title": "打开真实 LINE 业务",
          "narration": "宿主通过独立 HAR，\n加载真实天气小程序。\n本次业务浏览无需登录。",
          "note": "远端加载等待 2× 加速；非性能演示。",
          "sourceFrom": 0,
          "sourceTo": 19,
          "speed": 2,
          "frames": 285
        },
        {
          "start": 9.5,
          "end": 14.5,
          "title": "业务首页",
          "narration": "当前设备已保留新宿偏好。\n下面新增一个公开测试地区，\n不使用手机真实位置。",
          "note": "",
          "sourceFrom": 19,
          "sourceTo": 24,
          "speed": 1,
          "frames": 150
        },
        {
          "start": 14.5,
          "end": 30,
          "title": "搜索公开测试地区",
          "narration": "输入公开邮编 1500002，\n等待涉谷区候选出现。\n搜索结果来自远端业务。",
          "note": "",
          "sourceFrom": 33.5,
          "sourceTo": 49,
          "speed": 1,
          "frames": 465
        },
        {
          "start": 30,
          "end": 35.5,
          "title": "选择涉谷区",
          "narration": "选择真实候选，\n进入对应城市天气。",
          "note": "候选等待的空闲片段已删减。",
          "sourceFrom": 68.5,
          "sourceTo": 74,
          "speed": 1,
          "frames": 165
        },
        {
          "start": 35.5,
          "end": 41.8,
          "title": "保存地区偏好",
          "narration": "保存涉谷区，\n原有新宿偏好继续保留。",
          "note": "仅验证本设备恢复，不宣称账号云同步。",
          "sourceFrom": 82.7,
          "sourceTo": 89,
          "speed": 1,
          "frames": 189
        },
        {
          "start": 41.8,
          "end": 47.3,
          "title": "今日 / 明日切换",
          "narration": "切换预报的展开项，\n验证真实页面内状态变化。",
          "note": "",
          "sourceFrom": 98.5,
          "sourceTo": 104,
          "speed": 1,
          "frames": 165
        },
        {
          "start": 47.3,
          "end": 54.3,
          "title": "刷新与恢复",
          "narration": "使用宿主刷新，\n确认业务页面和地区偏好恢复。",
          "note": "刷新等待 3× 加速。",
          "sourceFrom": 104,
          "sourceTo": 125,
          "speed": 3,
          "frames": 210
        },
        {
          "start": 54.3,
          "end": 58.8,
          "title": "返回宿主，再次进入",
          "narration": "当前没有可回退网页历史，\n顶部返回退出到宿主目录。\n随后再次打开。",
          "note": "",
          "sourceFrom": 125,
          "sourceTo": 129.5,
          "speed": 1,
          "frames": 135
        },
        {
          "start": 58.8,
          "end": 64.46666666666667,
          "title": "重新加载业务",
          "narration": "重新创建容器，\n加载同一个真实业务入口。",
          "note": "远端加载等待 3× 加速。",
          "sourceFrom": 129.5,
          "sourceTo": 146.5,
          "speed": 3,
          "frames": 170
        },
        {
          "start": 64.46666666666667,
          "end": 69.46666666666667,
          "title": "偏好仍保留",
          "narration": "新宿和涉谷偏好仍在。\n最后使用关闭按钮退出。",
          "note": "此处 0.5× 慢放，便于查看恢复结果。",
          "sourceFrom": 146.5,
          "sourceTo": 149,
          "speed": 0.5,
          "frames": 150
        },
        {
          "start": 69.46666666666667,
          "end": 74.466667,
          "title": "关闭，回到宿主",
          "narration": "业务浏览闭环完成。\n本项目贡献是容器接入、\n导航和恢复行为的验证。",
          "note": "天气页面与业务数据属于第三方。",
          "sourceFrom": 149,
          "sourceTo": 154,
          "speed": 1,
          "frames": 150
        }
      ],
      "boundaries": [
        "业务浏览未要求登录，不代表 LINE 账号认证通过。",
        "录屏以公开邮编 1500002 的涉谷区为例，保留原有新宿偏好。",
        "日期切换是页内状态；无可返回历史时宿主返回退出容器。",
        "网络等待有加速或删减，不能据成片时长评价加载性能。"
      ]
    },
    {
      "id": "vk",
      "title": "VK 真实业务流程",
      "subtitle": "壁纸用量计算器 · 既有登录态 · 真机录制",
      "file": "videos/vk-business.mp4",
      "poster": "posters/vk.jpg",
      "duration": 122.6,
      "size": 3269597,
      "sha256": "2f5220ca808963a29150bc2fcccf671fc46a992e4d5826df6cd50c60b47a691b",
      "sourceDuration": 305.638,
      "chapters": [
        {
          "start": 0,
          "end": 9.333333333333334,
          "title": "打开真实 VK 业务",
          "narration": "通过独立 HAR 加载计算器，\n复用既有官方 VK 登录态。\n不录制账号或验证码。",
          "note": "远端加载等待 3× 加速。",
          "sourceFrom": 0,
          "sourceTo": 28,
          "speed": 3,
          "frames": 280
        },
        {
          "start": 9.333333333333334,
          "end": 15.333333333333334,
          "title": "第三方业务首页",
          "narration": "这里不是 API 测试台，\n而是可操作的真实计算工具。",
          "note": "页面和计算算法属于第三方。",
          "sourceFrom": 28,
          "sourceTo": 34,
          "speed": 1,
          "frames": 180
        },
        {
          "start": 15.333333333333334,
          "end": 22.333333333333336,
          "title": "新建演示计算",
          "narration": "新建测试房间，\n添加 InterviewDemo 标记，\n便于在历史记录中识别。",
          "note": "",
          "sourceFrom": 55.5,
          "sourceTo": 62.5,
          "speed": 1,
          "frames": 210
        },
        {
          "start": 22.333333333333336,
          "end": 26.833333333333336,
          "title": "确认房间尺寸",
          "narration": "使用虚构测试尺寸：\n400 × 300 × 270 cm。",
          "note": "",
          "sourceFrom": 73.5,
          "sourceTo": 78,
          "speed": 1,
          "frames": 135
        },
        {
          "start": 26.833333333333336,
          "end": 33.833333333333336,
          "title": "设置门窗数量",
          "narration": "将门数调整为 0，\n滚动查看窗数与下一步。",
          "note": "",
          "sourceFrom": 85.5,
          "sourceTo": 92.5,
          "speed": 1,
          "frames": 210
        },
        {
          "start": 33.833333333333336,
          "end": 40.53333333333334,
          "title": "进入第二步表单",
          "narration": "将窗数也调整为 0，\n进入壁纸参数。",
          "note": "",
          "sourceFrom": 98.8,
          "sourceTo": 105.5,
          "speed": 1,
          "frames": 201
        },
        {
          "start": 40.53333333333334,
          "end": 48.53333333333334,
          "title": "选择壁纸参数",
          "narration": "内置纯色样式，\n卷宽 53、卷长 1005 cm，\n保持无对花模式。",
          "note": "",
          "sourceFrom": 113.7,
          "sourceTo": 121.7,
          "speed": 1,
          "frames": 240
        },
        {
          "start": 48.53333333333334,
          "end": 58.56666666666667,
          "title": "执行真实业务计算",
          "narration": "点击计算并等待结果，\n由远端业务返回实际计算内容。",
          "note": "计算等待 3× 加速，空闲片段已删减。",
          "sourceFrom": 168.4,
          "sourceTo": 198.5,
          "speed": 3,
          "frames": 301
        },
        {
          "start": 58.56666666666667,
          "end": 67.06666666666666,
          "title": "结果：10 卷 / 28 条",
          "narration": "当前版本对这组参数，\n显示 10 卷、28 条，\n铺贴面积 37.8 m²。",
          "note": "这是业务输出，不是本项目的算法研发成果。",
          "sourceFrom": 198.5,
          "sourceTo": 207,
          "speed": 1,
          "frames": 255
        },
        {
          "start": 67.06666666666666,
          "end": 75.26666666666667,
          "title": "打开二维裁切详情",
          "narration": "打开 400 × 270 cm 墙面，\n查看 8 条裁切方案与卷号。",
          "note": "此处 0.5× 慢放，便于查看。",
          "sourceFrom": 213.2,
          "sourceTo": 217.3,
          "speed": 0.5,
          "frames": 246
        },
        {
          "start": 75.26666666666667,
          "end": 82.06666666666666,
          "title": "系统返回生效",
          "narration": "手机返回键回到结果页，\n随后再次进入墙面详情。",
          "note": "此处 0.5× 慢放，便于观察导航。",
          "sourceFrom": 217.3,
          "sourceTo": 220.7,
          "speed": 0.5,
          "frames": 204
        },
        {
          "start": 82.06666666666666,
          "end": 90.06666666666666,
          "title": "查看完整二维方案",
          "narration": "彩色条带标明裁切顺序，\n卷号标明来自哪一卷壁纸。",
          "note": "该业务页面与算法由第三方提供。",
          "sourceFrom": 221,
          "sourceTo": 229,
          "speed": 1,
          "frames": 240
        },
        {
          "start": 90.06666666666666,
          "end": 97.26666666666667,
          "title": "宿主返回与关闭",
          "narration": "顶部返回也回到结果页。\n关闭后返回宿主目录，\n再从目录重新进入。",
          "note": "",
          "sourceFrom": 235.8,
          "sourceTo": 243,
          "speed": 1,
          "frames": 216
        },
        {
          "start": 97.26666666666667,
          "end": 105.13333333333333,
          "title": "重新打开业务",
          "narration": "重新创建容器，\n等待远端业务加载。",
          "note": "加载等待 4× 加速。",
          "sourceFrom": 243,
          "sourceTo": 274.5,
          "speed": 4,
          "frames": 236
        },
        {
          "start": 105.13333333333333,
          "end": 109.13333333333333,
          "title": "打开计算历史",
          "narration": "历史列表中能看到\nInterviewDemo 测试记录。",
          "note": "",
          "sourceFrom": 274.5,
          "sourceTo": 278.5,
          "speed": 1,
          "frames": 120
        },
        {
          "start": 109.13333333333333,
          "end": 119.43333333333332,
          "title": "恢复同一份结果",
          "narration": "打开本次测试记录，\n再次显示同一份计算结果。\n验证关闭重开后的业务恢复。",
          "note": "",
          "sourceFrom": 288.2,
          "sourceTo": 298.5,
          "speed": 1,
          "frames": 309
        },
        {
          "start": 119.43333333333332,
          "end": 122.6,
          "title": "关闭，回到宿主",
          "narration": "两平台业务演示完成。",
          "note": "会话与 WebView 释放另有验收日志。",
          "sourceFrom": 302.3,
          "sourceTo": 305.5,
          "speed": 1,
          "frames": 95
        }
      ],
      "boundaries": [
        "复用已有官方 VK 登录态，视频不含全新登录验收。",
        "业务页面与计算算法属于第三方，个人贡献为容器集成和联调。",
        "本次仅演示二维裁切；未通过的可选 3D 模型不列入展示。",
        "等待片段有加速或删减，部分导航慢放以便观察，不是性能测量。"
      ]
    }
  ]
};
