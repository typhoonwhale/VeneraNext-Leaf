# Leaf 当前状态与分支说明

更新：2026-10-31。正式发布基线为 [1.19.0](https://github.com/typhoonwhale/VeneraNext-Leaf/releases/tag/v1.19.0)，versionCode 2502，提交 `b416a697079764b046caf0015ca6c200ba7c11d6`；本轮实机确认正式包仍为 1.19.0 / 2502，没有覆盖升级。

本次空章节修复的开发分支为 `fix/leaf-empty-chapter`，实现提交 `c8eb87a`，从上述正式主线建立，版本配置仍为 `1.19.0+250`。本地 280 项通过、23 项既有 Windows 专属测试跳过，全量静态分析与专项检查通过，行为和验证见[空章节加载错误与重试](LEAF_EMPTY_CHAPTER_FIX.md)。以下记录本次修复的代码来源；最新分支位置与合入状态以 Git 和对应 PR 为准。

| 分支 | 本次核对的代码来源与范围 |
|---|---|
| `main` | 本次修复采用的 1.19.0 发布基线为 `b416a69` |
| `fix/leaf-empty-chapter` | `c8eb87a` 独立修复空图片列表导致无重试错误，尚未发布 |
| `feature/leaf-read-state` | 本地 `98694ef`，已读/看过功能及专项完成，未合入、推送或发布；与本次修复独立 |
| `feature/leaf-eink-adaptation` | 早期调研基线 `274b3db`，当前仅补文档 |
| `feature/leaf-reader-footer` | 早期底栏基线 `3eac32b`，当前仅补文档，原 upstream 已 gone |
| `feature/leaf-release-ci` | 早期 CI 基线 `a17a9dc`，当前仅补文档 |

2026-10-31 已在 Leaf5+ 上验证独立 Debug 包 `1.19.0-emptyfix.1 / 2504`：受控空列表错误页、点击重试恢复 3 图、旧请求延迟 10 秒期间退出重进及后续翻页通过。正式版的两次瓜子在线尝试未复现原错误；瓜子源 UI 版本已确认 1.0.4，现有历史日志没有原异常栈，首次空列表的现场原因仍未确定。[验证范围](LEAF_EMPTY_CHAPTER_FIX.md#验证)。本轮测试包与临时环境已移除，设备回到正式版主页。

正式发布仍走功能分支 → PR → Linux CI → 合入 main → 附注标签。合入代码不等于发布新版；Debug 实测不等于 Release 覆盖升级验收，完整 Linux CI 以对应 PR 的检查结果为准。
