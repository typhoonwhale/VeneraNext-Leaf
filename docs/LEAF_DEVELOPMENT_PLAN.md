# VeneraNext Leaf：当前状态与开发入口

更新：2026-11-03。`main` 是长期权威主线；正式版与 Leaf5+ 设备当前版本均为 1.19.2+253 / ARM64 versionCode 2532。当前状态见 [LEAF_STATUS.md](LEAF_STATUS.md)，准备分支与主线门禁见 [LEAF_1_19_3_PREPARATION.md](LEAF_1_19_3_PREPARATION.md)。

## 1. 目标与状态

- 设备：文石 BOOX Leaf5+（Android 13，手势导航，无底部虚拟按键栏）。使用第三方 Venera JavaScript 漫画源，主要阅读普通漫画、日漫。
- 目标：阅读信息不遮挡漫画，持续完善墨水屏体验，同时保留漫画原图。KOOBONE 接入、Venera 源移植到 Mihon 和漫画灰度转换均不在范围内。
- 正式版：Leaf 1.19.2+253 / ARM64 versionCode 2532，包含章节已读／看过、紧凑信息区和墨水屏 UI／动画补齐；发布资产以 [GitHub Releases](https://github.com/typhoonwhale/VeneraNext-Leaf/releases) 为准。上一正式版 Leaf 1.19.1+252 / versionCode 2522（`v1.19.1`，基线 `c61937a`）包含空章节错误处理与重试修复。
- 应用内更新自 1.18.4 提供；墨水屏模式自 1.19.0 提供。底栏和实现细节见第 3 节。
- 墨水屏组件索引与修改指南见 [LEAF_EINK_UI.md](LEAF_EINK_UI.md)，阶段规划见 [LEAF_EINK_ROADMAP.md](LEAF_EINK_ROADMAP.md)，SDK 约束见 [LEAF_EINK_GUIDELINES.md](LEAF_EINK_GUIDELINES.md)。
- 应用内更新设计与已有覆盖记录见 [LEAF_IN_APP_UPDATE_DESIGN.md](LEAF_IN_APP_UPDATE_DESIGN.md) 和 [LEAF_IN_APP_UPDATE_VALIDATION.md](LEAF_IN_APP_UPDATE_VALIDATION.md)。

## 2. 基线与分支

- 上游：https://github.com/CyrilPeng/Venera-Next ，基线 `v1.18.1` / `087147a7810039398f4eed3bcc794b576f92c46b`。
- 本项目：https://github.com/typhoonwhale/VeneraNext-Leaf（`origin`，fork 自上游；上游远端为 `upstream`）。
- 暂不跟进上游新版本；需要某项修复时再单独评估。
- `main` 是长期主线，正式发布从 main 上的提交打 `v*` 标签；新增功能及功能修复必须先从当前分支新建独立分支，合入下一小版本预备分支后，再由预备分支通过 PR 合入 main；创建分支与整合时的功能／待办要求见[分支规范](LEAF_BRANCH_WORKFLOW.md)。
- `release/leaf-1.19.3` 从 `main@09b0bd5` 建立，已整合看过圆圈修复和缓存 HEAD 修复，版本元数据仍为 1.19.2+253；尚未合入 main 或发布。详情见[准备记录](LEAF_1_19_3_PREPARATION.md)。
- 早期 `feature/leaf-reader-footer` 已合入 main；`feature/leaf-1.19.1-integration` 的整合通过 [PR #6](https://github.com/typhoonwhale/VeneraNext-Leaf/pull/6) 合入 main（`2008382`）。新功能从当前分支已核实的 HEAD 新建分支；缺少下一小版本预备分支时，另从最新 main 建立预备分支。
- 沿用现有 Flutter/Dart 工程、阅读器、JS 漫画源运行环境、设置继承与数据导入导出；新增设置应有明确默认值，旧 `data.venera` 可进入现有导入流程。

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

### 已发布

- Leaf 1.19.2+253 / ARM64 versionCode 2532 已发布；包含已读／看过、紧凑信息区及墨水屏 UI／动画遗漏补齐。
- PR #6 的历史验证、布局模拟和定向截图见[整合验收记录](research/2026-11-02-integration-validation.md)。

### 已整合到预备分支，待合入 main

- 看过状态圆圈修复（`fix/leaf-viewed-marker@2fb53b4`）与瓜子章节往前翻回后显示空章节的缓存修复（`fix/leaf-chapter-cache-head@e662b3f`，[功能文档](features/leaf-chapter-cache-head.md)）已整合进 `release/leaf-1.19.3`。功能分支与整合后的验证、剩余待办见[准备记录](LEAF_1_19_3_PREPARATION.md)。

### 后续候选

以下为低优先级候选，不作为当前发布门槛：

- 瓜子服务器缓存若被其他客户端写成空正文，仍可能短时返回空章节，需源脚本带随机参数重试；错误页 1/1 占位显示可后续处理。
- 应用内更新剩余异常组合保留为按需候选，已有覆盖见[更新验收记录](LEAF_IN_APP_UPDATE_VALIDATION.md#历史发布与实机覆盖截至-2026-10-30)，不另设当前专项验收。
- 下载慢的原因尚未确认；放宽超时或增加下载镜像尚未实施。
- 墨水屏 SDK 手动刷新和同条件耗电对照可按后续需求评估；自动刷新须先通过手动刷新实机验证。
- 日期字形对齐暂缓，先核对 Leaf5+ 字体，不加入固定偏移。

### 用户取消的专项验收

已读／看过专项实机、其他墨水屏专项、升级数据保留、应用内完整升级及 WebDAV 往返专项已取消。日常使用暂未发现问题；这不表示专项测试通过，也不作为待办或发布门槛。

## 8. 继续开发

`main` 是长期权威主线。开始开发前必须阅读[分支与功能文档规范](LEAF_BRANCH_WORKFLOW.md)：从当前分支新建功能分支，确认下一小版本预备分支存在，并立即编写功能范围与待办。功能合入预备分支时同步汇总已实现内容与剩余待办，再由预备分支通过 PR 合入 main。纯文档改动使用轻量文档门禁，代码或 CI 改动执行完整核心 CI；门禁范围见[准备记录](LEAF_1_19_3_PREPARATION.md)。墨水屏候选见 [LEAF_EINK_ROADMAP.md](LEAF_EINK_ROADMAP.md)，机型依据与调研入口见[调研目录](research/README.md)。调研目录不是可构建工程。

```sh
git clone https://github.com/typhoonwhale/VeneraNext-Leaf.git
cd VeneraNext-Leaf
git remote add upstream https://github.com/CyrilPeng/Venera-Next.git
git status
git branch --show-current
git rev-parse HEAD
git switch -c feature/<主题>
# 随即检查或建立下一小版本预备分支，并初始化功能文档；详见分支规范。
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
