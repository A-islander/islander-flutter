# Flutter X／BOG 发串与回串

日期：2026-09-08。开发分支 `feat/external-posting`，基于已发布 `v0.0.4`／`53b7810`。本功能未包含在该 Release，不修改其标签或附件。

## 范围与参考

参照同工作区 `islander-cli/internal/forum/replies.go`、`docs/specs/external-replies.md` 与 `external-threads.md`，移植 TUI 的协议契约，不调用 Go 子进程或新增代理。现有 Flutter 布局、海浪、分层转场和编辑抽屉保持不变。

- 原生端 X／BOG 新串、文字回复、引用回复及图片附件；Web 仍不导入或发送外站饼干，也不开放外站写入。
- 发新串与回复使用独立能力 `publish`／`reply`；外站我的内容、SAGE、反对 SAGE、删除恢复、领取饼干仍关闭。
- 导航时间线可以打开编辑器，但必须在抽屉中选择具体板块后发布，时间线本身不作服务端目标。
- 引用 X 使用 `>>No.ID`，BOG 使用 `>>Po.ID`；引用楼层不改变正在阅读的回复主串。
- 抽屉明确显示岛、饼干备注；外站提交前预览站点、目标、标题、正文和图片数，确认前不请求发帖表单、不上传、不提交。

## 协议

X 默认 API `https://api.nmb.best/api/` 仅显式映射到网页 `https://www.nmbxd1.com/`；自定义 endpoint 只在自身 origin 工作，不回退正式域名。板块编号通过 API 映射名称，读取 `/f/名称`；回复读取 `/t/主串号`。解析唯一 POST 表单，核对 `fid`／`resto`、动态 `__hash__`、可用正文与图片输入、maxlength 和同源 action。提交 `/Home/Forum/doPostThread.html` 或 `/Home/Forum/doReplyThread.html`，multipart 的 `content`、可选 `title`、当前水印选项和最多一张 `image`。不发送名称、email/SAGE 或管理员字段。

BOG 用原始字符串板块 key 选板，读取 `/f/名称/1`，从该板块 `.compose-title` 匹配的表单获取真正正整数 `forum`；Flutter 的数字 0 和 CLI 的导航哈希均不能当发布编号。回复读取 `/t/主串号/1` 并核对 `res`。图片 POST `/post/upload`，仅 `code=200` 且合法 `pic` 视为上传成功；最终 URL 编码提交 `/post/post`，字段 `comment`、`forum` 或 `res`、可选可用标题、重复的 `img[]`。仅 `code=1` 视为发布成功，不能混用上传／读取成功码。

每次提交独立内存会话，保留有效同源 Session Cookie，遵循路径、Secure 和过期条件；不允许返回 Cookie 静默替换选中身份。GET／POST 均禁止自动跳转，action 不能包含凭证、查询或 fragment。只携带当前外站身份，不使用岛民岛 Dio／Authorization，不回显原始错误响应或饼干。

正文上限 8192 UTF-8 字节、标题 128 字节，另遵守表单 maxlength；BOG 标题最多 50 个 UTF-16 单元。原站 `#other` 按钮会启用 `.hid-input` 中的可选标题，Flutter 填写标题等同显式启用该选项；其他禁用输入及禁用 fieldset 不强行提交。图片只允许 JPEG／PNG／GIF／BMP，单张 20 MB，客户端 X 一张、BOG 九张，服务端权限与实际限制仍优先。

## 草稿与生命周期

- 编辑器捕获打开时的 repository、站点、饼干 ID 和 token，不依赖弹层是否继承页面 ProviderScope。任一身份变化禁止继续提交，旧 repository 销毁取消未完成请求。
- 岛民岛旧草稿键不变；外站按 `instanceKey + cookieId + boardKey／threadId` 保存，不同 BOG 板块即使数字编号均为 0 也不混稿。
- 附件选择时只验证本机文件。X 随最终请求发送；BOG 确认后逐张上传，每张成功立即保存回执，再发送帖子。失败或关闭恢复时复用回执，不重复上传已记录图片。
- 本机待发送附件保存路径与名称，文件仍由系统选择器管理；系统清理临时图片后提示重新选择，不宣称图片永久保存。草稿不存图片字节或饼干明文。
- 成功清除当前草稿，失败保留；移除外站饼干需确认并清除其本机草稿，已上传图片和服务器内容不删除。

## 失败语义

验证码引导打开原站，不内置挑战绕过。权限／饼干问题、频率、锁串、重复内容、图片限制使用固定中文提示。POST 超时、连接中断、重定向或无法识别的结果标为 `unknown_result`，保留草稿并要求先核对原站；不自动重试、不扫描全串猜测成功。BOG 导入仍仅校验 Cookie 格式，不冒称已验证发言权限。

## 验证

本地模拟 HTTP 测试覆盖动态 hash／会话、multipart、真实板块映射、重复与错误表单、验证码、标题禁用、Cookie 隔离、超时／重定向未知结果、原站错误脱敏和无重试。Widget 测试覆盖抽屉站点绑定、引用主串、确认前零写入、身份切换拦截、BOG 上传回执恢复、按字符串板块隔离及移除饼干清稿。

`external_form_smoke_test.dart` 单独显式启用，只向四个公开页面 GET 并运行同一解析器；无身份、无上传、无发帖，不打印动态表单字段。真实用户的发言权限、站点最终接受结果及手机体验仍待验收。

本轮结果：完整自动化回归 175 项通过，2 项真实联网 smoke 默认跳过；另行启用四个公开表单的只读检查通过（包含可选标题）。静态检查无问题，最新源码 Android ARM64 debug 与 Web 编译通过。未安装到手机、未使用真实饼干上传或发帖；本分支不合并或追加 Release，v0.0.4 的三项更新已独立发布。

协议来源：[X 新串表单](https://www.nmbxd1.com/f/综合版1)、[X 回复表单](https://www.nmbxd1.com/t/50000001)、[BOG 新串表单](https://bog.ac/f/综合版/1)、[BOG 回复表单](https://bog.ac/t/1526630/1)、[BOG 官方提交脚本](https://bog.ac/static/js/script.js?20230911:2)。这些是网页协议，不是接口长期稳定性的保证。
