# Leaf 当前状态与分支说明

更新：2026-10-30。当前正式版为 [1.19.0](https://github.com/typhoonwhale/VeneraNext-Leaf/releases/tag/v1.19.0)，versionCode 2502，主线 `b416a697079764b046caf0015ca6c200ba7c11d6`。本轮没有更新远端或操作设备。

本工作区为 `fix/leaf-empty-chapter`，从上述本地主线建立，无 upstream，版本配置仍为 `1.19.0+250`。本轮空章节修复已完成，本地 280 项通过、23 项既有 Windows 专属测试跳过，全量静态分析与专项检查通过，行为和验证见[空章节加载错误与重试](LEAF_EMPTY_CHAPTER_FIX.md)。本页为当前状态入口；继承文档中的版本与早期分支描述需按各自记录日期阅读。

| 分支 | 当前代码状态 |
|---|---|
| `main` | 1.19.0 发布基线 `b416a69`，未合入本次修复 |
| `fix/leaf-empty-chapter` | 独立修复空图片列表导致无重试错误，尚未推送或发布 |
| `feature/leaf-read-state` | 本地 `98694ef`，已读/看过功能及专项完成，未合入、推送或发布；与本次修复独立 |
| `feature/leaf-eink-adaptation` | 早期调研基线 `274b3db`，当前仅补文档 |
| `feature/leaf-reader-footer` | 早期底栏基线 `3eac32b`，当前仅补文档，原 upstream 已 gone |
| `feature/leaf-release-ci` | 早期 CI 基线 `a17a9dc`，当前仅补文档 |

正式发布仍走功能分支 → PR → Linux CI → 合入 main → 附注标签。此次没有创建 PR、改 tracking、合并、推送、改版本或发布。设备日志尚待回收，以确认瓜子源版本与首次空列表的具体网络/解析原因。
