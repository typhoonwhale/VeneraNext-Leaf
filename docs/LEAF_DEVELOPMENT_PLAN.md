# VeneraNext Leaf：当前状态与开发入口

更新：2026-11-02。当前分支状态见 [LEAF_STATUS.md](LEAF_STATUS.md)。

## 1. 目标与状态

- 设备：文石 BOOX Leaf5+（Android 13，手势导航，无底部虚拟按键栏）。使用第三方 Venera JavaScript 漫画源，主要阅读普通漫画、日漫。
- 目标：阅读信息不遮挡漫画（独立底栏），持续完善墨水屏体验。KOOBONE 接入、Venera 源移植到 Mihon 不在范围内。
- 已发布：Leaf 1.19.1 / versionCode 2522（tag `v1.19.1` 指向 `c61937a`），包含空章节错误处理与重试修复；Leaf5+ 已经 USB 覆盖升级。应用内更新自 1.18.4 提供，墨水屏模式自 1.19.0 提供。后续三项功能已通过 PR #6 合入 main（`2008382`），尚未发布。
- 用户实机确认：同签名 Release 覆盖升级保留数据、从原版导入 `data.venera` 均正常；竖屏日常阅读正常。用户只竖屏使用，横屏不在当前验收范围。
- 验证：PR #6 的 8 项检查全部成功，完整 Linux Flutter 为 5627 通过、151 跳过，Android ARM64 冒烟构建通过；合入 tree 与被测提交一致。信息区 7 项布局验证和合入后的 3 项截图验证通过，真实设备验收待补。[结果与截图](research/2026-11-02-integration-validation.md)。正式 1.19.1 的历史 CI 为 5543 通过、151 跳过，首次失败记录保留。
- 墨水屏模式（黑白 UI、减少动画，路线图阶段 2/3）已在 1.19.0 发布（默认开启，可在“设置 → 外观”关闭）；组件索引与修改指南见 [LEAF_EINK_UI.md](LEAF_EINK_UI.md)，阶段规划见 [LEAF_EINK_ROADMAP.md](LEAF_EINK_ROADMAP.md)，官方 SDK 约束见 [LEAF_EINK_GUIDELINES.md](LEAF_EINK_GUIDELINES.md)。
- 应用内更新已在 1.18.4 发布，设计与验收见 [LEAF_IN_APP_UPDATE_DESIGN.md](LEAF_IN_APP_UPDATE_DESIGN.md)、[LEAF_IN_APP_UPDATE_VALIDATION.md](LEAF_IN_APP_UPDATE_VALIDATION.md)。

## 2. 基线与分支

- 上游：https://github.com/CyrilPeng/Venera-Next ，基线 `v1.18.1` / `087147a7810039398f4eed3bcc794b576f92c46b`。
- 本项目：https://github.com/typhoonwhale/VeneraNext-Leaf （`origin`，fork 自上游，上游为 `upstream`）。
- 暂不跟进上游新版本；需要上游某项修复时再单独评估。
- `main` 为主线，正式版只能从 main 推 `v*` 标签由 CI 发布，构建与发布流程见 [LEAF_BUILD.md](LEAF_BUILD.md)。功能用独立 `feature/...` 分支开发。
- `feature/leaf-reader-footer`（3eac32b）是早期开发分支，已合入 main，不再在其上开发。
- `feature/leaf-1.19.1-integration` 从正式 1.19.1 建立，收进已读／看过、紧凑信息区和墨水屏补齐；已通过 [PR #6](https://github.com/typhoonwhale/VeneraNext-Leaf/pull/6) 合入 main（`2008382`）。新开发从核实过的最新 main 开始；早期 `feature/leaf-eink-adaptation@274b3db` 保留为历史调研分支。
- “已读／看过”从 `feature/leaf-read-state@98694ef` 整合；D1 续读补偿、D2–D8 均已确认。主线包含实现并通过完整自动验证，正式 1.19.1 尚不包含；新功能的实机、升级和跨设备同步验收待补，后续版本待定。
- 沿用现有 Flutter/Dart 工程、阅读器、JS 漫画源运行环境、设置继承与数据导入导出；新增设置带默认值，旧 `data.venera` 可进入现有导入流程。

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

## 7. 待办与验证

### 已完成

- [x] 正式 1.19.1 空章节修复已发布；Leaf5+ 同签名 USB 覆盖升级、数据保留和阅读冒烟通过。此前原版 `data.venera` 导入与竖屏日常阅读已有实机确认；这些历史结果不替代新功能验收。
- [x] 已读／看过、紧凑信息区、墨水屏遗漏补齐统一整合，并通过 PR #6 一次性合 main。
- [x] 最终整合内容的 8 项 PR CI 成功，Flutter 5627 通过、151 跳过，Android ARM64 冒烟通过；独立评审及相关本地验证通过。
- [x] 7 种信息区布局模拟和 3 项章节／收藏／加载框定向验证通过，16 张模拟图已归档；截图均使用墨水屏模式，参数和替代字体明确标注。

### 近期验收与交付

- [ ] Leaf5+ 真实续读和自动／手动标记：正常翻页、跳页、短章越尾、退出重进、同组之前标记与无历史手标；D1–D8 保持已确认规则。
- [ ] 新功能覆盖升级后的历史、收藏、源与设置保留；新旧数据库迁移已有自动验证，实机升级仍待补。
- [ ] WebDAV 跨设备往返：已读／看过及续读位置的真实同步；旧 Venera 重写行可能丢失看过记录的兼容边界保持。
- [ ] 墨水屏实机观感：紧凑信息区、收藏边框、对话框、禁用控件斜线与文字白边，以及 Hero／多帧图；补实际 DPI、字体缩放和应用显示配置。横屏不在当前验收范围。
- [ ] 为包含新功能的后续版本确定版本号、递增构建号，完成固定签名打包验包与发布；正式 `v1.19.1` 标签及资产保持，不用旧 `2512` 测试包升级。
- [ ] 新版应用内完整下载安装；1.19.1 下载有进度但慢、手动取消后改用 USB，未覆盖该次完整应用内链路。

### 后续问题、候选与暂缓项

- [ ] 应用内更新剩余异常组合：旧快照、恢复中异常退出、压缩包不同状态跨升级、分段损坏／缓存回收／清理失败、安装失败及后台／迟到回调，具体已有覆盖见[验收表](LEAF_IN_APP_UPDATE_VALIDATION.md#历史发布与实机覆盖截至-2026-10-30)。不把已完成的更新功能整体列为未做。
- [ ] 下载慢的改进候选：现有 30 秒网络超时放宽、下载镜像均未实施；本次慢下载没有超时报错证据，原因尚未确认。
- [ ] 瓜子源：再次出现原偶发错误时采集 Network／Reader 日志、章节和源版本；首次网络／解析失败原因未知，客户端空结果处理已发布。错误页 1/1 占位显示另待处理。
- [ ] 字形视觉对齐暂缓：模拟图日期数字看起来略高；中文和日期位于同一个 Text，共用基线。先核对 Leaf5+ 实际字体，再决定是否需要调整；当前不加固定偏移。
- [ ] 硬件与能耗：SDK 手动全刷最小实验、同条件 60 分钟耗电对照；自动刷新仅在 SDK 实机通过且仍有残影需求时考虑。

这些后续候选按实际需求安排，不把所有历史异常组合、硬件实验和耗电研究自动扩大为本轮整合的发布门槛。旧分支是否清理另行决定，不自动删除。

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
