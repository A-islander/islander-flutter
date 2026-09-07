import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import 'application/external_identity.dart';
import 'application/forum_state_store.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

class ForumHistorySheet extends ConsumerStatefulWidget {
  const ForumHistorySheet({super.key, required this.site});
  final ForumSite site;
  @override
  ConsumerState<ForumHistorySheet> createState() => _ForumHistorySheetState();
}

class _ForumHistorySheetState extends ConsumerState<ForumHistorySheet> {
  late ForumSite _site = widget.site;
  String _query = '';
  String? _error;
  bool _busy = false;
  Future<void> _change(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (_) {
      _error = '历史保存失败，请重试；原数据未被覆盖';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('只删除本机浏览记录和对应阅读位置，不删除帖子、饼干或草稿。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ==
      true;
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(forumStateStoreProvider);
    final identity = _site.isIslander
        ? ref.watch(authProvider).activeId
        : ref.watch(externalIdentityProvider(_site)).asData?.value.activeId;
    final scope = store.scopeKey(_site, identity ?? 'anonymous');
    final scopes = {scope, store.scopeKey(_site, 'anonymous')};
    final rows = [
      for (final key in scopes)
        ...store.history(key).map((r) => {...r, 'scope': key}),
    ]..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
    final filtered = rows.where(
      (r) => '${r['id']} ${r['title']}'.toLowerCase().contains(
        _query.toLowerCase(),
      ),
    );
    return SheetSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '最近浏览',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _site.id,
            decoration: const InputDecoration(labelText: '站点'),
            items: ForumSite.all
                .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                .toList(),
            onChanged: _busy
                ? null
                : (id) {
                    if (id != null) setState(() => _site = ForumSite.byId(id));
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: '搜索标题或串号',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('记录当前身份的浏览历史'),
            subtitle: const Text('最多 500 条，保留 90 天；预览不计入历史'),
            value: store.recording(scope),
            onChanged: _busy
                ? null
                : (v) => _change(() => store.setRecording(scope, v)),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('清空当前岛可见历史？') && mounted) {
                          await _change(() async {
                            for (final key in scopes) {
                              await store.clear(key);
                            }
                          });
                        }
                      },
                child: const Text('清空当前岛'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('清空所有岛、所有身份的历史？') && mounted) {
                          await _change(store.clearAll);
                        }
                      },
                child: const Text('清空全部'),
              ),
            ],
          ),
          if (_error != null || store.error != null)
            Text(
              _error ?? store.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有匹配的浏览记录'),
            ),
          for (final row in filtered)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${row['title']}'.isEmpty
                    ? 'No.${row['id']}'
                    : '${row['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${_site.name} · No.${row['id']}'),
              onTap: () => Navigator.pop(context, row['route']),
              trailing: IconButton(
                tooltip: '删除记录',
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('删除 No.${row['id']} 的浏览记录？') &&
                            mounted) {
                          await _change(
                            () => store.clear(
                              row['scope'] as String,
                              id: row['id'] as int,
                            ),
                          );
                        }
                      },
              ),
            ),
        ],
      ),
    );
  }
}
