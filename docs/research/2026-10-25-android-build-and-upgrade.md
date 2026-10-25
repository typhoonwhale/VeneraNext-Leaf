# Android 包体积、身份与升级调查

调查日期：2026-10-25。目标：为Leaf5+提供体积合理、可长期覆盖升级的ARM64 Release包，避免日常试用反复导入数据。源码基线及未提交状态见[布局调查](2026-10-25-leaf5plus-layout.md)。

## 包身份与数据边界

| 类型 | applicationId | 签名与数据 |
|---|---|---|
| Leaf Debug | com.github.typhoonwhale.veneranext.leaf.debug | Android Debug签名，独立数据区；同签名Debug更新可覆盖 |
| Leaf Release | com.github.typhoonwhale.veneranext.leaf | 固定Leaf自有签名，独立数据区；后续同签名Release更新可覆盖 |
| 上游Android版 | com.github.cyrilpeng.veneranext | 与Leaf独立，不能当作Leaf覆盖升级基线 |

Android根据包名识别应用，更新还要满足签名和版本要求。Debug与Release不是共用数据的两种启动方式：本项目配置了不同包名，首次从Debug切换Release需导出/导入。确认迁移完整前保留旧应用，后续Release直接覆盖安装，不先卸载。

应用数据备份包括设置、收藏、历史、Cookie、漫画源文件等，**不含本地漫画图片**；图片通过漫画导出/导入另行迁移。依据：[应用数据同步说明](../../doc/user/data_sync.zh.md)、[本地漫画导入](../../doc/user/import_comic.zh.md)、[设置页导入导出实现](../../lib/features/settings/app.dart)。

## 体积调查

| 已构建样本 | 大小（字节） | 解释 |
|---|---:|---|
| 早期ARM64 Debug | 113,672,033 | 存在AGP增量更新APK遗留空间 |
| 去冗余ARM64 Debug | 78,466,148 | 与上述包908个ZIP条目集合及解压后内容一致，重新打包移除35,205,885字节冗余 |
| 紧凑底栏ARM64 Release / 2372 | 23,374,071 | 约23.37 MB / 22.3 MiB；AOT编译，不含Debug kernel快照，代码和资源优化启用 |

两类原因需分别判断：Debug本身包含调试运行内容；113MB到78MB则主要是增量打包空洞，并非删掉了功能。检查ZIP条目压缩大小之和、文件总大小及签名块后再归因，不能只看APK后缀或总大小。

若出现同类冗余，先保留旧包及身份记录，仅移走生成目录中的目标APK，再执行同一构建重新打包。不要删除交付包、整个工程或依赖缓存；重新核对ABI、签名、版本与内容。

三个样本的原始身份字段保存在[APK身份证据JSON](evidence/2026-10-25-apk-identities.json)。该JSON从本机验包记录复制，包含包名、大小、SHA-256与原生库清单；不包含APK文件，也不证明已经实机安装。

## 固定签名与当前构建参数

- 应用名：Leaf；图标保留上游主体并增加Leaf标记。
- 更新仓库：`typhoonwhale/VeneraNext-Leaf`；启动检查默认关闭，手动检查沿用应用入口。没有发布版本时不应声称已有可下载安装的GitHub Release。
- 已生成固定RSA 3072位签名，alias `leaf-release`；公开证书SHA-256：`ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909`。证书指纹不是私钥；不要为下一次构建重新生成密钥。
- 私有签名材料使用Git忽略的`android/keystore.jks`和`android/key.properties`，已在本机保存和另存副本，离线安全备份仍需维护者确认。本目录不保存密钥、密码或机器私有路径。
- 当前交付版本名1.18.1，紧凑版ARM64 versionCode=2372，上一版Release为2362。Gradle对ARM64应用`flutter build-number × 10 + 2`，本次通过`--build-number=237`递增；`pubspec.yaml`仍为`1.18.1+236`，复构建及新迭代必须显式核对版本，不能不带参数就误造较低版本。

本轮构建命令：

```sh
flutter build apk --release --target-platform android-arm64 --build-number=237 --no-pub
```

工具链使用仓库锁定的Flutter 3.41.4、Dart 3.11.1、JDK17、NDK28.0.13004108、Rust1.92.0。本机Android SDK/build-tools为36，包要求Android API24或以上；**这些是构建参数，不是Leaf5+实机系统版本**。

交付取`build/app/outputs/apk/release/VeneraNext-Leaf-1.18.1-android-arm64-v8a.apk`。Flutter打印的`build/app/outputs/flutter-apk/app-release.apk`可能是universal副本，不能据此认定只含ARM64；需要用aapt或ZIP实际检查。

## 已验证与待验证

2372包的签名、显示名、包名、版本、ZIP完整性、仅ARM64、必需原生库、AOT库、非debuggable及无Debug kernel快照检查通过，签名证书与2362一致。APK SHA-256为`f3282e1dfe6ac9a7b4f5d61ac9335cf80d32442657ad83482a4d77dd74caedb0`。

Release资源优化会重命名图标路径，检查器应按aapt资源表解析实际路径；不能把Debug里固定的`res/mipmap-xxxhdpi-v4/...`路径用于Release。之前检查脚本因此首次提取失败，修正映射读取后通过，不属于APK构建失败。

使用者确认上一版Release功能正常，但2372的紧凑布局、实际覆盖升级保留数据和完整备份迁移仍待实机验收。没有创建公开GitHub Release、上传签名Secrets或推送本轮源码；此状态是调查时记录，之后需重新核对。

后续操作入口：[Leaf构建说明](../LEAF_BUILD.md)。验证结果需记录具体包哈希，不要仅以“最新版”作为产物身份。
