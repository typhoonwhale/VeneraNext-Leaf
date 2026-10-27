# Leaf 墨水屏开发约束：官方 SDK 核心摘要

更新：2026-10-26。适用分支：`feature/leaf-eink-adaptation`，目标设备：BOOX Leaf5+。

按使用者要求，后续界面、动画及刷新改动以本摘要为重要设计与评审依据。官方文档给出通用建议；下表明确区分官方结论和项目采用方式。用户已确认的机型需求与例外保留；通用建议未在 Leaf5+ 上验证。

## 核心约束

| 方向 | 官方核心结论 | Leaf 采用方式 |
|---|---|---|
| 配色 | 页面以黑白灰为主 [1] | 白底黑字、高对比轮廓；状态用文字/图形辅助区分，不只依赖颜色。保留漫画灰阶和原图，不默认对全应用做二值化 |
| 表面 | 不在图文上叠加透明层 [1] | 控件优先不透明背景和清晰边界，减少磨砂、阴影及渐变；避免遮住正文 |
| 动态效果 | 优先分页，尽量避免滚动、拖动等动画 [1] | 优先无动画分页，减少转场、淡入和持续加载动画；保留必要滚动/缩放及明确反馈。减少中间画面，不以延迟响应代替优化 |
| 可读性 | 建议字体不小于 14sp，内嵌字体尽量加粗；中央/边缘按钮图标分别不小于 36dp/48dp [1] | 普通 UI 以此为设计参考，验证字重、对比和触达性。Flutter 逻辑字号需结合系统缩放实测 |
| 刷新取舍 | 快速模式偏响应，可能增加残影或丢失细节；REGAL 面向文字，GC 为灰阶全刷 [2][3] | 静态漫画优先画质，滚动场景再评估速度；文字模式对漫画是否最优待实测，不预设“每 N 页”全刷值 |
| 接口接入 | 官方提供 EPD 刷新 API，并建议应用使用较高层包装 [3][4] | 如需硬件控制，先验证官方 SDK 路线；确认 Leaf5+ 固件与 Flutter 渲染兼容性，再接入自动策略。接口细节、依赖版本与调用时序按需查索引 |

**已有明确例外：** 用户最新确认的阅读底栏采用横线1、固定间隔2、自然文字高度、底部留白0–15（默认4），字号9–13（默认11）；保持[分段底栏方案](research/2026-10-26-footer-spacing.md)，不按 14sp 放大；可读性按实机反馈调整。

## 实施与验收边界

- Flutter 重建、绘制帧、软件黑白闪屏和面板物理刷新分别看待；现有纯色覆盖层不是硬件全刷。
- 先验证一次手动刷新请求、画质/残影及系统模式交互，再决定自动触发；失败时保留普通显示路径，避免与现有闪屏重复触发。
- UI 可做自动布局和交互检查；残影、闪屏舒适度、响应和耗电需真机验证。记录固件、系统模式及测试场景。
- 当前只确认官方文档与候选调用路线，Leaf5+ 硬件接口未实机验证。偏离本摘要时，在对应实现记录中写明原因、用户已确认的取舍和验证结果。

## 按需查阅索引

以下链接固定到已核对的官方仓库 commit `ec512c79c0d39c1e294214d36580ce4c914bbea6`。接入或升级时再核对官方当前依赖与可用接口；本摘要不维护 API 清单。

| 索引 | 何时查看 | 官方入口 |
|---|---|---|
| [1] UI/UX | 改配色、菜单、动画、字体或按钮 | [Eink Develop Guide](https://github.com/onyx-intl/OnyxAndroidDemo/blob/ec512c79c0d39c1e294214d36580ce4c914bbea6/doc/Eink-Develop-Guide.md) |
| [2] 模式与画质 | 比较刷新速度、灰阶、残影 | [EPD Update Mode](https://github.com/onyx-intl/OnyxAndroidDemo/blob/ec512c79c0d39c1e294214d36580ce4c914bbea6/doc/EPD-Update-Mode.md) |
| [3] 刷新调用 | 研究局刷、全刷、交互快刷 | [EPD Screen Update](https://github.com/onyx-intl/OnyxAndroidDemo/blob/ec512c79c0d39c1e294214d36580ce4c914bbea6/doc/EPD-Screen-Update.md) |
| [4] 控制器入口 | 选择调用层次及包装方式 | [EpdController](https://github.com/onyx-intl/OnyxAndroidDemo/blob/ec512c79c0d39c1e294214d36580ce4c914bbea6/doc/EpdController.md) |
| [5] SDK 接入与示例 | 首次引入依赖或升级 | [官方仓库与 README](https://github.com/onyx-intl/OnyxAndroidDemo/tree/ec512c79c0d39c1e294214d36580ce4c914bbea6) |

项目细节按需阅读：[官方证据与源码调查](research/2026-10-25-eink-adaptation.md)、[开源实现参考](research/2026-10-25-eink-open-source.md)、[调研目录及接手规则](research/README.md)。开源项目仅补充实现思路。
