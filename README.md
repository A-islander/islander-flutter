# 岛民岛 Flutter 客户端

正式入口 `lib/main.dart` 使用已确认的论坛原型视觉，默认连接正式服。

```bash
flutter run -t lib/main.dart
flutter test
flutter build web --target lib/main.dart --output build/forum-web
python3 -m http.server 8083 --bind 0.0.0.0 -d build/forum-web
flutter build apk --release --target lib/main.dart --split-per-abi
```

默认接口为 `https://forum-api.islander.top/` 与 `https://user-api.islander.top/`。测试环境可以通过 `--dart-define=FORUM_API_URL=https://your-forum/` 和 `--dart-define=USER_API_URL=https://your-user/` 覆盖，保留末尾 `/`。

功能包括时间线、板块、SAGE、真实分页、串详情、引用展开与定位、饼干导入与领取、全宽编辑抽屉、颜文字、媒体上传与查看，以及自己的内容删除与恢复。海浪之家本轮未接入。

正式代码在 `lib/features/forum/`；`lib/core/` 提供网络、路由和存储；`lib/shared/widgets/pixel_shore.dart` 是共用海岸动画。设计原型保留在 `lib/prototypes/`，通过 `lib/prototype_main.dart` 独立运行。

测试使用模拟传输层验证接口契约及交互，不向正式服发布测试内容。正式接口不支持全站最新发布排序或全文搜索，因此“本页最新发布”和“筛选本页”仅作用于当前页；输入 `No.编号` 回车可以跳转到真实内容。

Android 当前沿用工程的调试签名配置，release 包可用于安装体验；商店发布前需配置正式签名。

详细记录见 [正式论坛接入](../docs/岛民岛前端重构/flutter-prototype/正式论坛接入.md)。
