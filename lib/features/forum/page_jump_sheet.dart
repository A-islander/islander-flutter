import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'forum_theme.dart';

class PageDestination {
  PageDestination.page(this.page) : latest = false;
  PageDestination.latest() : page = null, latest = true;
  final int? page;
  final bool latest;
}

class PageJumpSheet extends StatefulWidget {
  const PageJumpSheet({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.title,
    this.isThread = false,
  });
  final int currentPage;
  final int totalPages;
  final String title;
  final bool isThread;
  @override
  State<PageJumpSheet> createState() => _PageJumpSheetState();
}

class _PageJumpSheetState extends State<PageJumpSheet> {
  late final _page = TextEditingController(text: '${widget.currentPage + 1}');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int page) => Navigator.pop(context, PageDestination.page(page));
  void _submit() {
    if (_form.currentState!.validate()) _go(int.parse(_page.text.trim()) - 1);
  }

  @override
  Widget build(BuildContext context) => SheetSurface(
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAGE NAVIGATION',
                      style: TextStyle(
                        color: ForumPalette.of(context).accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '跳转页码',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: '关闭跳页',
                icon: Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '${widget.title} · 当前第 ${widget.currentPage + 1} 页，共 ${widget.totalPages} 页',
            style: TextStyle(
              color: ForumPalette.of(context).muted,
              height: 1.7,
            ),
          ),
          SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('page-jump-input'),
                  controller: _page,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onTap: () => _page.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _page.text.length,
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '页码',
                    hintText: '1—${widget.totalPages}',
                    suffixText: '/ ${widget.totalPages}',
                  ),
                  validator: (value) {
                    final page = int.tryParse(value?.trim() ?? '');
                    return page == null || page < 1 || page > widget.totalPages
                        ? '请输入 1—${widget.totalPages} 之间的页码'
                        : null;
                  },
                ),
              ),
              SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: Key('page-jump-submit'),
                  onPressed: _submit,
                  child: Text('跳转'),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.currentPage == 0
                      ? null
                      : () => _go(widget.currentPage - 1),
                  icon: Icon(Icons.arrow_back, size: 16),
                  label: Text('上一页'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.currentPage + 1 >= widget.totalPages
                      ? null
                      : () => _go(widget.currentPage + 1),
                  icon: Icon(Icons.arrow_forward, size: 16),
                  label: Text('下一页'),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: widget.currentPage == 0 ? null : () => _go(0),
                child: Text('回到首页'),
              ),
              TextButton(
                onPressed: widget.currentPage + 1 >= widget.totalPages
                    ? null
                    : () => _go(widget.totalPages - 1),
                child: Text('跳到末页'),
              ),
              if (widget.isThread)
                TextButton.icon(
                  key: Key('page-jump-latest'),
                  onPressed: () =>
                      Navigator.pop(context, PageDestination.latest()),
                  icon: Icon(Icons.south, size: 16),
                  label: Text('最新回复'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
