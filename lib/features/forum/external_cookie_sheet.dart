import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'application/external_identity.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

class ExternalCookieSheet extends ConsumerStatefulWidget {
  const ExternalCookieSheet({super.key, required this.site});
  final ForumSite site;
  @override
  ConsumerState<ExternalCookieSheet> createState() =>
      _ExternalCookieSheetState();
}

class _ExternalCookieSheetState extends ConsumerState<ExternalCookieSheet> {
  final _token = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ForumFailure ? e.message : '保存失败，原身份未切换');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(externalIdentityProvider(widget.site));
    final notifier = ref.read(externalIdentityProvider(widget.site).notifier);
    return SheetSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.site.name} · 饼干',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.site.id == 'bog'
                ? 'BOG 饼干仅检查格式，保存后仍为“未验证”。'
                : 'X 岛通过只读访问受限板块验证饼干；保留 userhash 原有编码。',
          ),
          const SizedBox(height: 8),
          const Text('饼干只发送给当前岛，不与岛民岛身份共用；当前阶段仅支持浏览。'),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('网页版暂不导入外站饼干：浏览器的 Cookie 与跨域限制需单独验证，请打开原站。'),
            ),
          value.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton(
              onPressed: notifier.reload,
              child: const Text('饼干存储读取失败，点击重试（不覆盖原数据）'),
            ),
            data: (auth) => Column(
              children: [
                ListTile(
                  title: const Text('匿名浏览'),
                  leading: Icon(
                    auth.activeId == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: _busy
                      ? null
                      : () => _run(() => notifier.activate(null)),
                ),
                for (final cookie in auth.cookies)
                  ListTile(
                    title: Text(cookie.displayName),
                    subtitle: Text(
                      widget.site.id == 'bog' ? '未验证' : '导入时已验证访问',
                    ),
                    leading: Icon(
                      auth.activeId == cookie.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: _busy
                        ? null
                        : () => _run(() => notifier.activate(cookie.id)),
                    trailing: IconButton(
                      tooltip: '移除饼干',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('移除 ${cookie.displayName}？'),
                                  content: Text(
                                    '仅从本机移除 ${widget.site.name} 的这份饼干及其本机草稿，不删除服务器账号、帖子或已上传图片。请确认已备份。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('移除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await _run(() => notifier.remove(cookie.id));
                              }
                            },
                    ),
                  ),
              ],
            ),
          ),
          if (!kIsWeb && value.hasValue) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('external-cookie-input'),
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.site.id == 'x'
                    ? 'userhash 值'
                    : 'bog_master=…; bog_sel=…',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await notifier.importCookie(_token.text, _label.text);
                      _token.clear();
                      _label.clear();
                    }),
              child: Text(
                _busy
                    ? '处理中…'
                    : widget.site.id == 'x'
                    ? '验证并保存'
                    : '保存（未验证）',
              ),
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(widget.site.webUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开原站'),
          ),
        ],
      ),
    );
  }
}
