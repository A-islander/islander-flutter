# 岛民岛 Flutter 客户端

正式入口 `lib/main.dart` 使用已确认的论坛原型视觉，默认连接正式服。

```bash
flutter run -t lib/main.dart
flutter test --concurrency=1
flutter build web --target lib/main.dart --output build/forum-web --no-wasm-dry-run
python3 -m http.server 8083 --bind 0.0.0.0 -d build/forum-web
flutter build apk --release --target lib/main.dart
```

默认接口为 `https://forum-api.islander.top/` 与 `https://user-api.islander.top/`。测试环境可以通过 `--dart-define=FORUM_API_URL=https://your-forum/` 和 `--dart-define=USER_API_URL=https://your-user/` 覆盖，保留末尾 `/`。

功能包括时间线、板块、SAGE、真实分页、串详情、引用展开与定位、饼干导入与领取、全宽编辑抽屉、颜文字、媒体上传与查看，以及自己的内容删除与恢复。海浪之家本轮未接入。

论坛支持双向连续加载：中间页向上回看时加载上一页并保持阅读位置，触底追加下一页；回到第一页后下拉刷新，底部“已经到底了”也提供刷新按钮。右上角页码抽屉支持跳页，返回列表保留已加载范围与位置。最近五条回复预览不重复显示自身编号，正文引用保留。手机端隐藏“返回列表”入口，使用系统返回。

深浅色自动跟随系统（Web 跟随 `prefers-color-scheme`），帖子、侧栏、抽屉与海岸统一适配，保留海绿色重点色。

正式代码在 `lib/features/forum/`；`lib/core/` 提供网络、路由和存储；`lib/shared/widgets/pixel_shore.dart` 是共用海岸动画。设计原型保留在 `lib/prototypes/`，通过 `lib/prototype_main.dart` 独立运行。

测试使用模拟传输层验证接口契约及交互，不向正式服发布测试内容。正式接口不支持全站最新发布排序或全文搜索，因此“页内最新发布”仅在各页内部排序，“筛选已加载内容”仅搜索已读取的内容；输入 `No.编号` 回车可以跳转到真实内容。

Android 当前沿用工程的调试签名配置，release 包可用于安装体验；商店发布前需配置正式签名。

通用安装包位于 `build/app/outputs/flutter-apk/app-release.apk`（Android API 24 及以上）；也可追加 `--split-per-abi` 分架构打包。构建目录、Gradle/Kotlin 缓存及原生编译中间文件已加入 Git 忽略。Gradle 使用 1536 MB 堆内存与单 worker，内存有限时请顺序运行测试和打包。

详细记录见 [正式论坛接入](../docs/岛民岛前端重构/flutter-prototype/正式论坛接入.md)。
