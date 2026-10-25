# 底栏分段布局与留白语义

## 用户确认的设计

2026-10-26，使用者明确：此前“底栏高度”意指文字下面的留白，而不是横线到屏幕底部的总高度。继续沿用总高度和文字底对齐，会把增量放在线条与文字之间，与需求相反。使用者进一步选择底部留白范围0–15，并根据真实组件渲染确认横线到文字区域的间隔为2。

固定结构：**横线1 → 固定间隔2 → 文字自然行框 → 可调底部留白0–15 → 系统真实bottom padding**。

- 底部留白默认4（实现初始值），可调0–15；字号仍9–13、默认11。所有值均为Flutter逻辑像素，会随DPI缩放，不等于屏幕物理像素。
- 横线与文字区域的间隔固定2，不增加用户设置。组件构造参数仅供预览1/2/3对照；生产接入始终使用默认2。
- 字号与text scaling只改变文字自然高度；不会改变线下间隔与设置的底部留白。宽度不足时仍分成两行，标题单行省略，页码不裁切。
- 同排文字行框顶对齐。不同字体/字形内部可能有升部、降部和leading，因此到字形墨迹的可见距离不保证逐字相同；固定2针对文字行框边界。多行信息的底部留白以整个文字区域下缘为准。
- 不再为满足总高度而分配额外弹性空间，也不再通过数字样本估计文字高度。仍保留最宽数字的水平宽度预留，尽量避免普通翻页/时钟宽度抖动；极窄屏文字自然换行时允许增加高度。
- 保留2382对根层伪造15像素的修复。真实系统遮挡另行保留，不纳入可调留白。

## 配置兼容和入口

设置标题改为“阅读信息栏底部留白”。沿用旧存储键 `readerFooterHeight`、回调和全局/设备/单漫画继承规则；其运行时含义改为下方留白。旧值超过15时按15生效；不会强制重写为默认4，也不会清除导入数据。默认4仅用于缺失或无效配置。旧安装想体验图中的样式，需要手动将留白设为4。

源码：[底栏](../../lib/features/reader/information_footer.dart)、[正文接入](../../lib/features/reader/scaffold.dart)、[偏好范围](../../lib/foundation/reader_preferences.dart)、[设置页](../../lib/features/settings/reader.dart)。本轮基于 `7d0fbbf`；没有修改其他未提交的墨水屏调研文档。

## 实际组件渲染

预览使用生产ReaderInformationFooter、真实中文字体、3倍PNG输出；不是生成式示意图，也不是Leaf5+实机截图。字体为macOS STHeiti Light，Android字体度量可能略有不同。灰色区域代表漫画，外框仅帮助看清组件边界，不属于产品底栏。

- [横线间隔1/2/3](evidence/2026-10-26-footer-gap.png)：用户选择2。[几何数据](evidence/2026-10-26-footer-gap.json)。
- [下方留白0/4/15](evidence/2026-10-26-footer-bottom.png)：文字区域13、线下间隔2，整体高度分别16/20/31。[几何数据](evidence/2026-10-26-footer-bottom.json)。
- [字号9/11/13](evidence/2026-10-26-footer-font.png)：上间隔始终2，下间隔始终4，仅文字区域11/13/16及总高度18/20/23变化。[几何数据](evidence/2026-10-26-footer-font.json)。

## 验证与交付

74项检查通过：布局20、根层边距5、快照9、偏好存储12、appdata11、设置持久化7、设置效果7，以及3组真实字体渲染。静态分析和架构检查通过。布局矩阵包括留白0/4/15、字号变化、宽窄屏、混合文字、单/双行、隐藏信息保留体积、触摸边界和真实安全区消费；设置回归保留旧值的导入语义并核对归一化值。

```sh
flutter test --no-pub test/features/reader/information_overlay_test.dart test/app_runtime/android_window_insets_test.dart test/foundation/reader_settings_snapshot_test.dart test/foundation/reader_preference_store_test.dart test/foundation/appdata_test.dart test/features/settings/reader_settings_persistence_test.dart test/features/reader/settings_effects_test.dart
flutter analyze --no-pub
```

以上仓库测试合计71项；另3组截图脚本与首次失败日志保存在本机既有任务目录。首次失败包括并行编辑中间态不支持的subtitle参数、旧导入值应保持18而非自动重置4的测试预期，以及截图异步执行环境问题；修正后统一复跑通过。没有通过改变持久化行为来迎合错误测试预期。

固定签名ARM64 Release使用build number239 / versionCode2392，延续相同包名与证书。实际构建、验签及APK身份记录另存任务证据。仍需用户在相同DPI下核验：留白0→15只增加文字下方空间；字号变化不改变两侧间隔；横竖屏、菜单开关和覆盖升级正常。专项通过不代表全套Flutter测试或实机验收通过。
