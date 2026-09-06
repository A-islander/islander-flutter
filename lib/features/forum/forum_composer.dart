import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/emoji_constants.dart';
import '../../core/storage/storage_service.dart';
import '../../main.dart';
import '../../shared/widgets/media_item.dart';
import '../plate/models/plate_model.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

class ForumComposer extends ConsumerStatefulWidget {
  const ForumComposer({
    super.key,
    required this.boards,
    required this.boardId,
    this.threadId,
    this.quoteId,
  });
  final List<Plate> boards;
  final int boardId;
  final int? threadId;
  final int? quoteId;
  @override
  ConsumerState<ForumComposer> createState() => _ForumComposerState();
}

class _ForumComposerState extends ConsumerState<ForumComposer>
    with WidgetsBindingObserver {
  final _title = TextEditingController();
  late final _body = TextEditingController(
    text: widget.quoteId == null ? '' : 'No.${widget.quoteId} ',
  );
  late int _boardId = widget.boards.any((p) => p.id == widget.boardId)
      ? widget.boardId
      : widget.boards.firstOrNull?.id ?? 0;
  final _media = <MediaItem>[];
  bool _sending = false;
  bool _uploading = false;
  bool _emojis = false;
  double? _progress;
  String? _error;
  late final StorageService _storage;
  late final String _cookieId, _identityToken, _identityName;
  late String _draftKey;
  Timer? _saveTimer;
  bool _restoring = false, _finished = false, _transitioning = false;
  bool _draftReadError = false, _identityChanged = false;
  int _revision = 0, _boardRevision = 0;
  String _draftStatus = '自动保存到本机';
  bool get _reply => widget.threadId != null;
  bool get _busy => _sending || _uploading || _transitioning;
  bool get _hasContent =>
      _title.text.isNotEmpty || _body.text.isNotEmpty || _media.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _storage = ref.read(storageServiceProvider);
    final auth = ref.read(authProvider);
    _cookieId = auth.activeId ?? '';
    _identityToken = auth.token;
    _identityName = auth.current?.displayName ?? '未登录';
    _draftKey = _storage.draftKey(_cookieId, _boardId, widget.threadId);
    _restoreDraft(quoteId: widget.quoteId);
    _title.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
    WidgetsBinding.instance.addObserver(this);
    if (_hasContent && !_draftReadError) _scheduleSave();
  }

  void _restoreDraft({int? quoteId}) {
    _restoring = true;
    _draftReadError = false;
    try {
      final data = _storage.readDraft(_draftKey);
      if (data != null && data['version'] != 1) {
        throw const FormatException('Unknown draft');
      }
      final title = data?['title'] as String? ?? '';
      final body = data?['body'] as String? ?? '';
      final media = (data?['media'] as List? ?? [])
          .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _title.text = title;
      _body.text = body;
      _media
        ..clear()
        ..addAll(media);
      if (quoteId != null &&
          !RegExp('No\\.$quoteId(?![0-9])').hasMatch(_body.text)) {
        _body.text += '${_body.text.isEmpty ? '' : '\n'}No.$quoteId ';
      }
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
      _draftStatus = data == null ? '自动保存到本机' : '已恢复本机草稿';
    } catch (_) {
      _draftReadError = true;
      _error = '草稿读取失败，原数据未覆盖。可关闭后重试，或确认清空草稿。';
    } finally {
      _restoring = false;
    }
  }

  Map<String, dynamic>? _snapshot() => !_hasContent
      ? null
      : {
          'version': 1,
          'title': _title.text,
          'body': _body.text,
          'boardId': _boardId,
          'threadId': widget.threadId,
          'updatedAt': DateTime.now().toIso8601String(),
          'media': _media
              .map(
                (m) => {
                  'id': m.id,
                  'url': m.url,
                  'thumbnailUrl': m.thumbnailUrl,
                  'type': m.type,
                },
              )
              .toList(),
        };

  void _scheduleSave() {
    if (_restoring || _finished || _draftReadError || _cookieId.isEmpty) return;
    _revision++;
    _saveTimer?.cancel();
    setState(() => _draftStatus = '正在保存…');
    _saveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_saveDraft()),
    );
  }

  Future<bool> _saveDraft() async {
    _saveTimer?.cancel();
    if (_finished) return true;
    if (_draftReadError || _cookieId.isEmpty) return false;
    final revision = _revision;
    try {
      await _storage.saveDraft(_draftKey, _snapshot());
      if (mounted && revision == _revision) {
        setState(() => _draftStatus = '草稿已保存');
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _draftStatus = '保存失败，请重试');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_saveDraft());
  }

  Future<void> _switchBoard(int id) async {
    if (id == _boardId || _busy) return;
    setState(() => _transitioning = true);
    final saved = await _saveDraft();
    if (!mounted) return;
    setState(() {
      _boardRevision++;
      if (saved) {
        _boardId = id;
        _draftKey = _storage.draftKey(_cookieId, id, null);
        _error = null;
        _restoreDraft();
      } else {
        _error = '当前草稿尚未保存，未切换板块';
      }
      _transitioning = false;
    });
  }

  Future<void> _clearDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空这份草稿？'),
        content: const Text('只清空当前饼干在此板块或串中的草稿。已上传文件不会从服务器删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _saveTimer?.cancel();
    setState(() => _transitioning = true);
    try {
      await _storage.saveDraft(_draftKey, null);
      if (!mounted) return;
      setState(() {
        _restoring = true;
        _title.clear();
        _body.clear();
        _media.clear();
        _restoring = false;
        _draftReadError = false;
        _error = null;
        _revision++;
        _draftStatus = '草稿已清空';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '清空失败，请重试');
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    if (!_finished && !_draftReadError && _cookieId.isNotEmpty) {
      unawaited(
        _storage.saveDraft(_draftKey, _snapshot()).catchError((Object _) {}),
      );
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_draftReadError) {
      Navigator.pop(context);
      return;
    }
    setState(() => _transitioning = true);
    final saved = await _saveDraft();
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _transitioning = false;
        _error = '草稿尚未保存，请重试后关闭';
      });
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _insert(String text) {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : _body.text.length;
    _body.value = TextEditingValue(
      text: _body.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _pick(bool video) async {
    if (_busy || _identityChanged || _draftReadError || _media.length >= 5) {
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (video) {
        final file = await picker.pickVideo(source: ImageSource.gallery);
        files = file == null ? [] : [file];
      } else {
        files = await picker.pickMultiImage();
      }
      for (final file in files.take(5 - _media.length)) {
        final media = await ref.read(forumRepositoryProvider).upload(
          file,
          video ? 'video' : 'image',
          (sent, total) {
            if (mounted) {
              setState(() => _progress = total > 0 ? sent / total : null);
            }
          },
          expectedToken: _identityToken,
        );
        if (!mounted) return;
        setState(() => _media.add(media));
        _scheduleSave();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is ForumFailure ? error.message : '无法选择或上传文件，请重试',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_identityChanged ||
        ref.read(authProvider).token != _identityToken ||
        _identityToken.isEmpty) {
      setState(() => _error = '饼干已切换，请关闭并重新打开编辑器；草稿仍属于原饼干');
      return;
    }
    if (_draftReadError) return;
    if (_body.text.trim().isEmpty) {
      setState(() => _error = '请先写下正文');
      return;
    }
    if (!_reply && !widget.boards.any((p) => p.id == _boardId)) {
      setState(() => _error = '请选择板块');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (!await _saveDraft()) throw const ForumFailure('草稿保存失败，请重试后发布');
      if (!mounted || _identityChanged) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      await ref
          .read(forumRepositoryProvider)
          .publish(
            body: _body.text.trim(),
            title: _title.text.trim(),
            boardId: _boardId,
            threadId: widget.threadId,
            media: _media,
            expectedToken: _identityToken,
          );
      _finished = true;
      _saveTimer?.cancel();
      try {
        await _storage.saveDraft(_draftKey, null);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已发布，但本机草稿清理失败，请勿重复发布')));
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (next.token != _identityToken && mounted) {
        setState(() => _identityChanged = true);
      }
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: SheetSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reply ? 'REPLY · NO.${widget.threadId}' : 'NEW THREAD',
                        style: TextStyle(
                          color: ForumPalette.of(context).accent,
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        _reply ? '写下回复' : '发布新串',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _close,
                  tooltip: '关闭编辑',
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              '使用：$_identityName',
              style: TextStyle(
                fontSize: 12,
                color: ForumPalette.of(context).muted,
              ),
            ),
            if (_identityChanged)
              Text(
                '饼干已切换，关闭后将保留原饼干草稿。请重新打开编辑器。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _draftStatus,
                    key: Key('draft-status'),
                    style: TextStyle(
                      fontSize: 11,
                      color: ForumPalette.of(context).muted,
                    ),
                  ),
                ),
                TextButton(
                  key: Key('draft-clear'),
                  onPressed: _busy ? null : _clearDraft,
                  child: Text('清空草稿'),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (!_reply) ...[
              DropdownButtonFormField<int>(
                key: ValueKey('composer-board-$_boardId-$_boardRevision'),
                initialValue: widget.boards.isEmpty ? null : _boardId,
                decoration: InputDecoration(labelText: '发布到'),
                items: widget.boards
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) {
                        if (id != null) _switchBoard(id);
                      },
              ),
              SizedBox(height: 16),
              TextField(
                key: Key('composer-title'),
                controller: _title,
                enabled: !_busy,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: '标题（可选）',
                  counterText: '',
                ),
              ),
              SizedBox(height: 16),
            ],
            TextField(
              key: Key('composer-body'),
              controller: _body,
              enabled: !_busy,
              minLines: 4,
              maxLines: 8,
              maxLength: 10000,
              decoration: InputDecoration(
                labelText: '正文',
                hintText: '写下想说的话，输入 No.编号 引用内容',
              ),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _emojis = !_emojis),
                  child: Text('颜文字'),
                ),
                IconButton(
                  onPressed: _busy || _media.length >= 5
                      ? null
                      : () => _pick(false),
                  tooltip: '添加图片',
                  icon: Icon(Icons.image_outlined),
                ),
                IconButton(
                  onPressed: _busy || _media.length >= 5
                      ? null
                      : () => _pick(true),
                  tooltip: '添加视频',
                  icon: Icon(Icons.videocam_outlined),
                ),
                Text(
                  '${_media.length}/5 · 单个 20 MB',
                  style: TextStyle(
                    fontSize: 11,
                    color: ForumPalette.of(context).muted,
                  ),
                ),
              ],
            ),
            if (_emojis)
              SizedBox(
                height: 140,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    children: emojiList
                        .map(
                          (e) => TextButton(
                            onPressed: _busy ? null : () => _insert(e),
                            child: Text(e),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            if (_uploading) LinearProgressIndicator(value: _progress),
            if (_media.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _media
                    .asMap()
                    .entries
                    .map(
                      (entry) => InputChip(
                        avatar: Icon(
                          entry.value.type == 'video'
                              ? Icons.videocam
                              : Icons.image,
                          size: 16,
                        ),
                        label: Text('附件 ${entry.key + 1}'),
                        onDeleted: _busy
                            ? null
                            : () {
                                setState(() => _media.removeAt(entry.key));
                                _scheduleSave();
                              },
                      ),
                    )
                    .toList(),
              ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('composer-submit'),
                onPressed: _busy || _identityChanged || _draftReadError
                    ? null
                    : _submit,
                child: Text(
                  _sending
                      ? '正在发布…'
                      : _reply
                      ? '发布回复'
                      : '发布新串',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
