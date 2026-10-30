# Leaf 当前状态与分支说明

核对日期：2026-10-30。1.19.0 发布信息来自 GitHub，设备结果来自 2026-10-29 已有实机记录；本分支已完成 1.19.1 本地专项验证，尚未重新连接设备。

## 正式版

- 最新正式版：[Leaf 1.19.0](https://github.com/typhoonwhale/VeneraNext-Leaf/releases/tag/v1.19.0)，Android ARM64，versionCode **2502**；2026-10-29 18:05（北京时间）由 CI 发布。
- `main` 与 `v1.19.0` 指向 `b416a697079764b046caf0015ca6c200ba7c11d6`。[PR #3](https://github.com/typhoonwhale/VeneraNext-Leaf/pull/3) 已合入，8 项 CI 检查成功；全量 Flutter 测试在 Linux CI 上通过。macOS 原生依赖限制仍存在，不能把 CI 结果写成本机全量通过。
- 包含独立阅读底栏、1.18.4 的应用内更新，以及默认开启的黑白墨水屏模式和减少动画；设置 → 外观可关闭墨水屏模式。
- 历史实机记录确认 Leaf5+ 正式包从 1.18.4 应用内升级到 1.19.0，数据保留；此前的 `.eink` 测试包已卸载。设备当前状态需在后续实测时重新核对。
- 资产 `VeneraNext-Leaf-1.19.0-android-arm64-v8a.apk`，23,475,467 字节；GitHub SHA-256：`656dedd70e932f4c8134e47678113f07f43f1cfda63887cc59dfc97ebe97301b`。本次未重新下载或验签 APK。

## 本分支

- 分支：`feature/leaf-read-state`；代码基线：`b416a697079764b046caf0015ca6c200ba7c11d6`；`pubspec.yaml`：`1.19.1+251`。
- 本分支以 1.19.0 为基线，已实现 1.19.1 章节已读/看过规则并通过本地专项验证；当前改动尚未发布。
- 文档引用的版本和验收范围需与代码基线一起阅读；历史构建记录中的旧版本号和失败结果继续保留。

2026-10-30 核对到的分支如下；不代表以后不会变化。

| 分支 | 代码基线 | 用途 |
|---|---|---|
| `main` | `b416a69` / 1.19.0+250 | 当前开发、正式发布基线 |
| `feature/leaf-read-state` | 基于 `b416a69` / 本地 1.19.1+251 | 已读/看过规则实现与专项验证完成；未推送、未发布 |
| `feature/leaf-eink-adaptation` | `274b3db` / 1.18.2+240 | 早期墨水屏调研；远端仍保留，非 1.19.0 实现分支 |
| `feature/leaf-reader-footer` | `3eac32b` / 1.18.1+236 | 本地早期底栏分支，远端已无同名分支 |
| `feature/leaf-release-ci` | `a17a9dc` / 1.18.2+240 | 本地早期 CI 分支，远端已无同名分支 |

旧分支清理尚未决定；不为更新文档删除分支、重写历史或变更已有 tracking upstream。

## 本分支新增功能

[1.19.1 章节状态说明](LEAF_READ_STATE.md)记录已确认行为、数据兼容、源码入口与验收要求。当前尚未发布，验证以实际结果为准。

## 后续工作

1. **1.19.1 章节状态**：已确认增加“看过”、长按手动标记、保留旧已读数据与续读位置；已读改为会话内正向阅读判定，常规章节需末页显示且正向经过至少一半图片、下限 3 张，短章另行处理。D1 已确认启用续读补偿（允许此前跳页被补计）；D2–D8（清除语义、批量范围等）已全部按建议确认，已在本分支完成实现。本地阅读器专项 78 项、历史/UI/备份导入等 365 项通过，7 项 Windows 专属既有测试跳过；静态分析、架构与格式检查通过。完整 Linux CI、实机和跨设备同步待验。当前正式版 1.19.0 仍按加载页面记录已读。
2. **更新下载**：当前网络超时为 30 秒；1.19.0 首次下载曾超时，Mac 完整下载资产后设备重试成功。CDN 冷缓存是当时记录的推断，未单独证明因果。放宽超时、可选镜像仍是候选，不是已有能力；镜像不能绕过 SHA-256、包身份和签名校验。
3. **墨水屏后续**：图片收藏封面样式、直接 `showDialog` 转场、未处理的不确定线性进度动画；文石 SDK 硬件全刷和同条件 60 分钟耗电对照均未完成。

## 开发与验证入口

- 开工前核对分支、HEAD、工作区和 upstream；新功能基于当次核实的 `origin/main`，不从上述旧功能分支继续。
- 本地按变更运行专项测试、结构/架构检查、改动 Dart 文件格式检查及 `flutter analyze --fatal-infos --fatal-warnings`；新增 lib 文件登记架构依赖基线。全量验证以 PR 的 Linux CI 为准，设备交互与能耗另作实测。
- 正式流程：功能分支 → PR → CI 通过 → 合入 main → 附注 `v*` 标签 → CI 发布。推送与发布遵循当次授权。ARM64 构建保留 `--split-per-abi`、固定签名和递增版本码；1.19.0 发布时签名 secrets 已配置，无需重新创建密钥。
- 当前主线的[构建说明](https://github.com/typhoonwhale/VeneraNext-Leaf/blob/b416a697079764b046caf0015ca6c200ba7c11d6/docs/LEAF_BUILD.md)、[墨水屏组件指南](https://github.com/typhoonwhale/VeneraNext-Leaf/blob/b416a697079764b046caf0015ca6c200ba7c11d6/docs/LEAF_EINK_UI.md)、[应用内更新验收](https://github.com/typhoonwhale/VeneraNext-Leaf/blob/b416a697079764b046caf0015ca6c200ba7c11d6/docs/LEAF_IN_APP_UPDATE_VALIDATION.md)；本分支入口：[开发方案](LEAF_DEVELOPMENT_PLAN.md)、[构建说明](LEAF_BUILD.md)、[调研索引](research/README.md)。
