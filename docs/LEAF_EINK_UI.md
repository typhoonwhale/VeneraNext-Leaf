# Leaf 墨水屏 UI 组件索引与修改指南

更新：2026-10-29。随 1.19.0 发布。本文行号以 1.19.0 发布提交为准，改动后请同步。阶段与耗电约束见[开发路线图](LEAF_EINK_ROADMAP.md)，官方 SDK 约束见[核心约束](LEAF_EINK_GUIDELINES.md)。

## 1. 概述

墨水屏模式是应用内的一个外观开关：黑白高对比主题 + 减少动画。入口在「设置 → 外观 → 墨水屏模式」，**默认开启**（`lib/foundation/application_preferences.dart:95`）。关闭后恢复原有彩色主题和动画，`theme_mode`、`color` 两个已有偏好不被改写。

影响范围：

- 黑白主题：单色 `ColorScheme`、描边代替填充色和阴影、选中态黑底白字、封面黑边直角、按钮统一胶囊形。
- 减少动画：路由、弹层、对话框、渐显、循环动画（转圈、五点、骨架屏闪光、下载图标）和程序化滚动直接显示最终画面。

不处理：漫画正文图片、阅读底栏、软件闪屏，详见第 5 节。开启时「主题模式」「主题颜色」两项禁用并提示“墨水屏模式下固定为黑白”（`lib/features/settings/appearance.dart:23,35-38,49-52`）。

## 2. 整体机制

### 2.1 偏好与派生量

| 项 | 内容 | 位置 |
|---|---|---|
| 定义 | `AppearancePreferences.eInkMode = BoolPreference('eInkMode', true)`，加入 `AppearancePreferences.all`；非 bool 值回退默认 true | `lib/foundation/application_preferences.dart:95-96` |
| 存储 | `appdata.json` → `settings.eInkMode`；默认值经 `applicationPreferenceDefaults` 进入 `Settings._data`，旧版本覆盖安装后文件里没有该键，自动取 true | `lib/foundation/application_preferences.dart:254`，`lib/foundation/appdata.dart:619` |
| 本机字段 | `'eInkMode'` 在 `appDataLocalFields` 中：导入备份和同步既不读取也不覆盖它。原因：从手机端（模式关闭）导入备份时，Leaf 上的墨水屏模式不应被关掉 | `lib/foundation/app_data_sync_fields.dart:16` |
| 快照 | `AppearanceConfiguration.eInkMode` | `lib/foundation/application_configuration.dart:43-48` |
| 派生量 | `einkTheme`（黑白主题）和 `reduceMotion`（减少动画）目前都等于 `eInkMode`。两个 getter 是预留的拆分点：以后要分成两个开关，只改设置页和这两个 getter | `lib/foundation/application_configuration.dart:52,55` |
| 开关 UI | `SwitchSetting.preference`，切换后 `appNavigation.forceRebuild()` 重建 `MaterialApp` | `lib/features/settings/appearance.dart:27-34` |
| 文案 | 三条英文 key，`zh_CN` / `zh_TW` 各一份；`test/foundation/translations_test.dart` 会检查 `.tl` 字面量在两个 map 中都有翻译 | `assets/translation.json:182-184,1091-1093` |

### 2.2 主题切换路径

1. `lib/main.dart:361-362` 读取 `appearance`，得到 `eink`。
2. `getTheme(..., eink:)`（`lib/main.dart:536`）：`eink` 为 true 时 `colorScheme` 用 `einkColorScheme()`（不再用 seed 色），最后 `applyEInkTheme(theme)`（`lib/main.dart:592`）叠加组件主题。
3. `MaterialApp` 的 `theme` 和 `darkTheme` 都传 `eink`；`themeMode` 固定 `ThemeMode.light`（`lib/main.dart:386`）；`themeAnimationDuration` 为 `Duration.zero`（`lib/main.dart:382`），切换主题时不做渐变。
4. `applyEInkTheme` 末尾注册 `EInkStyle(enabled: true)` 扩展（`lib/foundation/eink_theme.dart:604`），`context.isEInk` 由它读出。

`getTheme` 是 `main.dart` 的顶层函数，测试用 `getTheme(..., eink: true/false)` 直接构造主题。

### 2.3 判断入口

| 场景 | 用法 | 说明 |
|---|---|---|
| 有 `BuildContext`，判断是否黑白 | `context.isEInk`（`lib/foundation/eink_theme.dart:299`） | 读主题扩展，主题变化时自动重建；绝大多数组件用这个 |
| 有 `BuildContext`，判断是否停动画 | `MediaQuery.disableAnimationsOf(context)` | 读 builder 覆盖后的标志，同时兼容系统层设置 |
| 无 `BuildContext`（getter、`PopupRoute.barrierColor`、`transitionDuration`） | `EInkPreferences.einkTheme` / `EInkPreferences.reduceMotion`（`lib/foundation/eink_theme.dart:9,12`） | 直接读 `appdata.settings`，不随主题重建；只用于路由层的时长和遮罩 |
| 取选中态颜色 | `context.einkStyle.selectedBackground` / `selectedForeground`（`lib/foundation/eink_theme.dart:319`） | 仅 `isEInk` 为 true 时有意义 |

### 2.4 减少动画的机制

- `MaterialApp.builder` 中始终包一层 `EInkReduceMotion(enabled: reduceMotion)`（`lib/main.dart:488-491`，组件在 `lib/foundation/eink_theme.dart:59-77`）：enabled 时覆盖 `MediaQuery(disableAnimations: true)`，否则把原 `MediaQuery` 数据原样透传。包装层常驻，切换开关不改变树结构，下层 `State` 不会被重建，依赖也只局限在这个小组件内。凡是读 `MediaQuery.disableAnimationsOf` 的地方（菜单、阅读器菜单、章节切换按钮等）在任何系统设置下都生效。
- Android 嵌入层会读 `Settings.Global.transition_animation_scale`，值为 0 时把 Flutter 的 `disableAnimations` 置 true；只看这一项，不看 `animator_duration_scale`。这个平台标志还会让 `AnimationController.animateTo` 只跑 5% 时长，300ms 转场约剩 15ms，通常留一两帧中间画面。
- 应用内覆盖只改 `MediaQuery`，**不改**上述 5% 缩放（后者读 `SemanticsBinding`）。所以显式写了 `Duration` 的地方要逐处改成 `Duration.zero`。
- 系统缩放管不到两类动画：`repeat()` 产生的循环动画（转圈、五点、骨架屏闪光、下载图标）；`AnimationController.unbounded` 驱动的滚动动画（`animateTo`、`animateToPage`、惯性）。这两类必须在应用内处理，见 4.4 节清单。
- 需要应用内开关的原因：系统标志依赖用户全局设置，一旦恢复为 1 就失效；循环和滚动动画不受它控制；5% 缩放仍有中间帧。

## 3. 统一调节点

想改全局外观，优先改这些常量和函数，组件会跟着变。除特别注明，位置都在 `lib/foundation/eink_theme.dart`。

| 想改什么 | 改哪里 | 位置 | 当前值 |
|---|---|---|---|
| 普通描边宽度（标签、徽标、卡片、输入框、chip、按钮、封面） | `EInkStyle.strokeWidth` | `:252` | 2.0 |
| 强调描边宽度（对话框、弹层、FAB、Toast、flyout） | `EInkStyle.strongStrokeWidth` | `:255` | 3.0 |
| 禁用控件斜线遮罩（线间距、线宽） | `EInkStyle.hatchSpacing`、`EInkStyle.hatchStrokeWidth` | `:264`、`:258` | 10.0（线中心垂直距离）、`strokeWidth`；斜线由 `EInkHatch` / `EInkHatchPainter`（`:96`、`:140`）绘制，标签文字描白边 `einkHaloLabel`（`:227`） |
| 章节已读对勾（大小、线宽） | `EInkStyle.checkMarkSize`、`EInkStyle.checkMarkStrokeWidth` | `:267` | 14.0、2.5；`EInkCheckMark`（`:609`）用 CustomPaint 画圆头粗勾，替代字体里偏细的 ✓ 字符 |
| 禁用控件文字白边宽度 | `EInkStyle.hatchHaloWidth` | `:261` | 3.0（文字向外扩展的白边，逻辑像素）；文字用白色描边层叠黑字实现，图标用 16 方向白色硬阴影。白边层是装饰：`einkHaloStack`（`:181`）给它套 `TickerMode(enabled: false)`、`ExcludeSemantics`、`IgnorePointer`；`einkHaloSafe`（`:197`）发现子树含 `StatefulWidget`、进度圈或 `GlobalKey` 时 `einkHaloLabel` 不生成副本，只保留斜线 |
| 单色配色 | `einkColorScheme()` | `:319-355` | 见下表 |
| 全局字重 | `_einkTextTheme`：所有样式不低于 w500，字号 ≤ 12 的不低于 w600，字号不变 | `:381-410`；`textTheme`、`primaryTextTheme` 在 `:449-450` 应用 | w500 / w600 |
| 硬编码小字的字重 | `context.einkSmallText(style)`，不继承主题字重的 `TextStyle` 用它包一层 | `:307` | w600 |
| 封面圆角 | `context.einkCoverRadius(normal)` | `:311` | `BorderRadius.zero` |
| 封面和标签的黑边 | `context.einkBorder({width})` | `:302` | `strokeWidth` 黑色 |
| 角标实心填充色 | `context.einkBadgeColor(color)` | `:298` | `Colors.black` |
| 按钮形状 | `buttonShape = StadiumBorder(side: border)`，用于 text/outlined/filled 三种按钮 | `:427`；自绘 `Button` 的圆角在 `lib/components/button.dart:226` | 胶囊形（自绘 `Button` 为 999） |
| 按钮描边（含禁用态） | `buttonSide` | `:428` | 启用、禁用都是黑色 `strokeWidth` |
| 按钮禁用态 | `hatchBackground` / `hatchForeground`（`backgroundBuilder` / `foregroundBuilder`，禁用时画斜线、文字描 3px 白边），`disabledForeground`（文字黑色） | `:429-447` | 黑框 + 45° 斜线 + 黑字 |
| 选中态颜色 | `EInkStyle.selectedBackground` / `selectedForeground` | `:264-275` | 黑 / 白 |
| 选中态之外的黑白分档 | `segmentedButtonTheme` 的 selected 判断 | `:580-599` | 选中黑底白字，未选中白底黑字；禁用时一律白底黑字，斜线由 segment 内部的 `textButtonTheme` 提供 |
| 卡片 | `cardTheme`：elevation 0，`shape`（圆角 12，`strokeWidth` 描边） | `:564`，`shape` 在 `:419` | |
| 对话框 | `dialogTheme`：透明遮罩，elevation 0，`strongShape`（圆角 12，`strongStrokeWidth`） | `:559-563`，`strongShape` 在 `:423` | |
| FAB | `floatingActionButtonTheme`：白底黑字，全部 elevation 0，圆角 16，`strongBorder` | `:567-579` | |
| SegmentedButton | `segmentedButtonTheme` | `:580-599` | |
| Chip | `chipTheme.side` | `:485` | `border` |
| Switch | `switchTheme`：轨道黑色描边；禁用时白轨道 + 黑框 + 空心圆环 thumb（轨道太窄画不出斜线） | `:486-502` | `strokeWidth` |
| text 按钮 | `textButtonTheme`（另有 padding 16×8） | `:451-462` | 胶囊 + 描边；禁用斜线 |
| outlined 按钮 | `outlinedButtonTheme` | `:463-471` | 胶囊 + 描边；禁用斜线 |
| filled 按钮 | `filledButtonTheme`：背景走 `primary`（黑），禁用时白底黑框黑字加斜线 | `:472-484` | 胶囊 |
| 弹出菜单 | `popupMenuTheme`：elevation 0，`shape` | `:565` | |
| SnackBar | `snackBarTheme`：elevation 0，`shape` | `:566` | |
| 路由转场（`MaterialPageRoute`、`PageRouteBuilder` 默认） | `pageTransitionsTheme`：所有平台用 `_NoTransitionsBuilder` | `:553-558`，builder 在 `:358-370`，`transitionDuration`、`reverseTransitionDuration` 均覆盖为 `Duration.zero`（`MaterialPageRoute` 从 builder 读取时长，默认 300ms） | 直接返回 child，pop 后下一帧旧页面消失 |
| 点击反馈 | `splashFactory: NoSplash.splashFactory`，`highlightColor` 透明 | `:551-552` | 无水波纹 |
| 应用自有路由转场 | `AppRoute` 的 `transitionDuration`、`reverseTransitionDuration`、`buildTransitions` | `lib/foundation/app_page_route.dart:62,67,132` | `reduceMotion` 时 0 / 直接返回 child |
| 弹层遮罩 | 对话框走 `dialogTheme.barrierColor`；`PopUpWidget`、`SideBarRoute`、收藏夹侧栏各自判断 `EInkPreferences.einkTheme` | `lib/components/pop_up_widget.dart:28`，`lib/components/side_bar.dart:55`，`lib/features/favorites/favorites_page.dart:128` | 透明 |
| `useTextColor` / `useBackgroundColor`（详情页彩色图标、标签色板、点赞/踩的集中入口） | `lib/foundation/context.dart` | `:77-85` | `onSurface` / `surface` |
| 毛玻璃 | `BlurEffect` | `lib/components/effects.dart:22` | `isEInk` 时直接返回 child |
| 静态进度圈 | `EInkProgressIndicator`：`disableAnimations` 且 `value` 为 null 时显示半圈 | `:19-54` | `value: 0.5`；`value`、`strokeWidth`、`color`、`valueColor`、`backgroundColor`、`semanticsLabel`、`semanticsValue`、`strokeCap` 原样传给 `CircularProgressIndicator`，未指定的保持 null |
| 减少动画包装 | `EInkReduceMotion(enabled, child)`，常驻树中 | `:59-77` | enabled 时 `disableAnimations: true` |
| 组件补间时长 | `tweenDuration(context, [normal])` | `lib/components/consts.dart:5-9` | `disableAnimations` 时 `Duration.zero`，否则 `fastAnimationDuration`（160ms） |
| 禁用态文字、图标颜色 | `disabledColor: Colors.black`；`ListTile`、`IconButton`、`InputDecoration`（label、helper、hint、前后缀图标）的禁用态为黑 | `:503-532` | 黑，不再是 38% 灰；`iconButtonTheme` `:506-508`，`inputDecorationTheme` `:509-532` |
| 禁用 Checkbox、Slider | `checkboxTheme`（禁用选中黑底白勾，未选中白底；描边 `border`）、`sliderTheme`（禁用：已填充黑、未填充白、滑块黑） | `:533-550` | |

`einkColorScheme()` 取值：

| token | 值 | 原因 |
|---|---|---|
| `primary` / `onPrimary` | 黑 / 白 | 填充按钮、Switch 打开态变黑底白字，和文石控制中心的激活态一致 |
| `primaryContainer`、`secondaryContainer`、`tertiaryContainer`、`errorContainer` 及对应 `on*` | 白 / 黑 | 这些 token 常用作封面占位底、徽标底、直接放默认颜色文字的容器；改黑会出现大面积黑块（增加残影）或黑底黑字。选中态由 `EInkStyle` 单独处理 |
| `secondary`、`tertiary`、`error` | 同 `primary` | 错误状态靠图标和文字区分，不靠红色 |
| `surface` 及全部 `surfaceContainer*`、`surfaceDim`、`surfaceBright` | 白 | 去掉淡紫和浅灰底色，区分靠描边 |
| `onSurface`、`onSurfaceVariant` | 黑 | 次要文字靠字号和字重区分，不用浅灰 |
| `outline`、`outlineVariant` | 黑 | 卡片边框和分隔线 |
| `shadow`、`surfaceTint` | 透明 | 去掉阴影和 Material 3 色调叠加 |
| `scrim`、`inverseSurface`、`onInverseSurface`、`inversePrimary` | 黑、黑、白、白 | Snackbar 等反色控件保持黑底白字 |

## 4. 组件索引

“实现方式”列：**主题** 表示走 `applyEInkTheme` 统一生效，无需单独分支；**分支** 表示组件内部有 `isEInk` 或 `disableAnimations` 判断。

### 4.1 全局主题

| 组件/位置 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 配色 | 单色 `ColorScheme`，固定浅色 | 主题 | `lib/foundation/eink_theme.dart:323`，`lib/main.dart:386` |
| 文字 | 字重下限 w500，小字 w600 | 主题 | `lib/foundation/eink_theme.dart:385` |
| 按钮（text / outlined / filled / tonal） | 胶囊形，2 描边；禁用黑框黑字，内部 45° 斜线，文字描 3px 白边 | 主题 | `lib/foundation/eink_theme.dart:431-488` |
| 卡片、弹出菜单、SnackBar | elevation 0 + 描边圆角 12 | 主题 | `lib/foundation/eink_theme.dart:568-570` |
| 对话框（`showDialog`） | 透明遮罩，3 描边，elevation 0 | 主题 | `lib/foundation/eink_theme.dart:563` |
| FAB | 白底黑字，3 描边，无阴影 | 主题 | `lib/foundation/eink_theme.dart:571` |
| SegmentedButton、Chip、Switch | 选中黑底白字、黑描边；Switch 禁用为白轨道 + 空心圆环 | 主题 | `lib/foundation/eink_theme.dart:489-506,584` |
| 路由转场、水波纹 | 无转场、无水波纹 | 主题 | `lib/foundation/eink_theme.dart:555-562` |
| 主题切换渐变 | 关闭 | 分支 | `lib/main.dart:382` |
| `useTextColor` / `useBackgroundColor` | 返回 `onSurface` / `surface`，详情页图标、标签色板、评论点赞/踩、稍后阅读变黑白 | 分支 | `lib/foundation/context.dart:77-85` |

### 4.2 公共组件（`lib/components`）

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| `Button`（自绘） | 胶囊（圆角 999）、左右 padding 18、`strokeWidth` 描边；`filled` 类型保持黑底无额外描边，其余类型黑描边；给定 `width`/`height` 时墨水屏下扣除两侧描边（`einkOutline`，`:176-187`），外形尺寸等于给定值，普通模式不扣除 | 分支 | `lib/components/button.dart:173-187,226,241-249` |
| `BlurEffect` | 不做毛玻璃 | 分支 | `lib/components/effects.dart:22` |
| `Select` 禁用态（`enabled: false`） | 黑 2 描边 + 斜线，文字和箭头描 3px 白边；`SelectSetting` 禁用时传入；启用态描边墨水屏下为 `strokeWidth`、普通模式 1（`:127-129`）；窄屏版式 `_DoubleLineSelectSettings`（宽度 < 450）禁用时同样黑框 + 斜线，标题、副标题、箭头、帮助图标描白边（`lib/features/settings/setting_components.dart:360-467`） | 分支 | `lib/components/select.dart:33-58,60,125-146`，`lib/features/settings/setting_components.dart:568` |
| `Select` 下拉菜单 | `surface` 底、2 描边、圆角 4、无阴影 | 分支 | `lib/components/select.dart:68-86` |
| `FilterChipFixedWidth` | 选中黑底白字，2 描边 | 分支 | `lib/components/select.dart:194-216`；背景和图标位移补间用 `tweenDuration`（`:195,204,239`），`AnimatedCheckIcon` 在 `disableAnimations` 下首帧即画满（`:322-326`） |
| `AnimatedCheckWidget` 勾选图标 | 选中态前景色白 | 分支 | `lib/components/select.dart:281-282` |
| `OptionChip` | 选中黑底白字；描边始终 2 | 分支 | `lib/components/select.dart:358-376,386`；`AnimatedContainer` 用 `tweenDuration`（`:359`） |
| 底部导航选中指示器 | 黑底白图标；`controller.duration` 在无动画时为 0 | 分支 | `lib/components/navigation_bar.dart:586-609,543` |
| 侧边导航选中项 | 黑底白图标白字 | 分支 | `lib/components/navigation_bar.dart:434-457` |
| 主内容切换 `AnimatedSwitcher` | 无动画时时长 0 | 分支 | `lib/components/navigation_bar.dart:805` |
| `SideBarRoute` 侧边面板 | 直角、仅左侧 2 描边（全宽时无边）、透明遮罩、时长 0 | 分支 | `lib/components/side_bar.dart:55,134-147,258` |
| `PopUpWidget` | 透明遮罩、3 描边、时长 0 | 分支 | `lib/components/pop_up_widget.dart:28,56,99` |
| `Flyout` | 时长 0、透明遮罩、`surface` 不透明底、3 描边 | 分支 | `lib/components/flyout.dart:114,164,217-232` |
| `ContentDialog` | 3 描边、elevation 0 | 分支 | `lib/components/message.dart:534,546` |
| Toast | elevation 0 | 分支 | `lib/components/message.dart:92` |
| `showDialogMessage` / `showConfirmDialog` / `showInfoDialog` | 无动画时传 `AnimationStyle.noAnimation` | 分支 | `lib/components/message.dart:222-223,228,247,579` |
| `SummaryHeader` 计数徽标 | 白底 + 黑描边 | 分支 | `lib/components/summary_header.dart:38` |
| `SmoothScrollProvider` 滚动条/滚轮 | 无动画时 `jumpTo` | 分支 | `lib/components/scroll.dart:172` |
| `AnimatedImage` 封面/缩略图渐显 | 无动画时时长 0 | 分支 | `lib/components/image.dart:331` |
| `LoadingState`、`MultiPageLoadingState` | 用 `EInkProgressIndicator`（静态半圈） | 分支 | `lib/components/loading.dart:172,350` |
| `FiveDotLoadingAnimation` | 无动画时不 `repeat`，画五个静态黑点；墨水屏下始终黑点 | 分支 | `lib/components/loading.dart:410-420,469` |
| 右键/长按菜单 | 原已读 `disableAnimationsOf` | 分支 | `lib/components/menu.dart:55` |

### 4.3 页面

**主页与书架**

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| `LocalComicsSummary` 等四张主页摘要卡 | 计数徽标白底黑描边 | 分支 | `lib/features/local_comics/local_comics_summary.dart:94`，`lib/features/comic_source/comic_source_summary.dart:79`，`lib/features/image_favorites/image_favorites_summary.dart:111`，`lib/components/summary_header.dart:38` |
| 下载中图标 | 无动画时停在静态图标 | 分支 | `lib/features/local_comics/local_comics_summary.dart:387` |
| 图片收藏统计条 | 去渐变，白底 + 黑描边 | 分支 | `lib/features/image_favorites/image_favorites_summary.dart:300-305` |
| 同步状态错误图标 | `onSurface` 代替红色 | 分支 | `lib/features/sync/sync_status_summary.dart:88` |
| 收藏夹侧栏 | 选中黑底白字；数量徽标加 2 描边 | 分支 | `lib/features/favorites/side_bar.dart:270,289,299,334,350` |
| 收藏夹弹出面板 | 时长 0、透明遮罩 | 分支 | `lib/features/favorites/favorites_page.dart:117,128` |

**漫画卡片（`lib/features/comic_widgets/comic_tile.dart`）**

| 位置 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 更新、收藏、历史页码三种角标 | 黑底（白图标/白字） | 分支 `einkBadgeColor` | `:175,373,390` |
| 详情模式封面（`_buildDetailedMode`） | 直角、2 黑边、无阴影 | 分支 | `:447-449` |
| 简略模式封面（`_buildBriefMode`） | 同上；封面上的半透明遮罩改纯黑 | 分支 | `:513-515,584` |
| 画廊模式封面（`_buildGalleryMode`） | 同上 | 分支 | `:650-652` |
| `SimpleComicTile` 封面 | 直角、2 黑边 | 分支 | `:1210-1211` |
| 描述、副标题、标签、徽章文字 | `einkSmallText`（w600）；副标题去半透明；标签 2 描边 | 分支 | `:916,946-949,991,999,1038,1157` |

**漫画详情与章节**

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 详情页封面 | 直角、2 黑边、无阴影；骨架屏封面同样 | 分支 | `lib/features/comic_details/comic_page.dart:365-369,1042-1044` |
| 来源名文字 | `einkSmallText` | 分支 | `lib/features/comic_details/comic_page.dart:409` |
| 信息区标签（可点击） | 白底（`useBackgroundColor`）+ 2 描边 | 分支 | `lib/features/comic_details/comic_page.dart:637,651-660` |
| 信息区键名（不可点击） | 2 描边 | 分支 | `lib/features/comic_details/comic_page.dart:699` |
| “下载”/“阅读”/“继续”按钮 | 走 `filledButtonTheme`：“下载”（tonal）白底黑描边；“阅读/继续”（filled）黑底白字 | 主题 | `lib/features/comic_details/comic_page.dart:492-516` |
| 操作按钮行（收藏、评论等） | 2 黑描边代替 0.6 浅灰描边 | 分支 | `lib/features/comic_details/action_button.dart:59` |
| 评论头像框 | 2 描边 | 分支 | `lib/features/comic_details/comments_page.dart:389` |
| 章节格子（普通和分组两种） | 直角 4、2 描边；未读白底黑框黑字；上次读到（`history.ep`，分组时同时匹配 `history.group`）黑底白字，整页最多一个；其他已读白底黑框，标题前固定显示粗对勾 `EInkCheckMark`，加 4 间距（Row + Flexible，标题过长时省略号，对勾不被截断）；文字 w600。普通模式不变 | 分支 | `lib/features/comic_details/chapters.dart:19-67,249-283,470-513` |
| 回到顶部 | 无动画时 `jumpTo(0)` | 分支 | `lib/features/comic_details/comic_page.dart:233` |
| 骨架屏闪光 | 无动画时 `Shimmer(enabled: false)` | 分支 | `lib/features/comic_details/comic_page.dart:976`，`lib/features/comic_details/favorite.dart:309` |

**搜索**

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 搜索入口 | 白底胶囊 + 2 描边 | 分支 | `lib/features/search/search_entry.dart:23-30` |
| 聚合搜索骨架屏 | 无闪光 | 分支 | `lib/features/search/aggregated_search_page.dart:198` |

**收藏、本地漫画**：见上文主页摘要卡、收藏夹侧栏、漫画卡片；卡片和侧栏组件被收藏页、本地漫画页、历史页、搜索结果共用，改一处全局生效。

**设置**

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 设置侧栏选中项 | 黑底白字白图标 | 分支 | `lib/features/settings/settings_page.dart:165-190` |
| 下拉设置项的弹出菜单 | `surface` 底、2 描边、圆角 4、无阴影 | 分支 | `lib/features/settings/setting_components.dart:405-418` |
| 多页筛选面板 | 去 `BoxShadow` | 分支 | `lib/features/settings/setting_components.dart:770` |
| 保存中指示器 | `EInkProgressIndicator` | 分支 | `lib/features/settings/setting_components.dart:21` |
| 外观页禁用项 | `SelectSetting` 新增 `enabled`、`subtitle` 参数 | 分支 | `lib/features/settings/setting_components.dart:191,257`，`lib/features/settings/appearance.dart:37,51` |

**阅读器**（底栏见第 5 节）

| 组件 | 墨水屏样式或行为 | 实现 | 文件:行 |
|---|---|---|---|
| 顶栏 | 不透明 `surface`，底边 2 黑线 | 分支 | `lib/features/reader/top_bar.dart:25-35` |
| 底部操作栏（页码滑条所在条） | 不透明 `surface`，顶边 2 黑线（仅菜单打开时） | 分支 | `lib/features/reader/progress_bar.dart:124-139` |
| 图片加载失败的“重试” | 主色加下划线，不用蓝色 | 分支 | `lib/features/reader/comic_image.dart:383` |
| 低电量图标 | 保持黑色，不用红色 | 分支 | `lib/features/reader/status_info.dart:137` |
| 画廊页加载圈 | `EInkProgressIndicator` | 分支 | `lib/features/reader/gallery_view.dart:424` |
| 连续模式定位、翻页键滚动 | 无动画时 `jumpTo`，目标夹在滚动范围内 | 分支 | `lib/features/reader/continuous_view.dart:1155,1293` |
| 亮度面板展开 | 无动画时时长 0 | 分支 | `lib/features/reader/brightness.dart:110` |
| 阅读器菜单、章节按钮、侧栏等 | 原已读 `disableAnimationsOf`，由 builder 覆盖稳定为无动画 | 分支（原有） | `lib/features/reader/scaffold.dart:219`，`lib/features/reader/chapter_navigation_button.dart:25`，`lib/features/reader/chapters.dart:27`，`lib/features/reader/sidebar_binding.dart:99` |

**弹层与对话框**：见 4.2 节 `ContentDialog`、`Flyout`、`PopUpWidget`、`SideBarRoute`、`Select`；`showDialog` 的遮罩和形状走主题，时长受系统缩放影响，见第 8 节。

**加载状态**：`LoadingState` / `MultiPageLoadingState` 转圈、`FiveDotLoadingAnimation`、`Shimmer`、下载图标，见 4.2 和 4.4 节。

### 4.4 动画处理清单

| 动画 | 处理 | 文件:行 |
|---|---|---|
| 主路由 300ms | `transitionDuration` / `reverseTransitionDuration` 为 0，`buildTransitions` 直接返回 child | `lib/foundation/app_page_route.dart:62,67,132` |
| `MaterialPageRoute` 等 | 主题 `_NoTransitionsBuilder`，两个时长均为 0 | `lib/foundation/eink_theme.dart:362-374,557-562` |
| `PopUpWidget`、`SideBarRoute`、`Flyout`、收藏夹面板 | 时长 0 | `lib/components/pop_up_widget.dart:99`，`lib/components/side_bar.dart:258`，`lib/components/flyout.dart:120-124`，`lib/features/favorites/favorites_page.dart:117-126` |
| 封装对话框（message.dart 三个入口） | `AnimationStyle.noAnimation` | `lib/components/message.dart:222-223,228,247,579` |
| 封面/缩略图渐显 200ms | 时长 0 | `lib/components/image.dart:331` |
| 导航切换和底栏选中 | 时长 0 | `lib/components/navigation_bar.dart:543,805` |
| 亮度面板 `AnimatedSize` | 时长 0 | `lib/features/reader/brightness.dart:110` |
| 转圈（`CircularProgressIndicator` 无限旋转） | `EInkProgressIndicator`：半圈静态；有 `value` 时原样。`lib/` 下所有 `CircularProgressIndicator` 均已替换（如 `lib/features/reader/images.dart:125,129`、`lib/features/reader/continuous_view.dart:768`、`lib/features/reader/comic_image.dart:512`、`lib/features/comic_widgets/comic_list.dart:680,727`、`lib/features/discovery/explore_page.dart:591`、`lib/features/comic_details/comments_page.dart:145`、`lib/components/button.dart:194,343`、`lib/features/comic_details/action_button.dart:74`、`lib/features/favorites/favorite_transfer_dialog.dart:305`） | `lib/foundation/eink_theme.dart:19` |
| 组件补间（`FilterChipFixedWidth`、`OptionChip`、`AnimatedCheckIcon`、`Button` 的 `AnimatedContainer`/`AnimatedSize`） | `tweenDuration(context)`：`disableAnimations` 时 0 | `lib/components/select.dart:195,204,239,324,359`，`lib/components/button.dart:221,252` |
| 五点加载（`repeat`） | `didChangeDependencies` 中停止并归零，黑点 | `lib/components/loading.dart:410-420` |
| 下载中图标（`repeat`） | 同上 | `lib/features/local_comics/local_comics_summary.dart:387-393` |
| 骨架屏 `Shimmer` | `enabled: false`（3 处） | `lib/features/comic_details/comic_page.dart:976`，`lib/features/comic_details/favorite.dart:309`，`lib/features/search/aggregated_search_page.dart:198` |
| 回到顶部、滚轮/滚动条、连续模式定位和翻页键 | `jumpTo` | `lib/features/comic_details/comic_page.dart:233`，`lib/components/scroll.dart:172`，`lib/features/reader/continuous_view.dart:1155,1293` |
| 主题切换渐变 | `themeAnimationDuration` 为 0 | `lib/main.dart:382` |
| 水波纹 | `NoSplash` | `lib/foundation/eink_theme.dart:555` |

## 5. 明确不改的地方

| 位置 | 原因 |
|---|---|
| 阅读底栏 `lib/features/reader/information_footer.dart` | 它已在浅色下显式使用黑字、白底、黑分隔线，且底栏的间隔、字号、高度由用户设置，并按字体度量文字宽度。全局字重下限（w500）会经 `DefaultTextStyle` 改变这些度量，所以 `:40` 显式固定 `FontWeight.w400`，保证墨水屏下底栏与普通浅色模式逐像素一致。`test/features/reader/eink_reader_test.dart` 的 T12 固定这一点 |
| 漫画正文图片 | 不加滤镜、灰度化、阈值化、模糊，不改预加载和缓存；T13 检查正文图片组件树中没有 `ColorFilter`、shader 或 `BackdropFilter` |
| 软件闪屏 `lib/features/reader/eink_refresh.dart`、`eink_refresh_controller.dart` | 只是在 Flutter 里盖一层纯色，不是面板硬件全刷；偏好默认关闭，墨水屏模式不联动它。它瞬时变色，不属于动画，与减少动画不冲突；以后接入硬件刷新时必须与它互斥 |
| 夜间调光遮罩 `lib/features/reader/brightness.dart` 中的亮度遮罩 | 用户主动开启的功能，保留原语义 |
| 反色辅助 `lib/features/reader/comic_image.dart` 中的 `ColorFilter` | 现有阅读辅助功能，不动 |
| 手势翻页物理和惯性（`BouncingScrollPhysics`、`PageView` 回弹） | 改 physics 会影响操作手感，列入后续阶段 |
| 画廊 `enablePageAnimation` 偏好 | 已有独立偏好，不覆盖用户设置 |
| 连续模式自动滚动的 smooth/stepped 选项 | 保留用户已有选择 |

## 6. 测试索引

测试都不依赖设备。运行单个文件：`flutter test <文件>`，例如 `flutter test test/foundation/eink_theme_test.dart`。

| 文件 | 覆盖 |
|---|---|
| `test/foundation/eink_hatch_test.dart` | 斜线段数量、45° 方向、端点在尺寸内；painter 按 shape 裁剪；白边：按钮、`Select` 白边层与黑字重合；禁用按钮子树是转圈时只有一个在跑的动画、白边副本的 ticker 被静音；子树带 `GlobalKey` 不报错；`einkHaloSafe` 的判定 |
| `test/foundation/eink_disabled_colors_test.dart` | 禁用 `ListTile`、`IconButton`、`TextField` 的文字和图标渲染后为纯黑（普通主题仍为灰）；Checkbox、Slider 禁用色；启用 `Select` 描边 2 / 1；固定宽高 `Button` 墨水屏下尺寸等于给定值，普通模式 outlined 仍多 0.6px×2 |
| `test/features/settings/eink_disabled_select_test.dart` | 宽（600）、窄（360）版式的禁用 `SelectSetting` 都有黑框 + 斜线；窄版标题、副标题、箭头有白边；普通主题无斜线 |
| `test/components/eink_tween_test.dart` | `FilterChipFixedWidth`、`OptionChip`、`Button` 的补间时长随 `disableAnimations` 为 0 / 160ms，勾选图标首帧画满且不再调度帧 |
| `test/foundation/eink_theme_test.dart` | T1 单色 `ColorScheme` 对比度配对；T2 主题关闭水波纹、遮罩和转场，`MaterialPageRoute` 立即切换，前进和返回时长均为 0、pop 后下一帧旧页面消失且不再调度帧（普通主题仍为 300ms）；T3 `use*Color`、`BlurEffect` 在墨水屏下收敛为黑白/无模糊；T4 选中态（`OptionChip`、`FilterChipFixedWidth`、`SummaryHeader` 徽标、FAB、`SegmentedButton`、导航选中）；描边宽度常量被主题引用；字重规则（小字 ≥ w600，其余 ≥ w500，浅色主题不变）；按钮胶囊形与描边、禁用态黑框黑字加斜线（可用按钮、非墨水屏无斜线）、禁用 `Select` 和 Switch、`Button.text` 描边；`einkBorder` |
| `test/foundation/eink_preferences_test.dart` | T5 默认开启且拒绝非 bool 值；T7 旧文件缺键时升级为开启，存储的 false 重启保留；T8 导入既不翻转也不接收本机的墨水屏选择 |
| `test/features/settings/eink_mode_setting_test.dart` | T6 开关持久化，主题模式/颜色两项被锁定 |
| `test/foundation/eink_motion_test.dart` | T9 平台标志关闭时应用开关仍生效：`AppRoute` 一帧内进出、对话框、菜单、`PopUpWidget` 逐帧开合；T10 循环动画（五点、下载图标、骨架屏、转圈）建立后不再调度帧，开关关闭时仍在动，确定性进度原样，`EInkProgressIndicator` 所有参数透传，静态五点为黑色；`EInkReduceMotion` 切换 enabled 时下层 `State` 实例不变 |
| `test/features/reader/eink_reader_test.dart` | T11 阅读器菜单一帧内开合；T12 底栏在墨水屏与浅色下一致（多组高度/字号）；T13 漫画图片无滤镜、shader、模糊 |
| `test/components/eink_sidebar_test.dart` | 侧边面板圆角：墨水屏直角，普通模式保留圆角 |
| `test/features/comic_details/action_button_test.dart` | 操作按钮描边宽度：墨水屏 `strokeWidth` 黑色，普通 0.6；其余用例是按钮语义/焦点原有测试 |
| `test/features/reader/eink_refresh_test.dart` | 软件闪屏（原有，非本次改动） |
| `test/foundation/translations_test.dart` | `.tl` 字面量在 `zh_CN`、`zh_TW` 都有翻译，新增文案后需通过 |

## 7. 修改指南

**加粗所有描边**：改 `EInkStyle.strokeWidth` / `strongStrokeWidth`（`lib/foundation/eink_theme.dart:252,255`）。主题、封面、标签、按钮、选中态都引用这两个常量，不需要逐处改。改完运行 `eink_theme_test.dart`；若需要不同于 2/3 的新档位，新增常量，不要在组件里写字面量。

**调整文字粗细**：全局改 `_einkTextTheme` 的 `floor`（`:384-385`）；个别硬编码 `TextStyle` 用 `context.einkSmallText` 包一层。改字重可能影响依赖字体度量的布局（如阅读底栏，已固定 w400）。

**新增组件需要墨水屏样式**：

1. 先用主题 token：颜色取 `colorScheme.*`，按钮用 `FilledButton` / `OutlinedButton` / `TextButton`，卡片用 `Card`，这样自动黑白。
2. 主题盖不到时（自绘 `Container`、`Material`、`InkWell`），在组件里用 `context.isEInk` 分支：描边用 `context.einkBorder()`，封面圆角用 `context.einkCoverRadius()`，角标填充用 `context.einkBadgeColor()`，选中态用 `context.einkStyle`，小字用 `context.einkSmallText()`，阴影在 `isEInk` 时设为 `null`。
3. 动画：时长写成 `MediaQuery.disableAnimationsOf(context) ? Duration.zero : 原值`；有 `repeat()` 的在 `didChangeDependencies` 里判断并 `stop()`；补间时长用 `tweenDuration(context)`；加载圈用 `EInkProgressIndicator`；程序化滚动用 `jumpTo`。
4. 无 `BuildContext` 的路由层（`barrierColor`、`transitionDuration`）用 `EInkPreferences`。
5. 补测试：以 `getTheme(..., eink: true/false)` 构造主题，两种模式都断言，参考 `test/components/eink_sidebar_test.dart`。

**发现某处还有颜色或阴影**：

1. 先判断它是否走主题 token：查该组件用的是 `colorScheme.xxx` 还是主题默认。token 已是黑白的，仍显示灰色/彩色多半是带了透明度（`toOpacity`、`withOpacity`）。
2. 再查硬编码：在组件文件里 `rg "Colors\.|Color\(0x|toOpacity|withOpacity|BoxShadow|elevation|BackdropFilter|LinearGradient"`，对照第 4 节清单看是否漏了。
3. 如果是第三方控件，看它读的是哪个主题字段，优先在 `applyEInkTheme` 补主题项；主题不支持再在调用处分支。
4. 如果是动态内容（漫画图片、第三方源返回的图标），属于第 5 节“不改”范畴。

**验证没有影响非墨水屏外观**：

1. 分支处都应是 `isEInk ? 新 : 原` 的形式，原值保持不变；`git diff` 里不应出现原分支行为变化。
2. 每个测试用 `eink: false` 构造一遍，断言原值（参考 `action_button_test.dart` 的 0.6 描边、`eink_sidebar_test.dart` 的圆角）。
3. 设置页关闭墨水屏模式，主题模式、主题颜色恢复可选，彩色主题和动画恢复；重新打开、强制重启后状态保持。
4. 非墨水屏下 `MediaQuery` 数据不应被改写：`lib/main.dart:488` 的 `EInkReduceMotion` 在 `enabled` 为 false 时原样透传。

## 8. 已知遗漏与后续方向

- 图片收藏页和缩略图网格的封面未加黑边直角处理（`lib/features/image_favorites/` 下 `AnimatedImage` 使用点，如 `image_favorites_item.dart:231`、`image_favorites_gallery_page.dart:275`）。
- 约 33 处直接调用的 `showDialog`（`lib/features/**`、`lib/components/js_ui.dart` 等）没有传 `animationStyle`，形状和遮罩走主题，开合时长仍依赖系统 `transition_animation_scale`（5% 缩放后一两帧）。统一做法是仿 `lib/components/message.dart:222` 传 `AnimationStyle.noAnimation`，或抽公共封装。
- `LinearProgressIndicator`（不确定进度时会循环动画）仍直接使用，如 `lib/features/reader/exit_guard.dart:226`、`lib/features/comic_source/source_repository_page.dart:587`、`lib/components/window_frame.dart:514`，未处理。
- 禁用 Slider 的已填充/未填充分别为黑/白，与启用态同一规则；禁用 Checkbox 选中为黑底白勾，与启用态外观接近，靠旁边文字和所在行的禁用样式区分。
- 白边副本只对可见子树做 `einkHaloSafe` 检查：自己构建子树的 `StatelessWidget`（如 `FilledButton.icon` 的内部 child）看不到内部，靠副本 ticker 静音兜底；若其内部含进度圈，副本会以静态形式叠在下面。
- Hero 在路由时长为 0 时按推断没有飞行帧，未实测；多帧动图在 `disableAnimations` 下按 Flutter 行为停在首帧，未实测。
- 文石 SDK 硬件全刷未接入，见[路线图](LEAF_EINK_ROADMAP.md)阶段 4；接入后必须与软件闪屏互斥。
- 耗电对照未做，按路线图在同条件下阅读 60 分钟对比。
- 用户已确认：去掉水波纹后点击反馈足够；描边加粗到 2/3 后不再偏细。若以后觉得过重，可以把 `outlineVariant` 改为深灰 `#404040`（`lib/foundation/eink_theme.dart:277`），或调小 `EInkStyle.strokeWidth`。

## 9. 实机验证记录

设备：Leaf5+，测试包版本码 2402 → 2412。

- 主页、漫画源、详情、阅读器菜单、设置、对话框均为纯黑白；选中项黑底白字；对话框无灰色蒙层，用 3 描边区分。
- SurfaceFlinger 统计：页面跳转、返回、开关菜单、点击翻页每次 2–3 帧；静止 5 秒 0–1 帧。
- 设备系统 `transition_animation_scale` 为 0，关闭墨水屏模式时页面跳转同样只有 2–3 帧。墨水屏模式的价值在于不再依赖系统设置，并停掉系统管不到的循环动画。
- 关闭开关后原彩色主题完整恢复；重新打开、强制重启后状态保持；覆盖升级后数据保留。
- 用户实机反馈驱动的调整：标签、刷新按钮、升序/降序选中态的遗漏补齐；加粗描边和字重；封面改直角加黑边；章节格子改黑白；按钮描边和胶囊形统一；侧边面板改直角。
- 用户反馈已读章节全部黑底太乱，改为“上次读到黑底，其他已读加 ✓”；已读的判定规则仍是上游的“打开即记录”，计划在后续版本单独调整。
- 字体自带的 ✓ 在设备上偏细，用户在细勾、图标库对勾、2.5px 和 3px 手画勾、黑圆白勾的预览中选定 2.5px 手画粗勾。
- 禁用控件样式：先后试过灰框灰字，改为黑框 + 45° 斜线 + 黑字描白边（用户在 2/3/4/5/6px 预览中选定 3px）；设备上禁用的“主题模式/主题颜色”下拉框和“下载选中”按钮待实机确认斜线观感（未实机验证）。
- “阅读/继续”主操作保持黑底白字（`filledButtonTheme`），“下载”等次要按钮为白底描边。
- 设备上系统的应用冻结机制会定时禁用并结束后台应用进程，可能打断后台下载；需在系统设置中把 Leaf 加入后台白名单（菜单位置未验证）。
