# 停止用 HEAD 校验网络缓存

- 功能分支：fix/leaf-chapter-cache-head
- 创建基线：origin/main@4e848a445013989bcd9dcb8d1aa1560e6cd1d722
- 目标预备分支：release/leaf-1.19.3
- 状态：实现中（代码与单元测试已完成，待 Leaf5+ 实测）

## 功能与范围

问题：在瓜子源中打开新章节后往前翻回上一章，或退出后重进，偶尔显示“本章未返回任何图片，请重试”，点击重试也无法恢复。

原因：`lib/network/cache.dart` 对存在 5 秒到 2 小时的缓存条目，先发 HEAD 请求校验，再决定是否复用。瓜子服务器用 HEAD 请求刷新已过期（`x-guazi-chapter-cache: STALE`）的章节缓存时，会把空正文写入缓存。紧接着的 GET 和此后几分钟内的重试都拿到 `200 HIT`、正文 0 字节，源脚本解析不到图片。瓜子每次响应的 `x-guazi-chapter-cache` 都不同，所以 HEAD 校验从未成功复用过缓存，每次都要再发 GET。

2026-11-07 设备日志证据：4 次 HEAD 碰到 STALE，之后的 GET 全部为空正文；HEAD 碰到 HIT 的 3 次，以及首次打开的 13 次，全部正常。带随机参数绕过服务器缓存的请求返回 `BYPASS` 和完整页面。

预期行为：网络缓存不再发 HEAD。缓存条目存在不到 5 秒（`cache-time: long` 时为 6 小时）直接复用，其余情况删除旧条目，正常发 GET。

验收条件：
- 缓存过期后只发一次 GET，不发 HEAD。
- 新鲜缓存仍直接复用；`long` 缓存的复用期限不变；取消、并发等原有语义保持不变。
- Leaf5+ 上用 Debug 包打开章节，翻到下一章，停留 5 秒以上再翻回：网络日志中没有 HEAD，章节正常显示。

不在范围内：源脚本遇到空页面时带随机参数重试（已被其他客户端写坏的服务器缓存需要脚本处理），以及画廊模式加载失败时补错误日志。

## 已实现

- `NetworkCacheInterceptor` 不再发 HEAD：新鲜缓存直接复用，其余情况删除旧条目后直接 GET。只为 HEAD 重放服务的 `captureRequests`、请求头快照和客户端引用一并移除，`AppDio` 只注册一个缓存拦截器。
- `test/network/cache_revalidation_test.dart` 删除 HEAD 专属用例（失败透传、405/501 回退、cookie 重放、HEAD 取消清理及 Windows 原生 HEAD 用例），新增新鲜复用、过期只发 GET、`long` 6 小时边界、`cache-time: no`、复用前取消等用例，保留授权头、responseType、GET 带正文绕过缓存等通用语义。

## 待办

- [x] 移除 `NetworkCache` 拦截器中的 HEAD 校验
- [x] 调整缓存回归测试
- [x] 静态分析、格式和架构检查
- [ ] Leaf5+ Debug 包实测
- [ ] 整合至预备分支并更新版本功能与待办汇总

## 验证与边界

- 本地：`cache_revalidation_test.dart`、`cache_test.dart`、`app_dio_test.dart` 共 20 项通过；`flutter analyze --fatal-infos lib test` 无问题；改动文件 `dart format` 无变化；架构依赖检查通过。`test/network/` 全目录另有 19 项 `image_config_ownership_test.dart` 因本机缺 Rust 原生库失败，改动前基线同样失败。完整 Linux CI 以 PR 检查为准。
- Leaf5+ 实测：待执行。
