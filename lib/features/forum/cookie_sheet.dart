import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
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

  Future<void> _login({bool register = false}) async {
    if (_busy) return;
    if (!register && _token.text.trim().isEmpty) {
      setState(() => _error = '请粘贴饼干');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(forumRepositoryProvider);
      final token = register ? await repo.register() : _token.text.trim();
      final user = await repo.verifyToken(token);
      if (!mounted) return;
      await ref
          .read(authProvider.notifier)
          .setToken(
            token,
            name: '${user['name'] ?? ''}',
            userId: user['id'] as int,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return SheetSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的饼干',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                tooltip: '关闭',
                icon: Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '饼干是你在岛上的身份。妥善保存，不要分享给其他人。',
            style: TextStyle(
              color: ForumPalette.of(context).muted,
              height: 1.6,
            ),
          ),
          SizedBox(height: 24),
          if (auth.isLoggedIn) ...[
            Text(
              auth.name.isEmpty ? '岛民 #${auth.userId}' : auth.name,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'ID ${auth.userId}',
              style: TextStyle(color: ForumPalette.of(context).muted),
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: auth.token),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('饼干已复制')));
                          }
                        },
                  child: Text('复制饼干'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) Navigator.pop(context, true);
                        },
                  child: Text('退出当前饼干'),
                ),
              ],
            ),
            SizedBox(height: 24),
          ],
          TextField(
            key: Key('cookie-token'),
            controller: _token,
            obscureText: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: auth.isLoggedIn ? '切换到另一块饼干' : '粘贴已有饼干',
            ),
          ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: Key('cookie-login'),
                onPressed: _busy ? null : _login,
                child: Text(_busy ? '验证中…' : '导入饼干'),
              ),
              if (!auth.isLoggedIn)
                OutlinedButton(
                  onPressed: _busy ? null : () => _login(register: true),
                  child: Text('领取饼干'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
