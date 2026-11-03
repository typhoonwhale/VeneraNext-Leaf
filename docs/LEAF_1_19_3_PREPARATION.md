# Leaf 1.19.3 准备记录

更新：2026-11-03。本文件记录 1.19.3 准备分支及 `main` 保护约定；长期状态以 [Leaf 当前状态](LEAF_STATUS.md) 和[开发计划](LEAF_DEVELOPMENT_PLAN.md)为准。

## 分支与版本

- `release/leaf-1.19.3@bc6b8d6` 从 `main@09b0bd5` 建立，本轮只准备文档，未改源码或版本元数据。该分支记录的是准备过程，不改变 `main` 作为长期权威主线的地位。
- 正式版及 Leaf5+ 设备版本为 **1.19.2+253 / ARM64 versionCode 2532**；发布资产见 [GitHub Releases](https://github.com/typhoonwhale/VeneraNext-Leaf/releases)。
- 看过状态圆圈修复保存在独立远端分支 `fix/leaf-viewed-marker@2fb53b465a7a3c6fe0ba2d562640978ad46923e8`。修复已实现，使用 14 dp 外径、2.5 dp 线宽的矢量空心圆；尚未合入 `main` 或 `release/leaf-1.19.3`。
- 修复源分支的 55 项回归、全仓静态分析、格式检查和 Leaf5+ 设备系统截图对照通过，结果仅对应该源分支。参见[固定提交的验证说明](https://github.com/typhoonwhale/VeneraNext-Leaf/blob/2fb53b465a7a3c6fe0ba2d562640978ad46923e8/docs/research/2026-11-02-viewed-marker.md)。
- Leaf Activity 实测为 350 dpi、fontScale 0.85；设备运行正式版 1.19.2 / 2532。ADB 系统截图用于界面对照，不代表墨水屏面板的灰阶或残影。

## 后续整合要求

遵循[分支与功能文档规范](LEAF_BRANCH_WORKFLOW.md)。1.19.3 预备分支已经存在，不重复创建；圆圈修复后续须先合入该分支，不能直接向 main 合入。每次功能整合必须在预备分支的本文件汇总已整合功能、源分支／提交、专题文档、实际验证与剩余待办，并同步当前状态和开发计划。待本版本整合验证完成后，由 `release/leaf-1.19.3` 发起到 main 的 PR。

当前尚未执行功能整合：本文件的规范更新通过纯文档 PR 维护在 main，预备分支仍保持上述准备提交。下一次整合前须将最新 main 规范同步到预备分支并保留该分支已有记录。

## 已取消的专项验收

用户取消已读／看过专项实机、其他墨水屏专项、升级数据保留、应用内完整升级及 WebDAV 往返专项。日常使用暂未发现问题；这些专项不作为待办或发布门槛，也不据此声称测试通过。现有自动 CI 继续保留。

## main 保护与 CI

`main` 只能通过 PR 合入。PR 和 `main` push 保留现有自动 CI 触发及聚合门禁。分支保护保留原有全部必需检查，并新增质量检查与依赖安全聚合门禁；文档轻量路径只跳过昂贵作业，不绕过 PR、分支保护或聚合门禁。管理员同样遵守规则，禁止强推和删除 `main`，合并前解决 PR 讨论；单人维护时必需批准人数为 0，但仍必须使用 PR。

纯文档改动仅在变更范围完全落于以下 Markdown 路径时使用轻量门禁：

- 根目录 `README.md`、`README.en.md`。
- `docs/` 下的 Markdown 文件。
- `doc/` 下的 Markdown 文件。

`CHANGELOG.md` 会打包进应用，因此不属于轻量文档范围。纯文档门禁跳过 Flutter、Rust、Android 和依赖扫描，但保留路径范围检查与聚合门禁；代码、文档与代码混合、CI 配置改动以及发布标签、手动与定时运行均执行全检。范围检测失败或应运行的检查被跳过时，合并门禁失败。必需检查以 GitHub branch protection 的实际配置为准，文档不固定检查项数量或名称。
