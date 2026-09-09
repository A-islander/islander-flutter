import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../forum/domain/forum_site.dart';
import '../forum/forum_theme.dart';
import 'cache_providers.dart';
import 'cache_store.dart';
import 'cache_widgets.dart';
import 'cache_backup.dart';

class LocalSettingsScreen extends StatelessWidget {
  const LocalSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('缓存配置'),
              subtitle: const Text('浏览搜索、容量、清理与备份'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/cache'),
            ),
          ],
        ),
      ),
    ),
  );
}

class CacheSettingsScreen extends ConsumerStatefulWidget {
  const CacheSettingsScreen({super.key});
  @override
  ConsumerState<CacheSettingsScreen> createState() =>
      _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends ConsumerState<CacheSettingsScreen> {
  CacheStats? _stats;
  bool _busy = true;
  String? _error, _site;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => _work(() async {}));
  }

  Future<void> _work(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final stats = await ref.read(cacheStoreProvider).stats();
      if (mounted) setState(() => _stats = stats);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '操作失败，请检查存储空间、备份格式后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capacity() async {
    final store = ref.read(cacheStoreProvider);
    final field = TextEditingController(
      text: '${store.limitBytes ~/ 1024 ~/ 1024}',
    );
    final dialog = DialogRoute<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存容量上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: field,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '1–2048 MB'),
            ),
            const SizedBox(height: 12),
            const Text('降低上限会立即按 LRU 清理普通缓存；永久保留内容不会被自动删除。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(field.text);
              if (n != null && n >= 1 && n <= 2048) Navigator.pop(context, n);
            },
            child: const Text('保存并应用'),
          ),
        ],
      ),
    );
    final value = await Navigator.of(context).push(dialog);
    await dialog.completed;
    field.dispose();
    if (value != null && mounted) {
      await _work(() => store.configure(bytes: value * 1024 * 1024));
    }
  }

  Future<void> _clear() async {
    var includePinned = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            '清理${_site == null ? '全部岛' : ForumSite.byId(_site!).name}缓存？',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('清理所选岛所有饼干身份下的本机正文、浏览记录及搜索索引，不删除服务器帖子、阅读位置、饼干或草稿。'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时删除永久保留内容'),
                value: includePinned,
                onChanged: (v) => setDialog(() => includePinned = v == true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认清理'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _work(
        () => ref
            .read(cacheStoreProvider)
            .remove(site: _site, includePinned: includePinned),
      );
    }
  }

  Future<void> _export(bool pinnedOnly) async => _work(() async {
    final store = ref.read(cacheStoreProvider);
    final scopes = ref.read(cacheScopesProvider);
    final rows = await store.exportRows(
      scopes,
      pinnedOnly: pinnedOnly,
      site: _site,
    );
    if (rows.length > 100000) throw const FormatException('内容过多，请到浏览搜索分批导出');
    final message = await saveCacheBackup(rows);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  });
  Future<void> _import() async => _work(() async {
    final rows = await pickCacheBackup();
    if (rows == null || !mounted) return;
    final scopes = ref.read(cacheScopesProvider);
    if (!await confirmCacheAction(
          context,
          '导入 ${rows.length} 条缓存？',
          '导入到各岛当前饼干身份下；同 ID 原文不覆盖，普通内容受容量限制。备份不包含饼干或草稿。',
        ) ||
        !mounted) {
      return;
    }
    if (!mapEquals(scopes, ref.read(cacheScopesProvider))) {
      throw const FormatException('饼干已切换，请重新导入');
    }
    final count = await ref.read(cacheStoreProvider).importRows(rows, scopes);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('新增 $count 条，重复记录已跳过；普通缓存仍受容量限制')));
    }
  });
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(cacheStoreProvider);
    final stats = _stats;
    final palette = ForumPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('缓存配置')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _work(ref.read(cacheStoreProvider).retry),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                CacheSection(
                  title: '本机存储',
                  children: [
                    Text(
                      stats == null
                          ? '正在读取…'
                          : '${cacheSize(stats.usedBytes)} / ${cacheSize(store.limitBytes)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: stats == null
                          ? 0
                          : (stats.usedBytes / store.limitBytes).clamp(0, 1),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stats == null
                          ? ''
                          : '${stats.count} 条 · 永久保留 ${stats.pinned} 条（正文 ${cacheSize(stats.pinnedBytes)}）\n数据库文件 ${cacheSize(stats.fileBytes)}（包含可复用空闲页）',
                      style: TextStyle(color: palette.muted, height: 1.6),
                    ),
                    if (stats != null)
                      for (final row in stats.sites)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${ForumSite.byId(row['site'] as String).name} · ${row['count']} 条 · 正文 ${cacheSize(row['bytes'] as int)} · 保留 ${row['pinned']} 条',
                          ),
                        ),
                    if (store.warning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          store.warning!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                CacheSection(
                  title: '保存规则',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动缓存加载到的内容'),
                      subtitle: const Text('关闭后停止新增，不删除已有内容'),
                      value: store.enabled,
                      onChanged: _busy
                          ? null
                          : (v) => _work(() => store.configure(automatic: v)),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('容量上限'),
                      subtitle: Text(cacheSize(store.limitBytes)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _capacity,
                    ),
                    const Text(
                      '每条主贴、回复单独保存；重复加载只更新访问时间，不覆盖原文。超限时按最近访问时间淘汰普通缓存，跳过永久保留及正在离线阅读的内容。\n\n仅缓存文字和附件地址，不自动下载原图。SQLite 不加密；卸载或清除应用数据会丢失本地内容。',
                      style: TextStyle(height: 1.6, fontSize: 13),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/local-search?pinned=1'),
                      icon: const Icon(Icons.bookmark_outline),
                      label: const Text('管理永久保留内容'),
                    ),
                  ],
                ),
                CacheSection(
                  title: '清理与备份',
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: 'all',
                      decoration: const InputDecoration(labelText: '操作范围'),
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
                          : (v) =>
                                setState(() => _site = v == 'all' ? null : v),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('清理本地缓存'),
                      subtitle: const Text('覆盖所选岛所有身份；默认保留永久内容'),
                      onTap: _busy ? null : _clear,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.compress),
                      title: const Text('回收数据库空闲空间'),
                      subtitle: const Text('整理文件，不删除帖子记录'),
                      onTap: _busy ? null : () => _work(store.compact),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('导出当前身份缓存'),
                      subtitle: const Text('ZIP 备份 · 文字与附件地址 · 单份最多 32 MB'),
                      onTap: _busy ? null : () => _export(false),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark_outline),
                      title: const Text('仅导出永久保留'),
                      onTap: _busy ? null : () => _export(true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text('导入缓存备份'),
                      subtitle: const Text('按备份中的岛导入，不受上方范围影响'),
                      onTap: _busy ? null : _import,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
