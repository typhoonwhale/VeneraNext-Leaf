# VeneraNext Leaf：当前状态与开发入口

更新核对：2026-10-30。当前正式版为 **1.19.0 / 2502**；本分支为 `feature/leaf-read-state`（基线 `b416a69`）。本分支以 1.19.0 为基线，已实现 1.19.1 章节已读/看过规则并通过本地专项验证；当前改动尚未发布。发布、验证与待办统一见[当前状态](LEAF_STATUS.md)。

更新：2026-10-30。

## 1. 目标与状态

- 设备：文石 BOOX Leaf5+（Android 13，手势导航，无底部虚拟按键栏），主要竖屏阅读普通漫画和日漫；KOOBONE 接入与向 Mihon 移植源不在范围内。
- 当前正式版为 **1.19.0 / 2502**，由 CI 发布，含独立底栏、应用内更新、默认开启的黑白墨水屏模式和减少动画。
- 历史实机记录：同签名覆盖升级、原版数据导入和竖屏日常阅读正常；1.18.4 → 1.19.0 应用内升级已通过，数据保留。当前设备状态未重新核验，横屏和耗电仍不作已验收结论。
- PR #3 的 Linux CI 全量 Flutter 测试及其他检查通过；macOS 的原生依赖限制仍在，不能称本机全量通过。
- 本 checkout：`feature/leaf-read-state`（基线 `b416a69`），版本 `1.19.1+251`。本分支以 1.19.0 为基线，已实现 1.19.1 章节已读/看过规则并通过本地专项验证；当前改动尚未发布。
- 后续优先级：1.19.1 完整 CI 与实机验收（已在本地 feature/leaf-read-state 实现并通过专项）→ 更新下载超时/镜像候选 → 墨水屏遗漏及硬件/耗电实验。证据与边界见[当前状态](LEAF_STATUS.md)。

## 2. 基线与分支

- 上游来源：[VeneraNext](https://github.com/CyrilPeng/Venera-Next)，采用基线 `v1.18.1 / 087147a`；暂不自动跟进上游。当前本机仅配置 `origin`，其他 checkout 的 remote 需实查。
- 主线与 `v1.19.0`：`b416a697079764b046caf0015ca6c200ba7c11d6`。新功能基于当次核实的 `origin/main`；正式流程为功能分支 → PR → CI → 合入 main → 附注标签 → CI 发布。
- `feature/leaf-reader-footer`、`feature/leaf-release-ci`、`feature/leaf-eink-adaptation` 都是早期基线；其中后者仍保留在远端。分支用途、精确 SHA 和清理边界见[分支说明](LEAF_STATUS.md)。
- 沿用 Flutter/Dart 工程、阅读器、源扩展、设置继承及导入导出；新设置必须带默认值，保留旧数据兼容。

## 3. 底栏设计（当前）

阅读器画廊模式把正文与信息栏分成真实布局分区，正文裁剪在上方视口内，缩放拖动不画到底栏上；底栏不触发翻页，工具栏开关不改变正文视口。从上到下：

1. 1 逻辑像素高对比横线（明暗主题均可见）。
2. 固定间隔 2（`dividerGap`，不对用户开放）。
3. 文字区：字号 9–13，默认 11；行高取字体自然高度。窄屏时信息分成两行，行间隔 4；长标题单行省略，页码不裁切。
4. 可调底部留白 0–15，默认 4（存储键沿用 `readerFooterHeight`，旧值超过 15 按 15 生效）。
5. 系统真实 bottom padding（不人为预留手势区）。

相关设置（均复用全局/设备/单漫画继承，随数据导出导入）：

- `readerInformationMode`：`footer`（默认）/ `overlay` / `hidden`，仅作用于画廊模式；连续滚动与瀑布流维持上游行为。全新安装缺字段时用默认值，已有安装导入旧备份时缺失字段保留本机值。
- `readerFooterShowChapter`：是否显示「书名｜章节名」；无章节仅显示书名。
- `readerFooterFontSize`：字号 9–13。
- 页码、时间电量、标题三项都关闭时不占用底栏；时间电量沿用现有读取逻辑，不增加轮询。

源码：`lib/features/reader/information_footer.dart`、`scaffold.dart`、`reader_viewport.dart`、`gallery_view.dart`，设置在 `lib/foundation/reader_preferences.dart` 与 `lib/features/settings/reader.dart`。设计依据与渲染见[底栏分段布局](research/2026-10-26-footer-spacing.md)，早期过程见[开发日志](research/2026-10-25-footer-dev-log.md)。

## 4. Android 身份、签名与升级

- Release 包名 `com.github.typhoonwhale.veneranext.leaf`，Debug 加 `.debug`；官方版包名 `com.github.cyrilpeng.veneranext`，可并行安装，数据区独立。
- 固定签名证书 SHA-256：`ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909`，必须复用；keystore 不入库，需单独备份，不得临时生成新签名。每次发布递增 versionCode，同包名同签名覆盖升级。
- 官方 APK 的签名私钥在上游 Secrets 中，同包名异签名无法覆盖官方版。
- FileProvider authority、深链、显示名随 applicationId 隔离；更新渠道默认指向本仓库 Releases。
- 构建、签名、发布流程见 [LEAF_BUILD.md](LEAF_BUILD.md)。

## 5. data.venera 内容

归档为 ZIP，由应用数据导出生成。

| 包含 | 不包含 |
| --- | --- |
| `appdata.json`（设置、搜索历史、源仓库配置） | 已下载/导入漫画的图片、EPUB、CBZ 等实体文件 |
| `history.db`（阅读历史与进度） | 本地库索引 `local.db`、路径文件 `local_path` |
| `local_favorite.db`（本地收藏） | 下载队列 `downloading_tasks.json` |
| `cookie.db`（Cookie，迁移后可能过期） | |
| `comic_source/`（漫画源脚本及数据） | |

备份可能含登录凭据，不放入仓库、issue 或构建产物；检查时只输出清单、数量和结构。继承离线漫画需另外保留漫画文件。

## 6. 迁移步骤

1. 在原版导出 `data.venera` 并保留原版；开发不依赖用户提供此文件。
2. 并行安装 Leaf，导入应用数据，核对源仓库、源设置、收藏和在线阅读进度。
3. 两个应用的下载目录保持独立，迁移测试期不写同一目录。
4. 先迁一本漫画：从原版导出 CBZ 再导入，或复制兼容的下载目录后用「本地 → 导入 → 恢复本地下载」（需重新授权目录）。核对章节顺序、页数、封面；重导入可能改变漫画身份，在线进度需实测。
5. 通过后再迁其余漫画，期间保留原应用和文件副本。

章节状态的已确认行为与代码入口见[1.19.1 章节状态说明](LEAF_READ_STATE.md)。

## 7. 待办与验证

以下是当前主线状态，旧 checkout 的代码能力另见第 1 节。

- [x] 1.19.0 已通过 PR 的 Linux CI 并正式发布；Leaf5+ 从 1.18.4 应用内升级、数据保留有实机记录。
- [x] 黑白界面与减少动画随墨水屏模式发布；底栏、源接口、固定签名保持既有边界。
- [x] 1.19.1 已读/看过规则本地实现：D1–D8 已按确认语义落地，443 项专项通过，7 项 Windows 专属既有测试跳过；静态分析、架构和格式检查通过。
- [ ] 1.19.1 完整 Linux CI、Leaf5+ 与普通手机实机、覆盖升级和跨设备同步；未发布。
- [ ] 更新下载超时/镜像候选；图片收藏、对话框转场和线性进度动画遗漏。
- [ ] SDK 硬件全刷实验、同条件 60 分钟耗电对照；本机 Linux CI 复现为可选项。

## 8. 继续开发

main 为主线，墨水屏进度看 [LEAF_EINK_ROADMAP.md](LEAF_EINK_ROADMAP.md)，机型依据与调研入口见[调研目录](research/README.md)。不重新创建阅读器项目，调研目录不是可构建工程。

```sh
git clone https://github.com/typhoonwhale/VeneraNext-Leaf.git
cd VeneraNext-Leaf
git remote add upstream https://github.com/CyrilPeng/Venera-Next.git
git switch main
git switch -c feature/<主题>
```

已有 checkout 时先看 `git status`、`git remote -v` 和当前分支，不重复 clone 或覆盖本地改动。每次开发后更新本文件的状态和待办。

用户使用的公开第三方源仓库：https://github.com/handahao666-boop/venera_comic_source ，保持源扩展接口兼容，本项目不内置该仓库。

## 9. 参考

- [v1.18.1 发布](https://github.com/CyrilPeng/Venera-Next/releases/tag/v1.18.1)
- [阅读器布局 scaffold.dart](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/lib/features/reader/scaffold.dart)
- [Android 应用身份及签名配置](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/android/app/build.gradle)
- [归档文件清单 app_data_snapshot.dart](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/lib/features/sync/app_data_snapshot.dart)
- [数据同步范围说明](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/doc/user/data_sync.zh.md)
- [本地漫画导入与恢复下载](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/doc/user/import_comic.zh.md)
- [Android 签名规则](https://developer.android.com/studio/publish/app-signing)
