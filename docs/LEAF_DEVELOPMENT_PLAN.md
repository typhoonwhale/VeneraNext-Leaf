# VeneraNext Leaf：设计方案、开发清单与交接

更新日期：2026-10-25  
状态：基于 VeneraNext 现有源码二次开发，远端 fork 与设计方案已建立；尚未修改阅读器代码，尚未构建定制 APK。

## 1. 用户目标与已确认情况

- 设备：文石 BOOX Leaf5+，用户表示系统为 Android 13。
- 用户已安装并确认 VeneraNext 可用；当前提供的官方安装包为 v1.18.1 ARM64。
- 用户使用第三方 Venera JavaScript 漫画源，主要阅读普通漫画、日漫。
- 当前问题：页码、时间、电量等信息浮在漫画上，遮挡图片。
- 目标：底部有独立信息区域，漫画在其上方显示，不与信息栏重叠。
- 用户同意以 VeneraNext 为基础进行 fork 二次开发，先保留设计和待开发内容。
- KOOBONE 接入暂不考虑；Venera 源移植到 Mihon 不属于本次开发范围。

## 2. 基线与当前工作状态

### 2.1 开发基线

- 上游：https://github.com/CyrilPeng/Venera-Next
- 基线标签：`v1.18.1`，不直接跟随不断变化的 `main` 开发。
- 基线 commit：`087147a7810039398f4eed3bcc794b576f92c46b`（已解析标签核实）。
- 拟定应用显示名称：`VeneraNext Leaf`。
- 使用新的独立 applicationId 和自有固定签名，允许与官方版并行安装。
- GitHub fork：https://github.com/typhoonwhale/VeneraNext-Leaf ，已通过 API 确认 `fork=true`，parent 为 `CyrilPeng/Venera-Next`。最终 applicationId 在独立包构建前确定。
- 方案路径：`docs/LEAF_DEVELOPMENT_PLAN.md`；跨会话以本仓库最新提交为准。
- 开发分支：`feature/leaf-reader-footer`，源自上述稳定版 commit，包含本方案。
- 官方 applicationId：`com.github.cyrilpeng.veneranext`。

### 2.2 已完成

- [x] 官方 v1.18.1 ARM64 APK 下载及 SHA-256、ZIP 完整性校验。
- [x] 用户实机确认官方版可用。
- [x] 核对源仓库格式、43 个脚本的标识/版本、语法及模拟环境中的基础构造；不代表已逐站验证正文阅读。
- [x] 检索 VeneraNext 的公开 issue、PR、相关评论，并对照 v1.18.1 和当时的 main 阅读器代码。
- [x] 未找到完全实现“底部独立信息栏并缩小漫画视口”的现成 issue/PR。
- [x] 核对官方签名流程和应用数据备份源码。
- [x] 保存本设计与交接文档。
- [x] 用户确认直接 fork 上游现有源码进行二次开发，技术路线见第 4.1 节。
- [x] 下载官方 GitHub CLI `2.103.2` Windows AMD64 便携版，校验官方 SHA-256 并验证命令可运行。
- [x] GitHub CLI 授权成功，确认账号为 `typhoonwhale`，核实远端 fork 地址和上游关系。

### 2.3 尚未完成

- 尚未完成构建环境准备与基线 APK 验证；新会话需克隆本仓库并检查开发分支。
- 没有阅读器代码修改，没有定制签名，没有定制 APK。
- 没有收到或检查用户自己的 `data.venera`，没有进行用户数据迁移。
- Flutter、Dart、JDK、Android SDK/NDK、Rust 和完整构建链仍需在开发环境中核实。
- 历史调研文件不属于可构建工程；开发使用本仓库的完整 checkout。

## 3. 第一版产品设计

### 3.1 布局

采用“上方漫画视口 + 下方信息栏”的真实布局分区。

- 漫画可用高度 = 阅读器可用高度 - 信息栏实际高度 - 需要保留的系统安全区。
- 漫画按上方视口等比适配，不拉伸、不为填满区域而额外裁切。
- 缩放、拖动后的图片仍裁剪在漫画视口内，不能画到信息栏上。
- 信息栏占用空间，不使用覆盖图片的透明层来模拟留白。
- 翻页、时钟刷新、切章时保持栏高稳定；章节长短不能使图片逐页跳动。
- 字号或屏幕方向改变时允许重新计算布局，保留当前源图片与阅读位置。

### 3.2 信息栏外观与内容

- Leaf 的默认浅色外观：白底、黑字、细分隔线；深色主题使用对应的背景和文字颜色。
- 默认显示：左侧当前页/总页数，右侧时间和电量。
- 可选显示章节名；长名称省略，不能挤掉页码。
- 栏高初始设计值为 36 个 Flutter 逻辑像素，可调范围暂定 28–64；字号默认 14，可调范围暂定 12–18。以 Leaf 实机可读性调整。
- 实际高度至少容纳系统文字缩放后的内容及内边距，不通过截断文字强行满足所设高度。
- 状态信息沿用现有时间、电池读取逻辑，避免增加高频轮询和耗电。

### 3.3 设置

新增信息显示方式：`浮层 / 独立底栏 / 隐藏`。

- 定制版在画廊模式默认使用独立底栏；旧备份缺少新增字段时采用这个默认值。
- 原有“显示页码”“显示时间与电量”继续决定具体内容；两项都关闭时不占用空栏。
- 沿用全局、设备、单本漫画设置的继承规则，不另建平行的设置系统。
- 保留浮层选项，便于用户比较或恢复原有阅读方式。
- 配置字段名在实施时确定，需带默认值、类型/范围校验，并能随现有数据导出导入。

### 3.4 模式与交互范围

- 第一版仅改变画廊分页模式，覆盖横竖屏和已有翻页方向。
- 连续滚动、瀑布流第一版维持上游行为，设置界面需说明独立底栏的适用模式。
- 正文触摸、缩放、中央点击呼出菜单、音量键/映射按键翻页保持可用。
- 信息栏区域不触发正文翻页；正文手势坐标按缩小后的视口计算。
- 工具栏展开/收起不改变常驻信息栏尺寸及漫画视口，避免图片跳动；操作工具栏保留现有临时浮层行为。
- 墨水屏刷新需要同时覆盖漫画与信息栏；图片调光与信息栏主题分开处理，保证文字可读。

## 4. 技术实施方向

### 4.1 基于现有源码二次开发（已确认）

本项目直接 fork `CyrilPeng/Venera-Next` 的现有完整源码，在上游 `v1.18.1` 基线上进行增量修改。沿用现有 Flutter/Dart 工程、阅读器、JavaScript 漫画源运行环境、下载与本地漫画库、收藏与历史、设置继承、数据导入导出功能；不新建一套阅读器或漫画源协议。

- 代码托管：用户 GitHub 账号下的 fork 为 `origin`，原项目为 `upstream`，保留上游历史及许可证文件。
- 开发分支：`feature/leaf-reader-footer`，从 `v1.18.1` 对应 commit 创建；将修改限制在独立底栏、相关设置及定制版应用身份/构建配置。
- 兼容策略：复用现有数据格式；新增设置提供缺省值，确保旧 `data.venera` 可进入现有导入流程。实际迁移仍按第 6、7 节验证。
- 后续维护：按需同步上游，再合并并验证本项目修改；不自动追随上游最新代码或直接发布未经验证的构建。
- 工程准备与功能实现分别记录：成功 fork/clone 只表示源码基础就绪，不代表底栏已实现或 APK 已构建。

### 4.2 现有布局与修改入口

当前 `scaffold.dart` 使用 `Stack`，漫画 `Positioned.fill` 占满区域，`_buildInformation()` 再定位到底部，因此信息与图片相叠。

实施方向：在独立底栏模式中为正文建立扣除底栏高度的视口，并复用页码/状态组件。实施时同时核对真实图片布局和手势使用的尺寸，不能只给文字加背景或只改外层 padding。

重点文件，路径相对于本仓库根目录：

| 路径 | 预计用途 |
| --- | --- |
| `lib/features/reader/scaffold.dart` | 正文、信息栏、工具栏和刷新层的组合 |
| `lib/features/reader/shell_data.dart`、`shell_host.dart` | 阅读壳所需配置与状态传递 |
| `lib/features/reader/status_info.dart` | 复用时间、电量展示与生命周期 |
| `lib/features/reader/information_text.dart`、`progress_bar.dart` | 页码与文字显示样式核对 |
| `lib/features/reader/reader_viewport.dart`、`gallery_view.dart` | 适配新视口、缩放与翻页尺寸 |
| `lib/foundation/reader_preferences.dart`、`reader_settings.dart` | 新设置定义、默认值、继承与校验 |
| `lib/features/settings/`、`lib/features/reader/settings_panel.dart` | 设置入口及中英文文案 |
| `test/features/reader/information_overlay_test.dart` 等 | 新增布局与交互回归 |
| `android/app/build.gradle`、Android manifest/入口、发布配置 | 独立应用身份、签名与构建 |

以上为待核对的修改位置，并非要求每个文件都必须改动。

## 5. 安装、签名与后续升级

- 官方 APK 的签名密钥由上游 GitHub Secrets 注入，fork 不会获得该私钥。
- 同包名但不同签名的自编 APK 无法直接更新官方版；正常安装会失败，并不会因此清空官方版数据。
- 本项目使用独立包名，官方版继续保留，定制版初始拥有独立数据区。
- 后续定制版保持 applicationId、签名密钥稳定，并递增 versionCode，支持正常覆盖升级。
- 自有密钥保存在受控位置，并单独备份；不得提交到 Git 仓库，也不能每次构建临时生成新签名。
- 同时核对 FileProvider authority、深链、应用显示名及更新渠道，避免与官方版冲突。
- 自动更新不能继续把官方 APK 当成本定制版的更新；首次可先关闭自动更新，待自有 Release 渠道建立后再接入。
- 修改包名不意味着跨应用数据自动共享，也不会继承原版的文件夹授权。

## 6. data.venera 到底包含什么

已按 v1.18.1 的 `createAppDataSnapshot()` 核实，应用数据归档保存以下内容：

| 归档条目 | 内容 |
| --- | --- |
| `appdata.json` | 设置和搜索历史；源仓库/来源等应用配置随设置保存 |
| `history.db` | 阅读历史和其中记录的进度 |
| `local_favorite.db` | 本地收藏 |
| `cookie.db` | 网站 Cookie |
| `comic_source/` 下的文件 | 漫画源脚本及该目录内的源数据文件 |

归档不包含：

- 已下载或导入漫画的图片、EPUB、CBZ 等实体文件。
- 本地漫画库索引 `local.db`。
- 独立的本地库路径文件 `local_path`。
- 下载队列文件 `downloading_tasks.json` 及未完成下载的数据。

归档本质上是 ZIP。文件名可以叫 `data.venera`，并不是必须使用这个名字；关键是由应用的应用数据导出功能生成、内容完整。

因此：

1. 为开发和验证源配置、收藏、历史的迁移，先导出一个 `data.venera` 作为备份就可以；写代码本身不需要用户私有备份。
2. 如果还要求定制版直接继承现有离线漫画，单有 `data.venera` 不够，还需要单独保留漫画文件，并在新应用中恢复/重新建立本地库。
3. 源登录信息即使已备份，也不能保证迁移后仍然有效，网站可能使 Cookie/Token 过期。
4. 同步及导入存在本机配置保留/字段排除规则；不能声称所有路径、权限和设备专属设置都会不加处理地原样继承。
5. 用户备份可能含登录凭据，不放入 GitHub fork、公开 issue 或构建产物。后续检查时只输出文件清单、数量和结构，不打印 Cookie/Token 内容。

## 7. 用户配合与迁移步骤

### 现在需要做的

- 在原版中手动导出应用数据，保存好 `data.venera`，保留原版应用。
- 开发不以收到此文件为前置条件；先自行保存即可，后续需要实际迁移检查时再在私有工作区处理。
- 若希望保留已有离线漫画：同时保留原版下载目录，后续由原版导出漫画或复制可访问文件；不要将 `data.venera` 当作漫画文件的替代备份。

### 定制版可用后

1. 并行安装定制版，不卸载原版。
2. 导入应用数据，核对源仓库、源设置、收藏及在线漫画的阅读进度。
3. 保持定制版与原版的下载目录独立；迁移测试阶段不让两个应用写同一目录。
4. 先迁移一本漫画：从原版导出 CBZ 再导入，或复制兼容的下载目录后使用“本地 → 导入 → 恢复本地下载”。后者需要先指向正确目录并重新授予访问权限。
5. 核对章节顺序、页数、封面和离线阅读。重新导入为本地漫画可能改变漫画身份，原在线阅读进度未必能自动匹配，应实测，不预先承诺完全关联。
6. 验证通过后再迁移其余漫画。整库迁移之前，原应用和文件副本继续保留。

## 8. 待开发清单

### P0：工程与基线

- [x] 确认 GitHub 账号/仓库归属，核实真正的远端 fork，并记录 URL。
- [ ] 克隆完整工程，阅读仓库内适用的 AGENTS.md/构建说明。
- [x] 从 v1.18.1 基线建立 `feature/leaf-reader-footer` 开发分支，记录基线 commit。
- [ ] 核实 Flutter、Dart、JDK、Android SDK/NDK、Rust 与锁文件要求。
- [ ] 确定独立包名、应用名和固定签名管理方式。
- [ ] 整理应用身份、Provider、更新渠道及 CI 配置。
- [ ] 先构建一个未改阅读布局的独立包，验证可与官方版共存。

### P1：底栏功能

- [ ] 新增设置、默认值、继承规则和中英文文案。
- [ ] 实现独立底栏和缩小后的漫画视口。
- [ ] 实现字号、栏高、可选章节名及主题适配。
- [ ] 修正视口约束、裁剪、缩放和手势边界。
- [ ] 核对工具栏、横竖屏、实体按键和墨水屏刷新。
- [ ] 保留浮层/隐藏模式，连续与瀑布流不受第一版影响。

### P2：验证与交付

- [ ] 布局回归：正文与底栏矩形不相交，放大后也不会绘制越界。
- [ ] 大字号/窄屏/横竖屏：文字不溢出，页码完整，长章节名不会造成逐页高度变化。
- [ ] 交互回归：正文翻页与缩放正常，底栏不误触翻页，开关菜单不使漫画跳动。
- [ ] 设置回归：全局/设备/单本继承与重启持久化、旧备份缺省值符合方案。
- [ ] 数据迁移：先用无私人凭据的样例备份验证，再按需检查用户备份。
- [ ] 验证定制版之间正常覆盖升级可保留设置和本地漫画。
- [ ] 在 Leaf5+ 实机核对残影、文字清晰度、按键与离线阅读，记录未完成项。
- [ ] 交付签名 ARM64 APK、SHA-256、简洁变更说明和安装/回退说明。
- [ ] 更新本文件，将“已实现”“已自动验证”“已实机确认”分别记录。

## 9. 仓库与跨会话入口

- 本项目：https://github.com/typhoonwhale/VeneraNext-Leaf
- 上游：https://github.com/CyrilPeng/Venera-Next
- 方案：`docs/LEAF_DEVELOPMENT_PLAN.md`
- 开发分支：`feature/leaf-reader-footer`
- 稳定版基线：`v1.18.1` / `087147a7810039398f4eed3bcc794b576f92c46b`
- 原版 ARM64 APK SHA-256：`6533b09a84a8a47fce9d8b8539bdee8f2822e650be13f1c80d4f9b7b15c87ff7`

新开发环境的起步命令：

```sh
git clone https://github.com/typhoonwhale/VeneraNext-Leaf.git
cd VeneraNext-Leaf
git remote add upstream https://github.com/CyrilPeng/Venera-Next.git
git switch feature/leaf-reader-footer
```

已有 checkout 时先检查 `git status`、`git remote -v` 和当前分支，不重复 clone 或覆盖本地改动。阅读适用的仓库指引与构建文档，再开始第 8 节任务。每次完成开发后更新本文件的勾选状态、验证结果和待办；功能开发期间优先阅读开发分支中的最新版本。

用户使用的公开第三方源仓库：https://github.com/handahao666-boop/venera_comic_source 。保持现有源扩展接口兼容，本项目不内置该仓库或用户账号信息。

## 10. 证据与参考

- [v1.18.1 发布](https://github.com/CyrilPeng/Venera-Next/releases/tag/v1.18.1)
- [阅读器布局](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/lib/features/reader/scaffold.dart)
- [Android 应用身份及签名配置](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/android/app/build.gradle)
- [CI 签名密钥注入](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/.github/workflows/build.yml)
- [归档实际文件清单](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/lib/features/sync/app_data_snapshot.dart)
- [应用数据导出与导入](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/lib/features/sync/app_data_transfer.dart)
- [数据同步范围说明](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/doc/user/data_sync.zh.md)
- [本地漫画导入与恢复下载](https://github.com/CyrilPeng/Venera-Next/blob/v1.18.1/doc/user/import_comic.zh.md)
- [Android 签名规则](https://developer.android.com/studio/publish/app-signing)
- [Android 应用专属文件与卸载](https://developer.android.com/training/data-storage/app-specific)

## 11. 下一次对话从哪里继续

先读取 `https://github.com/typhoonwhale/VeneraNext-Leaf` 中的 `docs/LEAF_DEVELOPMENT_PLAN.md`，再检查开发分支与最新提交。沿用该 fork 和已核实的 v1.18.1 基线，按 P0 的未完成项建立构建链，再做 P1；不要重新创建阅读器项目，不要把调研目录当作完整工程，也不要把文档提交视为功能或迁移已完成。此前原版停更的讨论已被 VeneraNext 持续维护这一事实更新，不需要重新寻找阅读器或重新研究 KOOBONE。
