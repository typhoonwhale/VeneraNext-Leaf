# 2026-10-25 底栏开发与验证记录

> 历史记录，其中的高度和字号参数已被 2026-10-26-footer-spacing.md 取代。

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
