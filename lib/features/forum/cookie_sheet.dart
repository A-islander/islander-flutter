import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../core/storage/cookie_identity.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

class CookieSheet extends ConsumerStatefulWidget {
  const CookieSheet({super.key});
  @override
  ConsumerState<CookieSheet> createState() => _CookieSheetState();
}

class _CookieSheetState extends ConsumerState<CookieSheet> {
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ForumFailure ? error.message : '操作未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(String token) async {
    final repo = ref.read(forumRepositoryProvider);
    final notifier = ref.read(authProvider.notifier);
    try {
      final user = await repo.verifyToken(token);
      if (!mounted) return;
      await notifier.setToken(
        token,
        name: '${user['name'] ?? ''}',
        userId: user['id'] as int,
      );
      if (mounted) Navigator.pop(context, true);
    } on ForumFailure catch (error) {
      if (error.message.startsWith('饼干无效')) await notifier.markInvalid(token);
      rethrow;
    }
  }

  Future<void> _login({bool register = false}) => _run(() async {
    final token = register
        ? await ref.read(forumRepositoryProvider).register()
        : _token.text.trim();
    if (token.isEmpty) throw const ForumFailure('请粘贴饼干');
    await _activate(token);
  });

  Future<void> _manage(CookieIdentity cookie, String action) => _run(() async {
    final notifier = ref.read(authProvider.notifier);
    if (action == 'copy') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('复制饼干到剪贴板？'),
          content: Text(
            '将复制「${cookie.displayName}」（ID ${cookie.userId}）的完整饼干。\n\n'
            '饼干是你的身份凭证，泄露后他人可能以你的身份操作。剪贴板可能被其他应用读取或同步，请仅用于自己的备份，不要分享或粘贴到不可信的位置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认复制'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (!ref
          .read(authProvider)
          .cookies
          .any(
            (entry) => entry.id == cookie.id && entry.token == cookie.token,
          )) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: cookie.token));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('饼干已复制，请勿分享给他人')));
      }
    } else if (action == 'rename') {
      final label = await showDialog<String>(
        context: context,
        builder: (context) => _CookieLabelDialog(label: cookie.label),
      );
      if (label != null) await notifier.rename(cookie.id, label);
    } else if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('从本机移除饼干？'),
          content: Text(
            '将移除「${cookie.displayName}」及其本机草稿，不会删除服务器上的身份或帖子。请先确认已备份饼干。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除'),
            ),
          ],
        ),
      );
      if (confirmed == true) await notifier.remove(cookie.id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final palette = ForumPalette.of(context);
    final unavailable = _busy || auth.error != null;
    return PopScope(
      canPop: !_busy,
      child: SheetSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '我的饼干',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              kIsWeb
                  ? '仅保存在当前浏览器，清除网站数据会丢失。饼干是你的身份，请勿分享。'
                  : '饼干存于本机安全存储。请自行备份，卸载应用可能丢失。',
              style: TextStyle(color: palette.muted, height: 1.6),
            ),
            const SizedBox(height: 20),
            if (auth.error != null) ...[
              Text(
                auth.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref.read(authProvider.notifier).retryStorage(),
                      ),
                child: const Text('重试读取'),
              ),
            ],
            if (auth.cookies.isEmpty && auth.error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('还没有保存的饼干', style: TextStyle(color: palette.muted)),
              ),
            for (final cookie in auth.cookies)
              Container(
                key: ValueKey('cookie-row-${cookie.id}'),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.line)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      cookie.id == auth.activeId
                          ? Icons.check_circle
                          : Icons.account_circle_outlined,
                      color: cookie.id == auth.activeId
                          ? palette.accent
                          : palette.muted,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cookie.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID ${cookie.userId} · ${cookie.invalid
                                ? '已失效，请验证'
                                : cookie.id == auth.activeId
                                ? '正在使用'
                                : '已保存'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (cookie.id != auth.activeId)
                      TextButton(
                        key: ValueKey('cookie-switch-${cookie.id}'),
                        onPressed: unavailable
                            ? null
                            : () => _run(() => _activate(cookie.token)),
                        child: Text(cookie.invalid ? '验证' : '使用'),
                      ),
                    PopupMenuButton<String>(
                      key: ValueKey('cookie-menu-${cookie.id}'),
                      enabled: !unavailable,
                      tooltip: '管理 ${cookie.displayName}',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (action) => _manage(cookie, action),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('修改备注')),
                        PopupMenuItem(value: 'copy', child: Text('复制饼干')),
                        PopupMenuItem(value: 'remove', child: Text('从本机移除')),
                      ],
                    ),
                  ],
                ),
              ),
            if (auth.isLoggedIn)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('cookie-logout'),
                  onPressed: unavailable
                      ? null
                      : () => _run(
                          () => ref.read(authProvider.notifier).logout(),
                        ),
                  child: const Text('退出当前饼干（保留存储）'),
                ),
              ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('cookie-token'),
              controller: _token,
              obscureText: true,
              enabled: !unavailable,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '导入另一块饼干',
                hintText: '粘贴饼干，验证后保存并使用',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('cookie-login'),
                  onPressed: unavailable ? null : _login,
                  child: Text(_busy ? '处理中…' : '导入饼干'),
                ),
                if (!auth.isLoggedIn)
                  OutlinedButton(
                    onPressed: unavailable
                        ? null
                        : () => _login(register: true),
                    child: const Text('领取饼干'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CookieLabelDialog extends StatefulWidget {
  const _CookieLabelDialog({required this.label});
  final String label;
  @override
  State<_CookieLabelDialog> createState() => _CookieLabelDialogState();
}

class _CookieLabelDialogState extends State<_CookieLabelDialog> {
  late final _controller = TextEditingController(text: widget.label);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('备注饼干'),
    content: TextField(
      key: const Key('cookie-label'),
      controller: _controller,
      autofocus: true,
      maxLength: 30,
      decoration: const InputDecoration(hintText: '仅在本机显示'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}
