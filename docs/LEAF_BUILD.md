# VeneraNext Leaf Android 构建

本文记录 Leaf Android 包的身份、更新和签名边界，以及可复现的本地构建入口。Leaf 基于 VeneraNext v1.18.1 源码。1.18.2 / 2402 由本机固定签名构建后手动上传 GitHub Release；配置签名 secrets 后，推送 `v*` 标签由 CI 构建并发布。

## Android 身份与隔离

Release APK 的 `applicationId` 是 `com.github.typhoonwhale.veneranext.leaf`，系统显示名是 `Leaf`。官方版的包名仍为 `com.github.cyrilpeng.veneranext`，两者可并行安装，Android 会为它们提供不同的应用数据目录。旧版 `data.venera` 只会在用户手动导入后进入 Leaf 自己的数据区；归档中的旧更新设置不能改变 Leaf 的更新来源。

Gradle `namespace` 和 Kotlin 源码包名暂时保留上游值，因为 Android 入口和原生类仍位于 `com.github.cyrilpeng.veneranext`。它们是编译期命名空间，不决定已安装应用的身份。`share_plus` 的 Provider authority 使用 `${applicationId}.flutter.share_provider`，因此合并到 Leaf 后为 `com.github.typhoonwhale.veneranext.leaf.flutter.share_provider`，不会和官方版重复。

Android Manifest 不再注册 `nhentai.net`、`e-hentai.org`、`exhentai.org` 的 HTTPS `VIEW` 深链，以免两个应用同时成为同一网页链接的候选处理程序。文本分享 `ACTION_SEND` 入口保留。debug 构建使用 `com.github.typhoonwhale.veneranext.leaf.debug`，可与签名 Release 并装；它与 Release 使用不同包名和数据区。

## 图标

Android 使用保留上游主体、右下方带高对比 `Leaf` 标记的图标。可编辑源文件为 `assets/leaf_icon.svg`，应用内图片为 `assets/leaf_icon.png`；普通、自适应及单色主题启动图标均已更新，标记处于自适应图标安全区。上游 SVG 与其他平台图标保留。

## 更新来源与签名

Android 更新来源默认为 `typhoonwhale/VeneraNext-Leaf`。“关于”页手动检查和更新提示均使用该仓库；“启动时检查更新”沿用原有设置，默认关闭，用户可自行打开。旧备份只能改变该开关，不能将更新来源改回上游。其他平台仍使用 VeneraNext 上游更新渠道。

可通过构建参数 `LEAF_ANDROID_RELEASE_REPOSITORY` 覆盖默认仓库；配置值必须是 `owner/repository`，且不能指向 `CyrilPeng/venera-next`（大小写不敏感）。显式传空值可关闭 Android 应用更新查询。1.18.3开发分支新增应用内下载并调用系统安装器，规则见[应用内更新方案](LEAF_IN_APP_UPDATE_DESIGN.md)。资产需来自所选仓库且包含SHA-256摘要；校验包名、签名、版本及ARM64后才能安装。Debug与Release身份不同，Debug只提供手动发布页入口。已发布1.18.2仍需从发布页手动下载。

Leaf Release 必须使用一把固定、长期保管并离线备份的自有 keystore。上游 GitHub Secrets 不会提供给 fork，不能拿上游密钥，也不能每次临时生成新密钥。没有有效 `android/key.properties` 和对应 keystore 时，Gradle Release 任务和 GitHub Release 构建都会明确失败；CI 的 Debug 构建不代表可升级发布包。首次生成后不得重新生成或随意轮换 keystore，否则会破坏已安装 Leaf 与后续 APK 的覆盖升级关系。

本地 keystore 放在 `android/keystore.jks`，该文件和 `android/key.properties` 已由 Android `.gitignore` 排除。`key.properties` 格式如下，密码只填入本机私有文件，不提交：

```properties
storeFile=../keystore.jks
storePassword=<keystore password>
keyAlias=<key alias>
keyPassword=<key password>
```

若配置 GitHub Actions，仓库维护者需要自行准备 `ANDROID_KEYSTORE`（固定 keystore 文件的 Base64 内容）与 `ANDROID_KEY_PROPERTIES`（上述属性文本）两个 secrets。本次经用户授权已在本机创建固定 Leaf Release 签名，alias 为 leaf-release；主文件保存在上述 Git 忽略路径，并在本机工具目录保留权限受限的同内容副本，尚待用户离线备份。证书 SHA-256 为 ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909。CI 发布需把这两个值配置为仓库 secrets（见“Leaf 正式发布”）；Debug 仍使用 Android 自动生成的测试签名。

## 构建环境

构建版本由仓库锁定：

- Flutter 3.41.4；`pubspec.lock` 要求 Dart 3.11.0 或更新版本，使用该 Flutter 自带 Dart。
- JDK 17；Gradle wrapper 8.14、Android Gradle Plugin 8.12.3、Kotlin Android 插件 2.1.0。
- Android SDK platform/build-tools 与该 Flutter 版本兼容；Gradle 从 Flutter 插件读取 `compileSdkVersion` 与 `targetSdkVersion`。
- Android NDK `28.0.13004108`。
- Rust `1.92.0`；`rust-toolchain.toml` 会选择 `aarch64-linux-android`、`armv7-linux-androideabi`、`x86_64-linux-android` targets。

先安装 Android Studio/SDK、Rust 工具链和 JDK，然后核对环境：

```sh
flutter doctor -v
java -version
rustup show
adb version
```

从仓库根目录获取锁定依赖并构建 ARM64 Debug APK：

```sh
flutter pub get --enforce-lockfile
flutter build apk --debug --target-platform android-arm64 --split-per-abi
```

Debug 包不需要 Leaf keystore，输出为 `build/app/outputs/apk/debug/app-arm64-v8a-debug.apk`，Flutter副本为 `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`。必须带 `--split-per-abi`，让Flutter按分包文件名查找产物；旧目录中的 `app-debug.apk` 可能是历史通用包，不应交付。设备可同时安装官方版、Leaf Release 与 Leaf Debug。

本机已放置固定 keystore 和 `android/key.properties` 后，构建 ARM64 Release APK：

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

默认已连接自有仓库，也可以显式指定同一来源：

```sh
flutter build apk --release \
  --target-platform android-arm64 --split-per-abi \
  --dart-define=LEAF_ANDROID_RELEASE_REPOSITORY=typhoonwhale/VeneraNext-Leaf
```

不传该 `dart-define` 时，Android 使用上述 Leaf 仓库。不要将它设为上游仓库。

安装前可检查 APK 包名与签名证书指纹：

```sh
apkanalyzer manifest application-id build/app/outputs/apk/release/VeneraNext-Leaf-*-android-arm64-v8a.apk
apksigner verify --print-certs build/app/outputs/apk/release/VeneraNext-Leaf-*-android-arm64-v8a.apk
```

升级时 applicationId、keystore、key alias 和签名证书必须与前一版一致，且 `versionCode` 必须增加。发布前应由维护者对照上一版记录的证书 SHA-256 指纹；仅仅成功生成 APK 不足以证明它可覆盖升级。

## 验证入口

Leaf 身份和签名配置静态检查：

```sh
python3 -m unittest discover -s .github/scripts/tests -p 'test_leaf_android_identity.py'
```

Android 更新渠道检查：

```sh
flutter test --no-pub test/app_runtime/application_updates_test.dart
flutter test --no-pub test/foundation/application_update_service_test.dart
```

全量 Flutter、原生和实机验证另按开发计划执行；这份文档不把本地 Debug 构建或静态检查称为设备验收。

## 增量打包与交付体积

AGP 增量更新 APK 时可能保留旧 ZIP 条目占用的空闲区域。若文件大小显著超过所有 ZIP 条目的压缩大小之和，在保存旧包身份和验证记录后移走生成的目标 APK，再执行同一构建命令即可重新打包；无需删除整个 Flutter/Gradle 缓存。交付前验证新包签名、ABI、版本以及与旧包的条目内容一致性。本轮重打包将同内容 Debug 包从 113.67 MB 降至 78.47 MB。

## Leaf 正式发布

首次公开发布为1.18.2（build240，ARM64 versionCode2402），发布到本仓库的GitHub Releases。Android检查更新比较Release标签和应用内版本号，忽略build后缀；因此每次正式发布都须递增 `release.json.version` 并同步 `pubspec.yaml`，仅增加build不会产生更新提示。发布标签使用 `v<version>`，更新说明来自CHANGELOG对应节。

Leaf仅维护Android ARM64产物；工作流职责见下表。正式发布流程：

1. 修改 `CHANGELOG.md`（新增 `## v<version>` 一节）、`pubspec.yaml` 和 `release.json`，保持版本一致。
2. 提交到 main。
3. 推送 `v*` 标签，格式为 `v1.2.3` 或 `v1.2.3-rc.1`。
4. CI 自动校验标签与元数据、质量检查、固定签名构建，用 `apksigner` 核对证书 SHA-256 为 `ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909`，核对 `SHA256SUMS.txt` 后创建 Release 并上传 APK 与摘要；`-rc` 等含 `-` 的标签发布为预发布。

首次使用前，在仓库 Settings → Secrets and variables → Actions 中配置：

- `ANDROID_KEYSTORE`：固定 keystore 文件的 Base64 内容。
- `ANDROID_KEY_PROPERTIES`：`android/key.properties` 的原文。

缺少任一值或证书指纹不符时，工作流失败，不会创建 Release。不要上传keystore或key.properties到仓库；不要在没有同一签名的情况下改用临时签名。

本机构建为备用方式：使用固定签名构建ARM64包，核对版本、内置pubspec、证书、ABI和SHA-256后，上传GitHub Release草稿，再正式发布为Latest。

使用发布API回读 `releases/latest` 确认新版本与APK资产，再通过实际版本比较函数检查旧版本会提示更新、新版本不会自我提示。设备须分别能访问GitHub API和资产下载域名。首次安装承载应用内更新功能的版本仍需手动覆盖安装，之后可在应用中下载并交给Android确认；安装结果不明确时保留唯一候选包并提供发布页回退。

## Leaf 工作流维护范围

| 入口 | 行为 |
|---|---|
| `main.yml`：v* 标签／手动运行 | 元数据校验、质量检查、调用 `build.yml` 构建；v* 标签推送时核对产物后创建 Release（rc 标签为预发布），手动运行不创建Release |
| `analyze.yml`：main推送／PR／发布校验调用 | Dart分析、格式与架构检查、脚本测试、Linux宿主的Rust和Flutter测试及覆盖率 |
| `pr_build.yml`：PR | 相关路径变化时构建Android ARM64 Debug作冒烟检查，不上传或发布Debug包，不使用Release密钥 |
| `build.yml`：`main.yml` 调用／手动运行 | 使用固定签名构建一个Android ARM64 Release APK，核对签名证书指纹，生成SHA-256摘要并上传Actions artifact；手动运行不发布 |
| `dependency_review.yml` | 保留依赖漏洞检查，覆盖Android使用的Rust依赖 |

Linux在这里是测试宿主，不生成Linux客户端。已移除Apple/iOS原生检查、Windows PR构建及Windows/macOS/iOS/Linux正式构建入口，以及AltStore、Winget、Fastlane和上游赞助同步工作流。上游平台源码和通用脚本仍保留，便于后续同步；它们不是Leaf的交付目标。Issue检查和手动清理运行记录不涉及应用产物，继续保留。

Android Gradle仅启用`arm64-v8a`，不生成ARM32、x86_64或通用APK；保留ARM64的版本码规则`build × 10 + 2`和原固定包名、证书。构建命令使用`flutter build apk --release --target-platform android-arm64 --split-per-abi`。

云端构建必须配置与现有Leaf安装一致的`ANDROID_KEYSTORE`和`ANDROID_KEY_PROPERTIES`，缺失时直接失败，不能生成临时签名替代。`build.yml` 在上传产物前用 `apksigner` 验签并核对证书指纹，指纹不符、多个签名者或验签失败都会终止发布。
