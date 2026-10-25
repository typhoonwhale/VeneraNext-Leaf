# Android 根层补白与阅读信息设置整理

## 结论与复现

用户在 Leaf5+ 手势导航下反馈：2372 版虽已将底栏内部文字底对齐，屏幕底部仍留白。核查发现此前只验证了底栏组件及 ReaderScaffold，遗漏 `main.dart` 的全局 MediaQuery 兼容处理：`viewPadding.top <= 0 || viewPadding.top > 200` 时，会将 padding 和 viewPadding 全部替换为上下各15、左右0。

全屏下顶部0是有效值。底栏将应用注入的bottom=15当作真实遮挡，形成额外白边。回归将生产根层处理接入 ReaderScaffold，旧逻辑下设置高度18、系统padding=0，实测组件高度33，断言失败；修复后高度18且文字行框贴底。该数值来自widget测试，不是实机WindowInsets采集。

## 修复范围

- 根层兼容逻辑提取为 [AndroidWindowInsets](../../lib/app_shell/android_window_insets.dart)，由 [main.dart](../../lib/main.dart) 仅在Android使用。
- 正常零边距原样传递；不将systemGestureInsets转换为底部占位。
- 保留原有 `viewPadding.top > 200` 的顶部异常兼容，仅修正顶部为15，保留其他三边及viewInsets、显示比例；顶部padding同时尊重viewInsets.top遮挡。
- 原引用 [Flutter issue 161086](https://github.com/flutter/flutter/issues/161086) 描述小米14/HyperOS2/Android15小窗模式出现top=640。本次查询仍为open；它不证明Leaf5+需要固定补白，也不证明top=0异常。保留200/15是既有兼容策略，不是通用硬件参数，小米实机未复测。
- 设置页将显示模式、时间/电量、页码、书名/章节名、高度和字号放入同一个连续区块；保留所有键、值、回调和全局/设备/单漫画作用域。
- 未修改导航宽度阈值、DPI、底栏字号/高度范围、字体行框或真实底部安全区。

## 全链路检查

1. Android Activity/主题没有发现额外固定15底部补白；原生系统栏由Flutter SystemChrome控制。
2. 根层 `MaterialApp.builder` 是本问题的合成边距来源；桌面WindowFrame的标题栏padding不适用于Android。
3. 路由/主导航/OverlayWidget未发现对阅读路由再次固定增加底部15；主导航自身按600逻辑宽度切换，独立于本修复。
4. 阅读器平台策略：菜单打开或用户要求显示系统状态栏时使用edgeToEdge，否则immersive；退出/重入通过平台effects owner恢复。
5. ReaderScaffold将底栏放在正文外；正文子树清除已由底栏消费的bottom padding，底栏仍读取父级真实padding，防止重复预留。
6. ReaderInformationFooter只在底部预留一次真实padding；文本行框底对齐。菜单/进度条/章节页的安全区和键盘遮挡保留；叠加信息模式的原有13偏移不属于独立底栏，未改。
7. 字体行框仍可能含下伸空间；本修复消除人为15逻辑像素，不承诺所有字形墨迹贴到屏幕物理边缘。

## 验证

76项相关测试通过，静态分析及架构依赖检查通过。覆盖零边距、仅底部系统栏、左右安全区、系统手势区、键盘、不同逻辑尺寸/DPR、异常顶部、根层到正文/底栏、菜单开关、平台effects退出恢复，以及设置持久化与继承。模拟metrics不替代Android实机验证。

```sh
flutter test --no-pub test/app_runtime/android_window_insets_test.dart test/features/reader/information_overlay_test.dart test/features/reader/platform_effects_test.dart test/features/reader/platform_effects_controller_test.dart test/features/reader/settings_effects_test.dart test/features/settings/reader_settings_persistence_test.dart test/foundation/reader_preference_store_test.dart
flutter analyze --no-pub
python3 .github/scripts/check_architecture_dependencies.py
```

本机任务证据保留首次沙箱Flutter宿主崩溃、旧逻辑断言失败（18→33）、修复后测试日志及链路审计。未将测试日志中的本机路径放入仓库。

## 实机待核验

固定签名Release将构建号递增为238，ARM64版本码2382。安装后在相同DPI、相同字号/高度下对照2372，检查关闭菜单的底栏空白、打开菜单再关闭、横竖屏和退出重进。真实固件边距、墨水屏刷新、覆盖安装的数据保留仍需用户实测。若仍有白边，应采集实际padding/viewPadding/viewInsets及截图，不再猜测固定安全区值。
