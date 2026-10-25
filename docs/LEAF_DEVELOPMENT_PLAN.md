# VeneraNext Leaf：设计方案、开发清单与交接

更新日期：2026-10-25  
状态：独立底栏、设置继承和 Android 独立身份已实现；固定签名 ARM64 Release 已交付，用户确认功能正常。本轮按设备反馈缩小底栏；全套回归未全绿，完整硬件验收仍待完成。

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
- 应用显示名称：`Leaf`。
- 使用新的独立 applicationId 和自有固定签名，允许与官方版并行安装。
- GitHub fork：https://github.com/typhoonwhale/VeneraNext-Leaf ，已通过 API 确认 `fork=true`，parent 为 `CyrilPeng/Venera-Next`。applicationId：`com.github.typhoonwhale.veneranext.leaf`，Debug 另加 `.debug` 后缀。
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

### 2.3 当前实现与待验收项

- 工程已克隆，Flutter 3.41.4 / Dart 3.11.1、JDK 17、Android SDK 36 / NDK 28.0.13004108、Rust 1.92.0 已准备；未完成未改布局的基线 APK 共存验证。
- 独立底栏与视口裁剪已实现，新增设置可继承、持久化；Android 应用身份、Provider、深链、更新隔离及签名缺失失败逻辑已实现。已生成并静态验证 ARM64 Debug 与固定签名 Release APK；用户已确认 Release 版本功能正常。
- 没有收到或检查用户自己的 `data.venera`，没有进行用户数据迁移。
- Debug 与 Release 构建链已通过；Release 覆盖升级保留数据和完整硬件表现仍需验证。构建入口与签名管理见 [LEAF_BUILD.md](LEAF_BUILD.md)。
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
- 底栏按当前页与总页各 5 位数字预留容量，保证总页数不超过 99999 的章节之间栏高稳定；超过此容量时允许扩容，优先完整显示页码。窄屏和系统大字下会预留更多高度，不缩小字号或截断页码。

### 3.2 信息栏外观与内容

- Leaf 的默认浅色外观：白底、黑字、贯穿底栏的 1 逻辑像素高对比分隔线；深色主题使用对应的背景和文字颜色。
- 默认显示：左侧当前页/总页数，右侧时间和电量。
- 可选显示「书名｜章节名」，书名复用原版顶部工具栏的数据；没有章节时仅显示书名，长名称省略，不能挤掉页码或时间电量。
- 按用户实机反馈收窄：栏高默认 18 个 Flutter 逻辑像素，可调范围 15–25；字号默认 11，可调范围 9–13。取消固定上下各 6 的留白，内容底对齐。
- 实际高度至少容纳系统文字缩放后的内容及 1 像素顶部分隔线；大字或窄屏换行时允许超过设置值，系统底部安全区另计，不通过裁切文字强行满足所设高度。
- 状态信息沿用现有时间、电池读取逻辑，避免增加高频轮询和耗电。

### 3.3 设置

新增信息显示方式：`浮层 / 独立底栏 / 隐藏`。

- 定制版在画廊模式默认使用独立底栏；旧备份缺少新增字段时采用这个默认值。
- 数据导入沿用现有合并语义：全新安装加载缺少新字段的旧备份时使用 `footer` 默认值；已有安装导入旧备份时，缺失字段保留本机当前值，不强制重置为默认值。
- 原有“显示页码”“显示时间与电量”继续决定具体内容；标题沿用原章节名开关，三项都关闭时不占用空栏。
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
- [x] 克隆完整工程，阅读仓库内适用的 AGENTS.md/构建说明。
- [x] 从 v1.18.1 基线建立 `feature/leaf-reader-footer` 开发分支，记录基线 commit。
- [x] 核实 Flutter、Dart、JDK、Android SDK/NDK、Rust 与锁文件要求。
- [ ] 确定独立包名、应用名和固定签名管理方式。
- [x] 整理应用身份、Provider、更新渠道及 CI 配置。
- [ ] 先构建一个未改阅读布局的独立包，验证可与官方版共存。

### P1：底栏功能

- [x] 新增设置、默认值、继承规则和中英文文案。
- [x] 实现独立底栏和缩小后的漫画视口。
- [x] 实现字号、栏高、可选章节名及主题适配。
- [x] 修正视口约束、裁剪、缩放和手势边界。
- [ ] 核对工具栏、横竖屏、实体按键和墨水屏刷新。
- [x] 保留浮层/隐藏模式，连续与瀑布流不受第一版影响。

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

Leaf5+机型依据和后续调查统一维护在[调研记录及agent接手入口](research/README.md)。开始布局或升级改动前先核对相关记录，新增调查继续追加到该目录。

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

先读取 `https://github.com/typhoonwhale/VeneraNext-Leaf` 中的 `docs/LEAF_DEVELOPMENT_PLAN.md`，再检查开发分支与最新提交。沿用该 fork 和已核实的 v1.18.1 基线，先读本文件最新验证记录，继续 P0/P2 未完成的构建与实机验证；不要重新创建阅读器项目，不要把调研目录当作完整工程，也不要把文档提交视为功能或迁移已完成。此前原版停更的讨论已被 VeneraNext 持续维护这一事实更新，不需要重新寻找阅读器或重新研究 KOOBONE。


## 12. 2026-10-25 开发与验证记录

本轮在 `feature/leaf-reader-footer` / `77e12cf` 上继续增量实现，没有变更 tracking upstream，没有推送。源码和结果保存在本机任务工作区；远端方案与本地未提交实现应区分。

### 已实现

- 画廊使用固定组件结构的正文区与底栏，正文 `ClipRect`、尺寸约束、`MediaQuery` 和长按坐标同时适配；切换模式不重挂正文组件。
- `readerInformationMode` 默认为 `footer`，可选 `overlay` / `hidden`；`readerFooterHeight` 默认 36、范围 28–64；`readerFooterFontSize` 默认 14、范围 12–18；`readerFooterShowChapter` 默认 false。均复用已有偏好和校验，不新增独立存储系统。
- 页码、状态与标题开关都关闭时无底栏；评论页保留底栏空间并隐藏信息。正文亮度独立，墨水屏刷新覆盖全阅读区。浅色白底黑字，深色沿用主题。
- Android Release 包名 `com.github.typhoonwhale.veneranext.leaf`，Debug 加 `.debug`。Launcher 显示 `Leaf`，移除网页深链竞争，保留文本分享，Provider 随 applicationId 隔离。
- Android 应用更新默认连接 `typhoonwhale/VeneraNext-Leaf`；启动检查沿用原有开关（默认关闭），手动检查可用，旧备份不能改回上游来源。构建时可覆盖仓库或显式传空值关闭，禁止上游仓库（大小写不敏感）。桌面端更新行为保留。
- Release 缺少固定签名时明确失败；Debug 使用 Android 自动生成的测试签名；本轮没有创建正式 Release 密钥或配置 GitHub Secrets。

### 自动验证与限制

- 最终底栏专项 14 项通过；更新服务、更新渠道及 About 设置 23 项通过。
- 阅读器与偏好/持久化套件：924 项通过、30 项跳过、1 项图片解码时序失败。该失败在当前代码和原始提交分别独立复跑均通过，没有修改断言或无关图片实现。
- Flutter analyze 无问题；Python 构建脚本 143 项中 133 通过、10 跳过；结构、架构、版本一致性、Git 依赖和 AST 自检通过。
- 完整 Flutter 测试未通过。macOS 缺失 QuickJS 原生框架、网络 FRB 初始化和文件选择插件分别有原始提交复现证据；部分子进程测试挂起后停止，日志中中断产生的加载错误不算新代码缺陷。不能将这些说明等同于全套通过。
- ARM64 Debug APK 已构建：1.18.1 / 2364，包名 `com.github.typhoonwhale.veneranext.leaf.debug`。ZIP、包身份、ARM64 原生库及 APK v2 Debug 签名检查通过。SHA-256：`64958477545396bddeaf19c87955b55b3ebc5f8829b8643d4c5bc31c03676a61`。
- 真实 Roboto 字体横竖屏及大字 4 项测试通过；截图为模拟正文，不是设备验收。
- 未完成正式签名 Release、官方版实机共存、定制版覆盖升级、真实备份迁移或 Leaf5+ 硬件验收。

后续优先补齐固定 Release 签名保管、Release 构建与设备验证；不重复实现已完成的底栏和设置，不为本轮功能顺手修改上游网络/原生测试框架。

### 同日后续：Leaf 名称、图标与自有更新渠道

- 按用户要求，Android 显示名和应用内标题改为 `Leaf`，原 SVG 主体右下加入 Leaf 标记；普通、自适应和单色主题图标同步，桌面平台保持原资源。
- Android 默认更新仓库为 `typhoonwhale/VeneraNext-Leaf`，About 仓库链接同步；启动检查仍遵循原有开关，默认关闭。稳定版优先查询 latest，Leaf 仓库未发布时的 404 再核对 Releases 列表；空列表为无更新，权限和网络错误保留。
- 更新与设置 30 项回归通过，Android 身份 4 项通过，最终 analyze 无问题。新版 ARM64 Debug APK 构建、签名、身份与图标验包通过；APK 和 SHA-256 见本机任务交付记录，旧包仍保留。
- 本轮没有发布 Release、配置签名 Secrets 或推送代码；同包名同 Debug 证书不代替实机覆盖安装和正式签名升级验收。


### 同日后续：分隔线与书名

- 独立底栏顶部加入全宽 1 逻辑像素高对比横线，明暗主题均可见。
- 复用原版 ReaderShellData.title 与 chapterTitle，按「书名｜章节名」展示；沿用 readerFooterShowChapter 的键、默认值及继承关系，仅调整设置文案。无章节仅显示书名，章节标题缺失沿用 E{chapter}。
- 标题独立开启也可显示；长标题单行省略，窄屏大字允许信息行与状态行分开，按实际行高扩展底栏。高度设置仍为 28–64 逻辑像素。
- 底栏专项 17/17、真实 CJK 字体视觉场景 8/8 通过。具体日志与新版测试包在本机任务目录记录；全套回归和正式 Release 的既有限制仍保留。


### 同日后续：首个固定签名 Release 测试包

- 按用户确认，后续设备试用改用固定签名 Release 迭代。本机首次生成并保存 Leaf 自有签名，Git 忽略且权限受限，另保留本机副本；尚待用户离线备份，未上传 GitHub Secrets。
- ARM64 Release 构建与静态验包通过：1.18.1 / 2362，23.37 MB（22.3 MiB）；包名 `com.github.typhoonwhale.veneranext.leaf`，非 debuggable，AOT 与必需原生库齐全。
- APK SHA-256：`0428c46a2929c701168f52a6da4e404bd9d522b5fe86c91108882b462988d180`；签名证书 SHA-256：`ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909`。后续必须复用此签名。
- Android 身份测试 4 项通过；本轮无产品代码更改，复用此前底栏与分析结果。全套回归未全绿、实机迁移和覆盖升级未验收，不把静态验包等同于运行验收。
- Debug 与 Release 独立数据区，首次需导出/导入；应用数据不含漫画图片，图片另行迁移。之后同包名同签名 Release 直接覆盖，发布新版本递增版本号。源码未提交、未推送，未创建公开 Release。


### 同日后续：Leaf5+ 紧凑底栏与底对齐

- 用户确认前一版Release功能正常，并要求高度15–25、字号更小、文字贴底。新默认高度18、字号11（范围9–13），取消上下各6的固定留白，底对齐；保留顶线、标题及窄屏大字自动增高。
- 用户确认目标Leaf5+使用手势导航、底部无虚拟按键栏。官方导航文档区分手势与虚拟按键，未规定固定底部8像素区域；此前8像素是测试模拟，不能当作机型实测值。代码默认请求immersive，只响应系统实际padding，不凭手势范围人为留白。本机任务 docs/leaf5plus-device.md记录来源和未实测边界。
- 50项配置/持久化/布局回归、11组真实CJK视觉场景及最终analyze通过。固定签名ARM64 Release已构建验包，versionCode从2362增至2372，23.37 MB。SHA-256：f3282e1dfe6ac9a7b4f5d61ac9335cf80d32442657ad83482a4d77dd74caedb0。
- 已存超范围旧值按新边界生效，已有安装可手动选18/11；同签名Release直接覆盖，无需重新导入。紧凑版尚待实机验收，源码未提交/推送。

## 应用内更新方案（2026-10-26）

已确认在独立分支 `feature/leaf-in-app-update` 开发，需求与设计见 [Leaf应用内更新方案](LEAF_IN_APP_UPDATE_DESIGN.md)。计划提供应用内下载、两阶段校验、系统安装确认和专用更新目录清理；不做断点续传。当前仅形成方案，尚未实现或验收。
