import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../forum/forum_theme.dart';
import '../forum/forum_repository.dart';
import '../forum/application/forum_state_store.dart';
import 'cache_providers.dart';
import 'cached_post.dart';
import 'cache_backup.dart';
import 'cache_widgets.dart';

String _browseTime(int value) {
  final time = DateTime.fromMicrosecondsSinceEpoch(value);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

class LocalSearchScreen extends ConsumerStatefulWidget {
  const LocalSearchScreen({super.key, this.pinnedOnly = false});
  final bool pinnedOnly;
  @override
  ConsumerState<LocalSearchScreen> createState() => _LocalSearchScreenState();
}

class _LocalSearchScreenState extends ConsumerState<LocalSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String? _site, _error;
  bool get _pinned => widget.pinnedOnly;
  bool _loading = true, _busy = false, _more = false;
  bool _selecting = false;
  int _ticket = 0;
  List<CachedPost> _rows = [];
  final Set<int> _selected = {};
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _ticket++;
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (!mounted) return;
    final ticket = ++_ticket;
    final scopes = ref.read(cacheScopesProvider);
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _rows = [];
        _selected.clear();
        _selecting = false;
      }
    });
    try {
      final store = ref.read(cacheStoreProvider);
      final history = ref.read(forumStateStoreProvider);
      for (final site in ForumSite.all) {
        final identity = scopes[site.instanceKey];
        if (identity == null) continue;
        final scope = history.scopeKey(site, identity);
        await store.migrateBrowseHistory(
          site,
          identity,
          history.history(scope),
        );
      }
      final rows = await ref
          .read(cacheStoreProvider)
          .search(
            scopes,
            query: _query.text,
            site: _site,
            pinnedOnly: _pinned,
            offset: append ? _rows.length : 0,
          );
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _rows = [if (append) ..._rows, ...rows];
        _more = rows.length == 80;
        _loading = false;
      });
    } catch (_) {
      if (mounted && ticket == _ticket) {
        setState(() {
          _loading = false;
          _error = '浏览搜索暂时不可用，请重试或检查缓存配置';
        });
      }
    }
  }

  Future<void> _action(String action) async {
    final selected = _rows.where((r) => _selected.contains(r.rowId)).toList();
    if (selected.isEmpty) return;
    final store = ref.read(cacheStoreProvider);
    if (action == 'delete' &&
        !await confirmCacheAction(
          context,
          '删除 ${selected.length} 条本地缓存？',
          '删除选中的本机正文和对应浏览记录，不删除服务器帖子、阅读位置或饼干。${selected.any((r) => r.pinned) ? '本次包含永久保留内容。' : ''}',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      if (action == 'export') {
        final message = await saveCacheBackup(selected);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      } else if (action == 'delete') {
        await store.remove(
          ids: selected.map((r) => r.rowId).toList(),
          includePinned: true,
        );
      } else {
        await store.pin(selected.map((r) => r.rowId).toList(), action == 'pin');
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败；请检查存储空间或分批导出（单份最多 32 MB）');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(CachedPost row) async {
    try {
      final scopes = ref.read(cacheScopesProvider);
      if (scopes[row.site.instanceKey] != row.identity) return;
      await ref.read(cacheStoreProvider).touch([row.rowId]);
      if (!mounted ||
          ref.read(cacheScopesProvider)[row.site.instanceKey] != row.identity) {
        return;
      }
      await context.push(row.route);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '这条内容暂时无法打开，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cacheScopesProvider, (previous, next) {
      _ticket++;
      _debounce?.cancel();
      _load();
    });
    final palette = ForumPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '已选 ${_selected.length} 条' : '浏览搜索'),
        actions: [
          if (_selecting)
            IconButton(
              tooltip: '取消选择',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _selecting = false;
                      _selected.clear();
                    }),
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: '缓存配置',
            onPressed: () async {
              await context.push('/settings/cache');
              if (mounted) await _load();
            },
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ColoredBox(
              color: palette.surface,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pinned ? '永久保留的内容' : '浏览与加载的内容',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '全部缓存按时间倒序 · 搜索已加载的主贴与回复',
                          style: TextStyle(fontSize: 12, color: palette.muted),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('local-search-query'),
                          controller: _query,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            hintText: '关键字/no号',
                            prefixIcon: Icon(Icons.search),
                            counterText: '',
                          ),
                          onSubmitted: (_) => _load(),
                          onChanged: (_) {
                            _debounce?.cancel();
                            _debounce = Timer(
                              const Duration(milliseconds: 250),
                              _load,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            DropdownButton<String>(
                              value: _site ?? 'all',
                              underline: const SizedBox.shrink(),
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('全部岛'),
                                ),
                                ...ForumSite.all.map(
                                  (s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(s.name),
                                  ),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) {
                                      setState(
                                        () => _site = v == 'all' ? null : v,
                                      );
                                      _load();
                                    },
                            ),
                            const Spacer(),
                            if (_rows.isNotEmpty)
                              TextButton(
                                key: const Key('browse-multiselect'),
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _selecting = !_selecting;
                                        _selected.clear();
                                      }),
                                child: Text(_selecting ? '完成' : '多选'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: () async {
                              try {
                                await ref.read(cacheStoreProvider).retry();
                              } catch (_) {}
                              if (mounted) await _load();
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _rows.isEmpty && !_loading && _error == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.manage_search,
                                    size: 48,
                                    color: palette.accent,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _query.text.trim().isEmpty && !_pinned
                                        ? '还没有缓存内容'
                                        : '没有找到匹配内容',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '成功加载的主贴和回复会保存在这里。\n只显示各岛当前饼干身份下的缓存。',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: palette.muted),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            key: const Key('local-search-results'),
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _rows.length + 1,
                            separatorBuilder: (_, _) =>
                                const Divider(indent: 20, endIndent: 20),
                            itemBuilder: (context, index) {
                              if (index == _rows.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _more
                                      ? TextButton(
                                          onPressed: _loading
                                              ? null
                                              : () => _load(append: true),
                                          child: const Text('加载更多本地结果'),
                                        )
                                      : Text(
                                          _rows.isEmpty
                                              ? ''
                                              : '已展示 ${_rows.length} 条 · 时间倒序',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: palette.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                );
                              }
                              final r = _rows[index];
                              final p = r.post;
                              return ListTile(
                                key: ValueKey(
                                  'cache-result-${r.site.id}-${p.id}',
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                selected: _selected.contains(r.rowId),
                                selectedTileColor: palette.soft,
                                leading: !_selecting
                                    ? null
                                    : Checkbox(
                                        value: _selected.contains(r.rowId),
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(() {
                                                v == true
                                                    ? _selected.add(r.rowId)
                                                    : _selected.remove(r.rowId);
                                              }),
                                      ),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.site.name} · No.${p.id}${r.threadId != null && r.threadId != p.id ? ' · 回复 No.${r.threadId}' : ''}',
                                      style: TextStyle(
                                        color: palette.accent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${r.browsedAt != null ? '浏览于' : '加载于'} ${_browseTime(r.displayTime)}',
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    if (p.title.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 7),
                                        child: Text(
                                          p.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Text(
                                    p.value.replaceAll(RegExp(r'\s+'), ' '),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.ink,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                trailing: r.pinned
                                    ? Icon(
                                        Icons.bookmark,
                                        color: palette.accent,
                                        size: 20,
                                      )
                                    : null,
                                onLongPress: _busy
                                    ? null
                                    : () => setState(() {
                                        _selecting = true;
                                        _selected.add(r.rowId);
                                      }),
                                onTap: _busy
                                    ? null
                                    : () => !_selecting
                                          ? _open(r)
                                          : setState(() {
                                              _selected.contains(r.rowId)
                                                  ? _selected.remove(r.rowId)
                                                  : _selected.add(r.rowId);
                                            }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : () => _action('pin'),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('永久保留'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _action('unpin'),
                      child: const Text('取消保留'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _action('export'),
                      child: const Text('导出'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _action('delete'),
                      child: const Text('删除本地缓存'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
