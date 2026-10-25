# Leaf5+ 导航与紧凑底栏调查

调查日期：2026-10-25。目标：文石 BOOX Leaf5+，为日常漫画阅读提供不遮挡正文、尽量少占空间的信息栏。

源码基线：`feature/leaf-reader-footer` / `77e12cf9b09e177b501fb5a7ab45ce58c07d8721`。调查时含未提交的Leaf适配实现。下述代码和测试结论对应当时工作区，不代表该基线commit本身已包含这些修改。

## 机型与导航证据

| 信息 | 结论 | 依据及限制 |
|---|---|---|
| 目标机型 | BOOX Leaf5+ | 使用者指定；[官方产品页](https://zh.boox.com/product-ad/?id=5499)标题核对为Leaf5+ |
| 该设备导航方式 | 手势导航，底部无虚拟按键栏 | 使用者于2026-10-25明确确认；不是对所有Leaf5+出厂设置的断言 |
| BOOX导航选择 | 手势导航或虚拟按键；手势可自定义底部3个、侧边2个动作 | [官方高速阅读器说明](https://support.boox.com/#/document/69bb6e43de2ae6af66489168)，属于通用说明 |
| 固定8像素底部安全区 | 没有在上述官方说明中找到此规定 | 旧预览的8像素来自测试脚本模拟，并非机型参数；没有读取实机WindowInsets |
| 设备固件、Android版本、逻辑尺寸、DPI及实际padding | 待实测 | 本轮未读取，不依据产品营销图或其他BOOX机型猜测 |

官方说明的关键原文：“可修改系统的导航方式为手势导航或虚拟按键”；“手势导航可自定义底部3个手势、侧边2个手势”。同页提示“不同尺寸的墨水平板，布局会有差别，请以设备本身为准”。以上为当次页面阅读摘录，未保存官方页面完整离线副本；链接未来可能变化。

手势触发区域不能直接等同于应用必须留白的区域。依据机型名称无法证明运行时padding恒为0，也不应凭空给手势模式添加固定白边。

## 2026-10-26 补充纠正

后续用户实测仍有白边，发现此前遗漏了应用根层将正常顶部0误判、强制注入上下各15的逻辑。以下“系统实际bottom padding”的结论对2372并不完整：其值可能已被根层覆盖。修复、完整链路与回归见[根层补白调查](2026-10-26-root-insets.md)。原测试记录保留为当时组件级验证，不能视为已覆盖根层。

## 2026-10-26 用户语义澄清

使用者明确原先“高度”意指文字下方留白，而不是底栏总高度；已改为“横线1＋固定线下间隔2＋自然文字高度＋底部留白0–15”，留白默认4，字号范围不变。用户根据渲染选择固定间隔2。以下旧表为历史参数；当前规范与预览以[分段布局记录](2026-10-26-footer-spacing.md)为准。

## 已采用的应用参数

以下均为**应用设计值**，不是硬件规格。高度及字号按Flutter逻辑单位设置，字体仍响应系统缩放。

| 项目 | 当前值 | 说明 |
|---|---|---|
| 底栏高度 | 15–25，默认18 | 旧范围28–64、默认36；旧超范围值沿用数值归一化至25 |
| 底栏字号 | 9–13，默认11 | 旧范围12–18、默认14；旧超范围值归一化至13 |
| 上下固定留白 | 0 | 去掉原上下各6；文字底对齐 |
| 顶部分隔线 | 1逻辑像素，全宽 | 浅色黑线，深色使用主题前景色 |
| 标题 | 书名｜章节名，单行省略 | 复用原版ReaderShellData.title/chapterTitle；无章节仅书名，缺失章节标题沿用E{chapter} |
| 标题开关 | readerFooterShowChapter，默认false | 沿用原键和继承规则；文案为“在阅读信息栏显示书名和章节名” |
| 实际底栏高度 | max(设置高度, 测量内容高度+1)，再加系统实际bottom padding | 大字或窄屏双行可超过25，不裁切页码和状态信息 |
| 模式范围 | 画廊模式 | 连续/瀑布流保留上游信息显示行为 |

`showSystemStatusBar`默认false。关闭阅读菜单时请求`SystemUiMode.immersive`隐藏系统栏，打开菜单时切回`edgeToEdge`；用户开启系统栏设置时仍遵循其设置。底栏读取`MediaQuery.paddingOf(context)`，没有固定8像素，也没有按`systemGestureInsets`人为增加手势区。

源码入口：[偏好定义](../../lib/foundation/reader_preferences.dart)、[底栏布局](../../lib/features/reader/information_footer.dart)、[阅读区接入](../../lib/features/reader/scaffold.dart)、[平台系统栏控制](../../lib/features/reader/platform_effects.dart)、[阅读器系统栏策略](../../lib/features/reader/reader_page.dart)。

## 验证及未决项

- 使用者确认前一版固定签名Release功能正常；紧凑、底对齐版2372尚待实机反馈。
- 相关自动回归50项通过：reader布局18、settings snapshot 9、preference store 12、appdata 11；Flutter analyze无问题。可按对应仓库测试复跑。
- 本地真实CJK字体预览11组通过：宽度320/412/667、字体缩放1/3.2、明暗主题及各信息组合。18/11和15/9在普通缩放下可达到设置高度；基准模拟bottom padding=0，另保留8像素兼容场景。这些是widget测试，不是Leaf5+实机尺寸或截图。
- 初始测试把窄屏双行误当成单行，导致同底断言失败；修正为宽屏单行同底、窄屏双行状态贴底及不重叠，未靠更改产品测量掩盖问题。
- 完整Flutter回归此前未全绿；本轮专项通过不代表全套通过。完整日志与预览保存在本机任务证据中，未把含机器路径的日志和图片复制进仓库。本记录保留结论与复跑入口，不冒充完整原始日志。

复跑入口（使用项目规定的Flutter版本）：

```sh
flutter test --no-pub test/features/reader/information_overlay_test.dart test/foundation/reader_settings_snapshot_test.dart test/foundation/reader_preference_store_test.dart test/foundation/appdata_test.dart
flutter analyze --no-pub
```

若实机仍有白边，先读取固件/系统版本、导航模式、菜单开关状态、逻辑尺寸、textScaler及MediaQuery的padding/viewPadding/viewInsets，再对照正文和底栏边界。不能直接把通用模拟值当成原因，也不应盲目清零真实遮挡值。后续按键、横竖屏、缩放、墨水屏残影和覆盖升级需要分别记录实机证据。
