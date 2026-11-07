# Leaf 当前状态

更新：2026-11-07。`main` 是长期权威主线；正式版与 Leaf5+ 设备当前版本均为 **1.19.2+253 / ARM64 versionCode 2532**。发布资产见 [GitHub Releases](https://github.com/typhoonwhale/VeneraNext-Leaf/releases)。

## 已发布

1.19.2 包含章节已读／看过、紧凑信息区和墨水屏 UI／动画遗漏补齐。相关整合于 2026-11-02 通过 [PR #6](https://github.com/typhoonwhale/VeneraNext-Leaf/pull/6) 合入 `main`（`2008382`）。当时 8 项 PR 检查成功，完整 Linux Flutter 为 5627 通过、151 跳过；信息区布局模拟和定向截图验证记录见[整合验收](research/2026-11-02-integration-validation.md)。

## 已整合到 1.19.3 预备分支

`release/leaf-1.19.3` 已整合以下两个修复，尚未合入 `main` 或发布；整合记录、验证与剩余待办见[准备记录](LEAF_1_19_3_PREPARATION.md)。

- 看过状态圆圈修复（`fix/leaf-viewed-marker@2fb53b4`）：矢量空心圆替换字体字符，见[问题、实测比例与修复](research/2026-11-02-viewed-marker.md)。
- 瓜子章节往前翻回后显示空章节（`fix/leaf-chapter-cache-head@e662b3f`）：网络缓存不再用 HEAD 校验，见[功能文档](features/leaf-chapter-cache-head.md)。

## 设备与截图边界

Leaf Activity 实测配置为 350 dpi、fontScale 0.85。设备目前运行正式版 1.19.2 / 2532。ADB 系统截图可用于界面布局对照，不代表墨水屏面板的灰阶或残影表现。

## 后续候选

以下均为低优先级候选，不是当前版本或发布门槛：

- 瓜子服务器缓存若被其他客户端写成空正文，仍可能短时返回空章节，需源脚本带随机参数重试；错误页 1/1 占位可后续处理。
- 应用内更新剩余异常组合保留为按需候选，已有覆盖见[更新验收记录](LEAF_IN_APP_UPDATE_VALIDATION.md#历史发布与实机覆盖截至-2026-10-30)，不另设当前专项验收。
- 下载慢的原因尚未确认；放宽超时或增加镜像均未实施。
- 墨水屏 SDK 手动刷新和同条件耗电对照可按后续需求评估；不默认增加自动全刷。
- 日期中英文与数字的视觉对齐暂缓，先核对设备字体，不加固定偏移。

保留漫画原图，不新增客户端灰度转换。

## 用户取消的专项验收

用户取消了已读／看过专项实机、其他墨水屏专项、升级数据保留、应用内完整升级及 WebDAV 往返专项。日常使用暂未发现问题；取消专项不表示测试通过，也不作为待办或发布门槛。

## 开发入口

开发前必须阅读[分支与功能文档规范](LEAF_BRANCH_WORKFLOW.md)。新功能从当前分支新建分支并初始化功能／待办，先整合进下一小版本预备分支并汇总文档，再由预备分支通过 PR 合入 main；纯文档维护可直接发 PR 到 main 并走轻量门禁，其他改动按核心 CI 验证。主线保护和路径范围见[准备记录](LEAF_1_19_3_PREPARATION.md)。开发计划、功能清单和构建说明见[开发入口](LEAF_DEVELOPMENT_PLAN.md)与[构建说明](LEAF_BUILD.md)。
