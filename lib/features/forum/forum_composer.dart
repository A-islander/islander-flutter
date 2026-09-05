import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/emoji_constants.dart';
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

class _ForumComposerState extends ConsumerState<ForumComposer> {
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
  bool get _reply => widget.threadId != null;
  bool get _busy => _sending || _uploading;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_title.text.isNotEmpty ||
        _body.text.trim().isNotEmpty ||
        _media.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('放弃这次编辑？'),
          content: Text('尚未发布的内容将丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('放弃'),
            ),
          ],
        ),
      );
      if (discard != true) return;
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
    if (_busy || _media.length >= 5) return;
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
        );
        if (!mounted) return;
        setState(() => _media.add(media));
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
      await ref
          .read(forumRepositoryProvider)
          .publish(
            body: _body.text.trim(),
            title: _title.text.trim(),
            boardId: _boardId,
            threadId: widget.threadId,
            media: _media,
          );
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
  Widget build(BuildContext context) => PopScope(
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
          SizedBox(height: 24),
          if (!_reply) ...[
            DropdownButtonFormField<int>(
              initialValue: widget.boards.isEmpty ? null : _boardId,
              decoration: InputDecoration(labelText: '发布到'),
              items: widget.boards
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (id) => setState(() => _boardId = id ?? _boardId),
            ),
            SizedBox(height: 16),
            TextField(
              key: Key('composer-title'),
              controller: _title,
              enabled: !_busy,
              maxLength: 40,
              decoration: InputDecoration(labelText: '标题（可选）', counterText: ''),
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
                          : () => setState(() => _media.removeAt(entry.key)),
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
              onPressed: _busy ? null : _submit,
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
