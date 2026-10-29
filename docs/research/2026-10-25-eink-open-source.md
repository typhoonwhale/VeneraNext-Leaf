# 墨水屏开源参考补充：VeneraNext、KOReader 与插件

日期：2026-10-25。用户要求在实施前补充直接上游 VeneraNext 和网上开源插件的实现思路。本轮仅调查，当前分支 `feature/leaf-eink-adaptation`，HEAD `3eac32b9463368f6596bb1107519b4319dfb9d2f`；沿用上一轮未提交的调研文档，没有修改运行代码、安装插件、构建 APK、提交或推送。

结论：**VeneraNext 是优先复用的直接上游；KOReader 最值得借鉴的是核心刷新调度与设备后端；第三方强刷插件只能补充策略，不能给不支持的设备凭空增加硬件刷新能力。** 第一阶段黑白高对比和减少动画仍不需要接入厂商 SDK。若后续确有残影问题，再用独立、可关闭的 Android 原生实验验证 Leaf5+ 接口。

## 1. 明确直接上游，而非只看原始 Venera

本轮重新使用 GitHub API 核实：`typhoonwhale/VeneraNext-Leaf` 的 `fork=true`，`parent.full_name=CyrilPeng/Venera-Next`。[直接上游](https://github.com/CyrilPeng/Venera-Next)当次 `main` 仍为 `91e651a8d1351bb78770f9a57ae2a30a76447650`。

上一轮已检查该仓库 119 条 issue/PR 记录，以及 v1.18.1 到当次 main 的 8 个提交。软件 E-Ink 刷新来自其 [81fe47b](https://github.com/CyrilPeng/Venera-Next/commit/81fe47b26d4028733fce2fa836f783fbea2c532b)，已包含在我们的版本。5 个相关刷新/设置文件在 v1.18.1 与当次 main 的 blob SHA 相同；本轮没有发现需要再合入的新版硬件刷新实现。范围和证据见[上一轮调研](2026-10-25-eink-adaptation.md)及[上游摘要](evidence/2026-10-25-eink-upstream-sources.json)。

优先沿用它的设置继承、页变化事件、翻页动画开关与现有刷新计数入口。现有 `ColoredBox` 黑/白闪屏仍应与未来硬件刷新区分，避免两套策略同时触发。原始 Venera 的未合并 PR #754 是补充需求参考，不取代对 VeneraNext 当前架构的核对。

## 2. KOReader 核心提供的实现思路

固定源码：`koreader/koreader` 的 `400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f`；它绑定的 Android launcher 子模块为 `e0c3c861b043966a8d845392f10d64da095f99bc`。launcher 独立默认分支当次为 `17713ea1db0a3d1ab76e736a4363d052451f1412`，二者没有混作同一发布版本。

| 机制 | 核验依据 | 对 Leaf 的启发 |
|---|---|---|
| 重绘与面板刷新分离 | [UIManager `setDirty`](https://github.com/koreader/koreader/blob/400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f/frontend/ui/uimanager.lua#L532)将请求留到后续 UI tick；函数返回不等于屏幕完成刷新 | 不在每个 widget 的 `setState` 后直接请求全刷 |
| 合并刷新请求 | [刷新队列](https://github.com/koreader/koreader/blob/400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f/frontend/ui/uimanager.lua#L1199)合并相交区域并保留较强模式 | 漫画、页码和菜单同时更新时，避免分别发出多次硬件请求；Flutter 自身局部重绘不等于面板局刷 |
| 内容与 UI 分开计数 | [partial 晋升逻辑](https://github.com/koreader/koreader/blob/400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f/frontend/ui/uimanager.lua#L1231)每轮 repaint 至多计数一次，达到配置阈值后提升刷新模式 | “每 N 页”应由有效内容变化驱动，而不是按秒、每个组件重建或图片下载进度触发 |
| 按内容/场景配置 | [刷新菜单](https://github.com/koreader/koreader/blob/400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f/frontend/ui/elements/refresh_menu_table.lua#L54)含每页/每6页/自定义，以及章节、图片相关选项 | 参考区分漫画翻页、菜单和静止信息栏；6 是该项目设计值，不是 Leaf5+ 最佳参数。图片项本轮仅核对设置入口，没有验证完整执行链 |
| 拖动期间偏快 | 同一 UIManager 在 `currently_scrolling` 时使用 fast 请求 | 可研究交互期间响应优先、结束后画质优先；前提是设备后端真的支持相应模式 |

KOReader 的 `full` 指高保真闪刷语义，覆盖范围还取决于 region；有 region 时不能仅凭名称翻译成“整个屏幕全刷”。我们的实现不需要复制一整套 KOReader UIManager，也不应给 Flutter 人为降到某个固定帧率。可以先保留“内容已经稳定 → 统一请求一次”的最小策略，硬件部分只有验证成功后才接入。

## 3. 真正存在的 KOReader 插件：ForceRefresh

已通过网页搜索找到并读取 [acanoe/forcerefresh.koplugin](https://github.com/acanoe/forcerefresh.koplugin)，固定 commit `68272f15b327afa4c5410b455feadfe54034fff2`，当次最后推送时间为 2025-10-25 UTC，未归档。

[`main.lua`](https://github.com/acanoe/forcerefresh.koplugin/blob/68272f15b327afa4c5410b455feadfe54034fff2/main.lua)的核心很小：收到 `onPageUpdate` 后通过 `UIManager:scheduleIn(0.1, ...)`，再调用 `UIManager:setDirty(self.ui, self.refresh_mode)`。可选 `full`、`partial`、`flashui`、`flashpartial`，另有休眠刷新开关。默认功能关闭，默认模式 `flashui`；0.1 秒是插件的软件延迟，不是屏幕刷新耗时或 Leaf5+ 建议值。

这说明插件主要决定**什么时候向已有刷新系统再请求一次**，不包含 BOOX 驱动或 Flutter 接口。它不能直接安装到我们的应用，也不能补齐未被识别的硬件后端。README 建议与 KOReader 每页全刷叠加来实现两次刷新，属于作者方案，不是我们应采用的默认值。连续翻页、关闭文档时的待执行请求如何合并/撤销，也需要在自己的实现中明确。

插件 `_meta.lua` 特别提到 Kindle，未提供 Leaf5+ 验证。仓库只有 README、`_meta.lua`、`main.lua`，当次未发现 LICENSE，GitHub license 元数据为 null；本轮只参考公开思路，不复制代码进入本项目。

另一个容易混淆的插件是 [KOReader AutoTurn](https://github.com/koreader/koreader/blob/400ba0e65ca4baa8df1f2eaabfe3715c76d9da1f/plugins/autoturn.koplugin/main.lua)：它负责定时发出 `GotoViewRel` 翻页事件，并处理输入/休眠时的定时任务，依赖阅读器既有刷新机制；它本身不是去残影或硬件刷新插件。

## 4. KOReader 的 Onyx Android 后端更接近硬件复用入口

[绑定版本的 OnyxEPDController](https://github.com/koreader/android-luajit-launcher/blob/e0c3c861b043966a8d845392f10d64da095f99bc/app/src/main/java/org/koreader/launcher/device/epd/OnyxEPDController.kt)通过 [QualcommEPDController](https://github.com/koreader/android-luajit-launcher/blob/e0c3c861b043966a8d845392f10d64da095f99bc/app/src/main/java/org/koreader/launcher/device/epd/qualcomm/QualcommEPDController.kt)反射调用厂商扩展 `View.refreshScreen` 和 `setWaveformAndScheme`；不是在应用上盖黑白图片。

但其能力声明是 `full-only`，源文件标注测试设备为 Nova 2，常量和延迟均不能直接视作 Leaf5+ 规格。代码还尝试干预系统刷新策略，注释指出某些系统模式仍可能在其后再次刷新，说明叠加策略是实际集成风险。

绑定版本[设备识别表](https://github.com/koreader/android-luajit-launcher/blob/e0c3c861b043966a8d845392f10d64da095f99bc/app/src/main/java/org/koreader/launcher/device/DeviceInfo.kt)明确包含 Leaf、Leaf2/Leaf2 Plus，未发现 Leaf5+ 明确条目；独立 launcher 最新快照新增 Leaf5c，**Leaf5c 不等于 Leaf5+**。当前检查路径未匹配时走 `Id.NONE` 和 `FakeEPDController` 空实现，没有通用 Onyx fallback。这不证明 Leaf5+ 必然不可用，因为实际 Build 字段可能匹配已有条件；必须读设备信息和探测接口。

可借鉴的落地顺序是：在 Flutter Android 侧验证一个最小原生桥，先只提供手动刷新实验，返回明确的支持/失败结果；确认图像已提交、刷新实际发生且不被系统重复触发，再考虑翻页自动策略。不要先移植整个 KOReader、按产品名称硬编码支持、照搬反射常量或绕过失败结果。

KOReader 核心为 AGPL-3.0，当前 Leaf 工程许可证文件为 GPLv3；核心 Lua 代码不能当作可任意复制的零依赖片段。Android launcher 为 MIT，若复用其代码需保留许可和版权。公开的官方 Onyx SDK 是另一候选路线，见[官方依据](2026-10-25-eink-adaptation.md)，仍需验证固件与 Flutter 渲染兼容性。

## 5. 对软件黑白闪屏的反例

[KOReader #11288](https://github.com/koreader/koreader/issues/11288)请求给未适配设备提供连续黑白闪屏兜底，当次状态为 closed / not_planned。维护成员[讨论](https://github.com/koreader/koreader/issues/11288#issuecomment-1870759120)指出，类似先白后图的序列在部分屏保场景使用过，但效果与停留时间有关，在要求及时响应的阅读过程中并不适合直接照搬。

这不证明 VeneraNext 的软件闪屏一定无效，也不代表第三方 ForceRefresh 不存在；三者是不同实现与维护者取舍。它提醒我们不要将“多闪几次”当通用硬件全刷替代方案。该 issue 还有转贴 AI 生成的原理解释，本报告未将其作为权威技术依据。

## 6. 其他开源实现与 Flutter 包

### Komga Reader：与漫画场景更接近的 SDK 实现

[Gabriel-Graf/komga-reader](https://github.com/Gabriel-Graf/komga-reader)当次固定 commit 为 `606d27adf33d84c43f9cb0fce2d8e1e33cd2490e`，未归档，最后推送 2026-07-03 UTC。它是原生 Kotlin/Compose 阅读器，不是 Flutter 插件。

其 [`OnyxEinkController`](https://github.com/Gabriel-Graf/komga-reader/blob/606d27adf33d84c43f9cb0fce2d8e1e33cd2490e/eink-onyx/src/main/kotlin/com/komgareader/eink/onyx/OnyxEinkController.kt)有两类明确调用：

- `EpdController.setAppScopeRefreshMode(UpdateOption...)`：设置应用刷新模式，映射 NORMAL/FAST_QUALITY/REGAL/FAST/FAST_X。
- `EpdController.applyTransientUpdate(UpdateMode.GC)`：请求一次全刷；`refresh()` 对非 FULL 的显式请求直接返回，将它们交给上下文模式控制。不能因接口接受 region 就声称该后端支持任意区域局刷。

它的默认场景策略为 WEBTOON 使用 SPEED，其余使用 HD，可参考“连续滚动与分页分开选择策略”；不能照搬这些默认值作为 Leaf5+ 已验证参数。[Android 模块](https://github.com/Gabriel-Graf/komga-reader/blob/606d27adf33d84c43f9cb0fce2d8e1e33cd2490e/eink-onyx/build.gradle.kts)使用 `onyxsdk-device:1.3.5`，因此它也提供了官方 SDK 调用路线的公开样例。

限制很具体：源文件说明目标 Onyx 型号为 Go Color 7 Gen2，并硬编码 `canColor=true`，不能照搬给黑白 Leaf5+。方法异常主要记录日志，不能把调用返回当成面板已成功刷新；我们若做原生桥，需要明确探测及错误返回。该项目采用 AGPLv3 系列许可证，参考接口和设计不等于直接复制整套实现。它的屏保、关机图和颜色调整不在本次需求范围内。

### onyxsdk_pen：真正的 Flutter 插件，但用途不同

[pub.dev 的 onyxsdk_pen](https://pub.dev/packages/onyxsdk_pen)当次最新版本 1.5.0（2026-05-20 UTC），源码在 [Saber 的 packages/onyxsdk_pen](https://github.com/saber-notes/saber/tree/main/packages/onyxsdk_pen)。README 明确表示它接入 Onyx Pen SDK，只提供 `OnyxSdkPenArea` 以优化绘画笔迹；非 Onyx Android 设备回退为原 child。它不能直接替代整页漫画的刷新模式控制。

README 还注明作者已无 Onyx 设备，按 best effort 维护。我们当前没有手写需求，因此不建议为了名称里有 Onyx 就引入它。此次未安装该包，也未按 README 改 Maven 源或构建配置。

### Librera：Android View 路线的边界参考

[LibreraReader #374](https://github.com/foobnix/LibreraReader/issues/374)是 KOReader #11288 中维护成员提及的参考，讨论普通 Android View 的 invalidate/postInvalidate 与设备自身刷新策略。本轮未将这种讨论当成通用硬件刷新插件，也未证明 Flutter Surface 上会得到相同结果；不据此直接给当前应用增加 invalidate 调用。

本轮还检索了 pub.dev 的 eink/boox/onyx，以及 GitHub 的 Flutter/e-ink/BOOX 组合词。命中的结果需区分 UI 主题、图像抖动、笔迹加速与面板控制；在已核验范围内，没有确认能直接接入本项目、已验证 Leaf5+ 阅读刷新控制的通用 Flutter 包。这个结论是有界检索结果，不代表整个生态没有其他候选。

## 7. 验证边界与下一步

网页搜索用于发现候选，GitHub 固定版本源码和 API 用于核对；没有实际安装 KOReader/插件，未测残影、延迟、耗电或 Leaf5+ 兼容性。正式源码身份与关键链接保存在[证据摘要](evidence/2026-10-25-eink-open-source.json)。完整公开源码摘取、API 响应和查询记录保存在本机同一任务的 evidence 目录，本仓库只保留必要摘要。

下一步仍建议先完成黑白 UI 和减少动态效果；硬件实验随后独立进行。新增插件/SDK依赖之前，先核对实际需要的是界面简化、图像处理还是面板刷新控制，三者不能相互替代。
