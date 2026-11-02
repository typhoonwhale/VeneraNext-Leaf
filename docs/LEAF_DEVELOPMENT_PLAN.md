# VeneraNext Leaf：当前状态与开发入口

更新：2026-11-02。当前分支状态见 [LEAF_STATUS.md](LEAF_STATUS.md)。

## 1. 目标与状态

- 设备：文石 BOOX Leaf5+（Android 13，手势导航，无底部虚拟按键栏）。使用第三方 Venera JavaScript 漫画源，主要阅读普通漫画、日漫。
- 目标：阅读信息不遮挡漫画（独立底栏），持续完善墨水屏体验。KOOBONE 接入、Venera 源移植到 Mihon 不在范围内。
- 已发布：Leaf 1.19.1 / versionCode 2522（tag `v1.19.1`，`main@c61937a`），包含空章节错误处理与重试修复；Leaf5+ 已经 USB 覆盖升级。应用内更新自 1.18.4 提供，墨水屏模式自 1.19.0 提供。
- 用户实机确认：同签名 Release 覆盖升级保留数据、从原版导入 `data.venera` 均正常；竖屏日常阅读正常。用户只竖屏使用，横屏不在当前验收范围。
- 验证：正式 1.19.1 的 Linux CI 重跑通过（5543 通过、151 跳过），首次图片时序断言失败记录保留；不能沿用早期 macOS 环境失败把正式主线标为未全绿。当前紧凑信息区有 7 项局部验证和静态分析，尚无该改动的完整 Linux CI 或实机结果。
- 墨水屏模式（黑白 UI、减少动画，路线图阶段 2/3）已在 1.19.0 发布（默认开启，可在“设置 → 外观”关闭）；组件索引与修改指南见 [LEAF_EINK_UI.md](LEAF_EINK_UI.md)，阶段规划见 [LEAF_EINK_ROADMAP.md](LEAF_EINK_ROADMAP.md)，官方 SDK 约束见 [LEAF_EINK_GUIDELINES.md](LEAF_EINK_GUIDELINES.md)。
- 应用内更新已在 1.18.4 发布，设计与验收见 [LEAF_IN_APP_UPDATE_DESIGN.md](LEAF_IN_APP_UPDATE_DESIGN.md)、[LEAF_IN_APP_UPDATE_VALIDATION.md](LEAF_IN_APP_UPDATE_VALIDATION.md)。

## 2. 基线与分支

- 上游：https://github.com/CyrilPeng/Venera-Next ，基线 `v1.18.1` / `087147a7810039398f4eed3bcc794b576f92c46b`。
- 本项目：https://github.com/typhoonwhale/VeneraNext-Leaf （`origin`，fork 自上游，上游为 `upstream`）。
- 暂不跟进上游新版本；需要上游某项修复时再单独评估。
- `main` 为主线，正式版只能从 main 推 `v*` 标签由 CI 发布，构建与发布流程见 [LEAF_BUILD.md](LEAF_BUILD.md)。功能用独立 `feature/...` 分支开发。
- `feature/leaf-reader-footer`（3eac32b）是早期开发分支，已合入 main，不再在其上开发。
- 当前 `feature/leaf-1.19.1-integration` 从正式 1.19.1 建立，收进已读／看过和紧凑信息区，并补齐墨水屏遗漏；验证通过后一次性经 PR 合入 main，当前尚未发布。早期 `feature/leaf-eink-adaptation@274b3db` 保留为历史调研分支，不作后续开发基线。
- “已读／看过”从 `feature/leaf-read-state@98694ef` 整合；D1 续读补偿、D2–D8 均已确认。本分支包含实现，正式 1.19.1 尚不包含；本轮完整验收进行中，后续版本待定。
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

- [x] 正式 1.19.1 的完整 Linux CI 通过；历史 macOS 失败不等同当前主线失败。
- [x] 同签名 Release 覆盖升级保留数据（用户实机确认）。
- [x] 从原版导入 `data.venera`（用户实机确认）。
- [x] Leaf5+ 竖屏日常阅读（用户实机确认）；横屏暂不验收。
- [ ] 已读／看过：已整合正式主线、空章节修复与新信息区；仍需完成 Linux CI、真实续读和手动标记、覆盖升级及 WebDAV 跨设备往返。此前 443 项专项通过、7 项既有 Windows 专属测试跳过，不替代整合验收。
- [x] 墨水屏遗漏实现：图片收藏缩略图黑边直角、对话框无动画、未知总量进度静态显示及动态尺寸布局；完整 CI 与合入状态见当前状态页，详见 [UI 指南第 8 节](LEAF_EINK_UI.md#8-已知遗漏与后续方向)。
- [ ] 墨水屏实机验收：紧凑信息区、禁用控件斜线与文字白边、Hero／多帧图；补实际 DPI／字体缩放。测试和截图统一开启墨水屏模式；离线模拟注明假定配置，不算实机通过。
- [ ] 应用内更新：新版完整下载安装链路、剩余恢复／安装异常组合；30 秒网络超时放宽和镜像为尚未实施的候选。1.19.1 下载有进度但慢，手动取消后通过 USB 安装，没有本次下载报错证据。
- [ ] 瓜子源：若再出现原偶发错误，采集 Network／Reader 日志和源版本；客户端空结果处理已发布，首次网络／解析失败原因仍未知。错误页 1/1 占位显示为独立遗留。
- [ ] 硬件与能耗：SDK 手动全刷最小实验和同条件 60 分钟耗电对照；自动刷新仅在 SDK 实机通过且仍有残影需求时考虑。

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
