# Leaf 1.19.3 准备记录

更新：2026-11-07。本文件记录 1.19.3 准备分支及 `main` 保护约定；长期状态以 [Leaf 当前状态](LEAF_STATUS.md) 和[开发计划](LEAF_DEVELOPMENT_PLAN.md)为准。

## 分支与版本

- `release/leaf-1.19.3` 从 `main@09b0bd5` 建立（准备提交 `bc6b8d6`）。2026-11-07 整合两个修复，并经 `fix/leaf-chapter-cache-head` 同步了 `main@4e848a4` 的规范与 CI 改动；版本元数据仍为 1.19.2+253，发版时再递增。该分支记录的是准备过程，不改变 `main` 作为长期权威主线的地位。
- 正式版及 Leaf5+ 设备版本为 **1.19.2+253 / ARM64 versionCode 2532**；发布资产见 [GitHub Releases](https://github.com/typhoonwhale/VeneraNext-Leaf/releases)。
- Leaf Activity 实测为 350 dpi、fontScale 0.85；设备运行正式版 1.19.2 / 2532。ADB 系统截图用于界面对照，不代表墨水屏面板的灰阶或残影。

## 已整合功能

| 功能 | 实际行为 | 源分支与提交 | 整合提交 | 功能文档 |
|---|---|---|---|---|
| 看过状态圆圈修复 | 章节“看过”标记由字体字符改为 14 dp 外径、2.5 dp 线宽的矢量空心圆，与已读勾同尺度 | `fix/leaf-viewed-marker@2fb53b4` | `b3d67f8` | [问题、实测比例与修复](research/2026-11-02-viewed-marker.md) |
| 瓜子章节往前翻回后显示空章节 | 网络缓存不再用 HEAD 校验，过期条目直接 GET，避免瓜子服务器把 HEAD 刷新成空正文缓存 | `fix/leaf-chapter-cache-head@e662b3f`（代码 `9919295`） | `3d919e7` | [停止用 HEAD 校验网络缓存](features/leaf-chapter-cache-head.md) |

整合时，预备分支准备提交与 main 的文档提交在状态、开发计划、构建、路线图和本文件上冲突，按 main 一侧为准解决，再在本次整合中补记以上内容。相对 `main@4e848a4`，代码差异仅为这两个修复。

## 验证情况

- 功能分支：
  - 看过圆圈修复：55 项回归、全仓静态分析、格式检查和 Leaf5+ 设备系统截图对照通过（2026-11-03）。
  - 缓存修复：缓存相关 20 项测试通过，全仓静态分析无问题；Leaf5+ 用受控服务器做了修复前后 Debug 包对照，修复前复现空章节且重试无效，修复后只发 GET、章节正常。详见功能文档。
- 预备分支整合后（`3d919e7`，2026-11-07，本机）：`cache_revalidation_test.dart`、`cache_test.dart`、`app_dio_test.dart`、`chapters_test.dart` 共 48 项通过；`flutter analyze --fatal-infos lib test` 无问题；改动的 6 个 Dart 文件格式无变化；架构依赖检查通过。完整 Linux CI 以预备分支到 main 的 PR 检查为准。

## 剩余待办

- [ ] 由 `release/leaf-1.19.3` 发起到 main 的 PR，通过 main 保护要求的 CI。
- [ ] 发版前递增版本元数据并构建正式包；Release 覆盖升级按发布流程核对。
- 缓存修复：真实瓜子网络下的长期表现未验证；已被其他客户端写坏的服务器缓存仍可能导致短时空章节，需源脚本处理，不在本版本范围。

## 调整记录

无。

## 已取消的专项验收

用户取消已读／看过专项实机、其他墨水屏专项、升级数据保留、应用内完整升级及 WebDAV 往返专项。日常使用暂未发现问题；这些专项不作为待办或发布门槛，也不据此声称测试通过。现有自动 CI 继续保留。

## main 保护与 CI

`main` 只能通过 PR 合入。PR 和 `main` push 保留现有自动 CI 触发及聚合门禁。分支保护保留原有全部必需检查，并新增质量检查与依赖安全聚合门禁；文档轻量路径只跳过昂贵作业，不绕过 PR、分支保护或聚合门禁。管理员同样遵守规则，禁止强推和删除 `main`，合并前解决 PR 讨论；单人维护时必需批准人数为 0，但仍必须使用 PR。

纯文档改动仅在变更范围完全落于以下 Markdown 路径时使用轻量门禁：

- 根目录 `README.md`、`README.en.md`。
- `docs/` 下的 Markdown 文件。
- `doc/` 下的 Markdown 文件。

`CHANGELOG.md` 会打包进应用，因此不属于轻量文档范围。纯文档门禁跳过 Flutter、Rust、Android 和依赖扫描，但保留路径范围检查与聚合门禁；代码、文档与代码混合、CI 配置改动以及发布标签、手动与定时运行均执行全检。范围检测失败或应运行的检查被跳过时，合并门禁失败。必需检查以 GitHub branch protection 的实际配置为准，文档不固定检查项数量或名称。
