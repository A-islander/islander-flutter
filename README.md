# 岛民岛 Flutter 客户端

正式入口 `lib/main.dart` 使用已确认的论坛原型视觉，默认连接正式服。

v0.0.4 新增：[图片保存、PO 与分层动效](docs/specs/media-po-motion.md)。新增平台权限与手感尚待真机验收。

开发规格：[Flutter 三岛接入](docs/specs/multi-forum.md) — v0.0.3 接入三岛浏览、外站独立饼干管理、最近浏览及阅读状态保存；完整进度和待验收项见 spec 第 10 节。

多岛入口位于导航顶部的“当前站点”。岛民岛保留现有写入能力，X / BOG 暂时只读；X 饼干导入会验证受限板块访问，BOG 仅检查格式并标为“未验证”。外站饼干按站点实例独立安全存储，网页端暂不支持导入或发送外站饼干，可打开原站。原生匿名读取已验证，Web 编译成功不代表外站跨域能力已验证。

“最近浏览”可按岛筛选、搜索、删除、清空或关闭记录。每岛、每身份独立保存页码和帖子锚点，默认历史上限 500 条 / 90 天。默认正式站继续使用原有饼干和草稿键，避免不必要的数据重写；自定义岛民岛 endpoint 使用独立命名空间，不能读取正式站身份和草稿。草稿修订历史尚未加入。

当前版本为 `0.0.4+5`，发布标签为 `v0.0.4`，提供正式证书签名的分架构 Android APK。同架构、正式签名的 v0.0.2／v0.0.3 可保留数据覆盖更新。旧 v0.0.1 和本地 debug 包签名不同，不要直接卸载以绕过限制；详见 [发布与更新说明](docs/releases/v0.0.4.md) 和 [CHANGELOG.md](CHANGELOG.md)。

预览中的换行转为空格，标题最多 2 行、正文摘要最多 3 行、最近回复最多 1 行，超出才省略；详情保留原文排版。手机从内容任意位置右滑可跟手打开左栏，桌面 Web 窄屏也支持鼠标／触摸右滑，宽屏侧栏常驻。

```bash
flutter run -t lib/main.dart
flutter test --concurrency=1
flutter build web --target lib/main.dart --output build/forum-web --no-wasm-dry-run
python3 -m http.server 8083 --bind 0.0.0.0 -d build/forum-web
bash scripts/build_android.sh
```

默认接口为 `https://forum-api.islander.top/` 与 `https://user-api.islander.top/`。测试环境可以通过 `--dart-define=FORUM_API_URL=https://your-forum/` 和 `--dart-define=USER_API_URL=https://your-user/` 覆盖，保留末尾 `/`。

功能包括时间线、板块、SAGE、真实分页、串详情、引用展开与定位、饼干导入与领取、全宽编辑抽屉、颜文字、媒体上传与查看，以及自己的内容删除与恢复。海浪之家本轮未接入。

论坛支持双向连续加载：中间页向上回看时加载上一页并保持阅读位置，触底追加下一页；回到第一页后下拉刷新，不再显示顶部提示或预留空白。到底状态与刷新合并为“已经到底了，点击刷新”按钮，保留页码信息。右上角页码抽屉支持跳页，返回列表保留已加载范围与位置。最近五条回复预览不重复显示自身编号，正文引用保留。手机端隐藏“返回列表”入口，使用系统返回。

深浅色自动跟随系统（Web 跟随 `prefers-color-scheme`），帖子、侧栏、抽屉与海岸统一适配，保留海绿色重点色。

Android 页面级预测返回无论从左侧还是右侧触发，都以阅读区的固定中心等比缩放，顶栏、侧栏与海浪保持不动。手势拖动阶段宽高最多缩小 8%（最小为原来的 92%）；中途取消回弹，确认返回后从当前尺寸继续向中心缩到 0 并淡出，不先恢复原尺寸。只处理系统边缘返回事件，不抢占帖子滚动；底部抽屉、媒体缩放、确认框及首页退出仍保持各自逻辑。悬浮按钮独立向下退场、从右侧入场并线性衰减回弹；系统减少动态效果时直接切换。

拖动缩放直接映射系统进度，确认返回使用 200ms 快速收尾，取消回弹约 140ms；不再额外给拖动进度加缓动。普通帖子按行懒加载，仅前插页／直接引用定位页整体测量；海浪直接驱动绘制而非逐帧重建 Widget，并跨页面共享时钟。真机 profile 帧率仍待验证。

帖子与回复详情的引用回复、SAGE、反对 SAGE、本人删除／恢复操作统一放在右下角 `⋯` 菜单，保留计数、已投票状态及删除确认；列表中本人的管理入口也收进菜单。正文中的 `No.编号` 高亮可点击，展开／收起引用，不再额外显示重复的“引用 No.xxx”按钮。

移除饼干、删除串／回复、恢复串／回复、清空草稿及复制饼干均需二次确认。恢复确认显示编号、串／回复类型、内容摘要及可见性变化；复制确认显示备注／ID 和剪贴板泄露风险，不展示饼干原文。取消或系统返回不调用恢复接口、不写入剪贴板；其他操作暂不追加确认弹窗。

“我的内容”的每条串／回复在信息行显示“未删除／已删除”标签，分别采用海绿色和警示色，适配系统深浅色。标签读取接口删除状态，删除／恢复成功刷新列表后同步变化；其他页面维持原有显示。

多饼干管理支持验证导入、去重、备注、切换、复制、退出和本机移除。旧版单饼干首次启动时自动迁移；原生端采用 `flutter_secure_storage`（当前锁定 10.3.1，兼容工程 Android SDK 36），Android 禁止自动备份且关闭存储出错自动重置。Web 端使用当前浏览器本地存储，不提供与原生端相同的密钥保护，也不跨设备同步。请自行备份饼干，清除数据或卸载可能导致丢失。切换失败保留原身份；失效仅标记对应饼干。退出保留已存饼干与草稿，移除则确认后清除该饼干及其本机草稿，不影响服务器身份或帖子。

发串／回复抽屉自动保存本机草稿：标题、正文、引用及已上传附件信息。草稿按饼干独立 ID 和板块／串号隔离，输入停顿 350ms 后保存，关闭编辑器和进入后台时补存。切换板块先保存当前草稿再载入目标板块草稿；关闭后重新打开可继续编辑，发布失败保留，成功清除当前草稿。编辑器中可确认清空草稿；已上传文件不会因此从服务器删除，未完成上传的附件需重选。草稿是本机普通存储，非加密云端备份；系统强制终止前尚未落盘的最后输入仍可能丢失。

编辑器显示其所属饼干；身份改变后禁止继续发布，关闭后保留原身份草稿。发布、上传、SAGE 与删除／恢复请求绑定发起身份，旧身份的迟到鉴权失败不会退出新饼干。

正式代码在 `lib/features/forum/`；`lib/core/` 提供网络、路由和存储；`lib/shared/widgets/pixel_shore.dart` 是共用海岸动画。设计原型保留在 `lib/prototypes/`，通过 `lib/prototype_main.dart` 独立运行。

测试使用模拟传输层验证接口契约及交互，不向正式服发布测试内容。正式接口不支持全站最新发布排序或全文搜索，因此“页内最新发布”仅在各页内部排序，“筛选已加载内容”仅搜索已读取的内容；输入 `No.编号` 回车可以跳转到真实内容。

### Android 签名

Release 使用正式 `islander-release` 密钥；debug 和 profile 使用保留原证书身份的 debug 密钥。两者的密钥库和密码配置均放在 Flutter 仓库之外，默认目录为同级 `../.signing/android/`：

- `key.properties`：正式签名配置，默认引用 `islander-release.p12`。
- `debug.properties`：调试签名配置，默认引用 `islander-debug.keystore`。

另一台机器或 CI 可用环境变量 `ISLANDER_SIGNING_DIR` 指定外部目录；直接调用 Gradle 时也可用 `-PislanderSigningDir=/absolute/private/path`，后者优先。配置字段为 `storeFile`、`storeType`、`keyAlias`、`storePassword`、`keyPassword`；`storeFile` 支持绝对路径或相对签名目录的路径。密钥库和配置不得位于 Flutter 仓库内，也不要将密码写入命令行或提交 Git。

对应构建缺少配置、密钥无效或过期时会失败，不会回退签名或自动生成 debug 密钥；release 还会拒绝标准 Android debug 证书。仅构建 debug 不需要正式密钥。可在 `android/` 中运行 `./gradlew :app:verifyReleaseSigning :app:verifyDebugSigning :app:signingReport` 检查配置（本机需使用 Java 17）。

现有 `v0.0.1` APK 仍是旧 debug 签名，配置修改不会改变已有产物。`v0.0.2` 正式签名 APK 不能直接覆盖旧 debug 签名安装，本次没有提供签名轮换链或自动迁移工具；请先备份饼干和草稿并安排迁移，不要直接卸载。正式密钥及密码配置需另做独立加密备份，以后持续使用同一把正式密钥。

通用安装包位于 `build/app/outputs/flutter-apk/app-release.apk`（Android API 24 及以上）；也可追加 `--split-per-abi` 分架构打包。构建目录、Gradle/Kotlin 缓存及原生编译中间文件已加入 Git 忽略。Gradle 使用 1536 MB 堆内存与单 worker，内存有限时请顺序运行测试和打包。

### 本地 debug 体验包与产物命名

当前开发验证优先使用 debug 模式（不是 release 模式套 debug 签名），不修改上面的正式签名配置，也不自动发布 GitHub Release：

```bash
bash scripts/build_android.sh                # 默认 debug，输出三个分架构 APK
bash scripts/build_android.sh --universal    # 单独输出 debug 通用包
bash scripts/build_android.sh --release     # 正式证书签名的三个分架构包
```

脚本读取 `pubspec.yaml` 的版本与构建号，输出 `build/distributions/v<版本>-b<构建号>/<debug或release>/<split或universal>/`，附带 `SHA256SUMS.txt`。文件名采用 `islander-android-v<版本>-b<构建号>-<架构>-<模式>.apk`，例如 `islander-android-v0.0.2-b3-arm64-v8a-release.apk`。架构为 `arm64-v8a`、`armeabi-v7a`、`x86_64` 或 `universal`；在产物目录运行 `sha256sum -c SHA256SUMS.txt` 可验证完整性。

可通过 `FLUTTER_BIN` 指定 Flutter 可执行文件；本机使用 Java 17。debug 包使用保留下来的 debug 证书，可在版本码不降低时覆盖同签名调试版，不能覆盖正式签名安装。debug 包较大且包含调试能力，只用于开发体验，不作为正式发行包。脚本不提交 Git、不上传密钥或 APK。

注意：文件名 `b3` 表示 pubspec 基础构建号。Flutter 默认给分架构包的 Android `versionCode` 加偏移：当前 ARMv7 为 `1003`、ARM64 为 `2003`、x86_64 为 `4003`；通用包则为 `3`，本次 Release 不提供通用包。安装分架构包后，不要直接换装基础版本码更低的通用包；后续升级应持续使用同架构包，或在计划迁移时明确提高内部版本码。不要为绕过降级限制直接卸载、丢失本机饼干与草稿。

发行说明见 [v0.0.2](docs/releases/v0.0.2.md)。完整设计过程记录保留在主工作区 `docs/岛民岛前端重构/flutter-prototype/`，不包含在独立 Flutter 仓库中。
