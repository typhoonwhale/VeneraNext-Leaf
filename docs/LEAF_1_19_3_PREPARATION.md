# Leaf 1.19.3 预备说明

更新：2026-11-03。

## 分支与版本

- `release/leaf-1.19.3` 从 `origin/main@09b0bd51be451930094fabfbfcf19afb7b2c3cb6` 建立；本轮只更新准备文档，源码尚未改动。
- 正式版仍为 1.19.2+253 / ARM64 versionCode 2532。准备期间保持版本元数据不变；发布与资产以 [GitHub Releases](https://github.com/typhoonwhale/VeneraNext-Leaf/releases) 为准。
- 独立分支 `fix/leaf-viewed-marker@2fb53b465a7a3c6fe0ba2d562640978ad46923e8` 已保存到远端，分支保留；看过圆圈修复待纳入本准备分支。修复将字体字符换成 14 dp 外径、2.5 dp 线宽的矢量空心圆。
- 修复源分支的 55 项回归、全仓静态分析、格式检查及 Leaf5+ 设备系统截图对照已通过。这些结果只对应源分支，不代表 `release/leaf-1.19.3` 已完成验证。见固定提交的[问题与验证记录](https://github.com/typhoonwhale/VeneraNext-Leaf/blob/2fb53b465a7a3c6fe0ba2d562640978ad46923e8/docs/research/2026-11-02-viewed-marker.md)。原始截图含用户阅读内容，仅留本地；系统截图不代表墨水屏面板的灰阶与残影观感。
- 实测 Leaf Activity 配置为 350 dpi、fontScale 0.85；测试后设备已恢复官方 1.19.2 / 2532。

## 已取消的专项验收

用户决定不再安排以下专项：

- 已读／看过功能实机验收。
- 其他墨水屏体验专项实机验收。
- 升级数据保留、应用内完整升级和 WebDAV 跨设备往返。

日常使用暂未发现问题。这是日常使用反馈，不代表上述专项测试通过；上述专项不再作为当前待办或 1.19.3 发布门槛。现有自动 CI 继续保留。

## main 保护规则

`main` 保护已启用，并通过 GitHub API 回读核实：`protected=true`，HEAD 仍为 `09b0bd51be451930094fabfbfcf19afb7b2c3cb6`。规则如下：

- 必须通过 PR 合入，并严格要求分支更新到最新 main 后才能合并。
- 以下 6 项 GitHub Actions 检查全部作为合并门禁：`analyze`、Flutter 测试与覆盖率、Rhttp 原生回调生命周期、平台冒烟构建门禁、依赖安全审查、Rust 锁定依赖漏洞扫描。
- 管理员同样遵守保护规则；禁止强推和删除 main；合并前解决 PR 讨论。
- 单人维护，必需批准人数设为 0；仍必须通过 PR 和上述 CI。

准备分支后续合入 main 时按以上规则走 PR；本轮只保存分支和准备文档，不创建合并 PR、版本标签或 Release。
