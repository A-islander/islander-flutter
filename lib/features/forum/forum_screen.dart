import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../shared/widgets/pixel_shore.dart';
import '../plate/models/plate_model.dart';
import '../plate/models/post_model.dart';
import 'cookie_sheet.dart';
import 'forum_composer.dart';
import 'forum_links.dart';
import 'forum_post_view.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

final forumBoardsProvider = FutureProvider<List<Plate>>(
  (ref) => ref.watch(forumRepositoryProvider).plates(),
);

class ForumScreen extends ConsumerStatefulWidget {
  const ForumScreen({
    super.key,
    this.kind = 'timeline',
    this.boardId = 0,
    this.postId = 0,
  });
  final String kind;
  final int boardId;
  final int postId;
  @override
  ConsumerState<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends ConsumerState<ForumScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _targetKey = GlobalKey();
  List<Post> _posts = [];
  Post? _thread;
  int? _highlightId;
  int _page = 0;
  int _count = 0;
  int _request = 0;
  bool _loading = true;
  bool _newest = false;
  bool _showSearch = false;
  String? _error;
  String? _notice;
  String _query = '';
  bool get _isThread => widget.kind == 'thread';
  bool get _isMine => widget.kind == 'mine';
  int get _pages =>
      ((_count + ForumRepository.pageSize - 1) ~/ ForumRepository.pageSize)
          .clamp(1, 1000000);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(resolve: true));
  }

  @override
  void didUpdateWidget(covariant ForumScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.boardId != widget.boardId ||
        oldWidget.postId != widget.postId) {
      _page = 0;
      _thread = null;
      _highlightId = null;
      _query = '';
      _search.clear();
      _load(resolve: true);
    }
  }

  @override
  void dispose() {
    _request++;
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({
    bool resolve = false,
    int? page,
    bool last = false,
  }) async {
    if (!mounted) return;
    final ticket = ++_request;
    if (_isMine && !ref.read(authProvider).isLoggedIn) {
      setState(() {
        _posts = [];
        _count = 0;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    final repo = ref.read(forumRepositoryProvider);
    var currentPage = page ?? _page;
    var thread = _thread;
    int? highlight = _highlightId;
    String? notice;
    try {
      if (_isThread) {
        if (resolve || thread == null) {
          final target = await repo.post(widget.postId);
          if (target.followId != 0) {
            thread = await repo.post(target.followId);
            highlight = target.id;
            try {
              currentPage = await repo.replyPage(thread.id, target.id);
            } catch (_) {
              currentPage = 0;
              notice = '暂时无法定位该回复，已打开所在串首页';
            }
          } else {
            thread = target;
            highlight = null;
          }
        } else {
          thread = await repo.post(thread.id);
        }
      }
      var data = await repo.page(
        kind: widget.kind,
        boardId: widget.boardId,
        postId: thread?.id ?? 0,
        page: currentPage,
      );
      final maxPage = ((data.count - 1) ~/ ForumRepository.pageSize).clamp(
        0,
        1000000,
      );
      if (last || currentPage > maxPage) {
        currentPage = maxPage;
        data = await repo.page(
          kind: widget.kind,
          boardId: widget.boardId,
          postId: thread?.id ?? 0,
          page: currentPage,
        );
      }
      if (!mounted || ticket != _request) return;
      setState(() {
        _thread = thread;
        _posts = data.posts;
        _count = data.count;
        _page = currentPage;
        _highlightId = highlight;
        _notice = notice;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ticket != _request) return;
        if (resolve && _targetKey.currentContext != null) {
          Scrollable.ensureVisible(_targetKey.currentContext!, alignment: .12);
        } else if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    } catch (error) {
      if (mounted && ticket == _request) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  void _navigate(String route) {
    _scaffold.currentState?.closeDrawer();
    context.go(route);
  }

  void _open(Post post) => context.push('/post/${post.id}');
  Future<void> _cookie() async {
    await forumSheet(context, const CookieSheet());
  }

  Future<void> _compose({int? quoteId}) async {
    if (!ref.read(authProvider).isLoggedIn) {
      await _cookie();
      if (!mounted || !ref.read(authProvider).isLoggedIn) return;
    }
    final boards = ref.read(forumBoardsProvider).asData?.value ?? [];
    if (!_isThread && boards.isEmpty) {
      ref.invalidate(forumBoardsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在加载板块，请稍后再试')));
      return;
    }
    if (_isThread && _thread == null) return;
    final result = await forumSheet<bool>(
      context,
      ForumComposer(
        boards: boards,
        boardId: _thread?.plateId ?? widget.boardId,
        threadId: _isThread ? _thread?.id : null,
        quoteId: quoteId,
      ),
      dismissible: false,
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_isThread ? '回复已发布' : '新串已发布')));
      await _load(page: 0, last: _isThread);
    }
  }

  void _searchSubmit(String value) {
    final match = RegExp(
      r'^(?:No\.)?(\d+)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match != null) context.push('/post/${int.parse(match[1]!)}');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    ref.listen(authProvider, (previous, next) {
      if (_isMine && previous?.token != next.token) {
        _load(page: 0);
      }
    });
    final boards = ref.watch(forumBoardsProvider);
    final boardList = boards.asData?.value ?? [];
    String boardName(int id) =>
        boardList.where((p) => p.id == id).firstOrNull?.name ?? '板块 $id';
    final board = boardList.where((p) => p.id == widget.boardId).firstOrNull;
    final title = switch (widget.kind) {
      'board' => board?.name ?? '板块',
      'sage' => 'SAGE 串',
      'mine' => '我的内容',
      'thread' => '串的讨论',
      _ => '时间线',
    };
    final description = switch (widget.kind) {
      'board' => board?.value ?? '',
      'sage' => '已被 SAGE 的串与回复',
      'mine' => '你的发串与回复，也可以在这里恢复已删除内容',
      _ => '全岛最近有回应的串',
    };
    final eyebrow = switch (widget.kind) {
      'board' => 'BOARD',
      'sage' => 'SAGE',
      'mine' => 'MY POSTS',
      'thread' => 'DISCUSSION',
      _ => 'LATEST ACTIVITY',
    };
    var visible = _posts
        .where((p) => !_isThread || p.id != _thread?.id)
        .toList();
    if (_query.isNotEmpty) {
      visible = visible
          .where(
            (p) => '${p.id} ${p.title} ${p.value}'.toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
    }
    if (_newest && !_isThread) visible.sort((a, b) => b.time.compareTo(a.time));

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        final compact = constraints.maxWidth < 600;
        final horizontal = compact ? 20.0 : 36.0;
        final shoreHeight = wide ? 152.0 : 112.0;
        Widget sidebar() => _ForumSidebar(
          kind: widget.kind,
          boardId: _thread?.plateId ?? widget.boardId,
          boards: boards,
          onNavigate: _navigate,
          onRetry: () => ref.invalidate(forumBoardsProvider),
        );
        final cookieName = auth.isLoggedIn
            ? (auth.name.isEmpty ? '岛民 #${auth.userId}' : auth.name)
            : '导入 / 领取';
        return Scaffold(
          key: _scaffold,
          appBar: AppBar(
            toolbarHeight: 64,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            title: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
                  child: Row(
                    children: [
                      if (!wide)
                        IconButton(
                          onPressed: () => _scaffold.currentState?.openDrawer(),
                          tooltip: '打开导航',
                          icon: const Icon(Icons.menu, size: 21),
                        ),
                      TextButton(
                        onPressed: () => _navigate('/plate/0'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compact)
                              const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Icon(Icons.waves, size: 28),
                              ),
                            const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '岛民岛',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.8,
                                  ),
                                ),
                                Text(
                                  'ISLANDER FORUM',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xA8FFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (wide)
                        SizedBox(
                          width: 360,
                          height: 40,
                          child: TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v.trim()),
                            onSubmitted: _searchSubmit,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: '筛选本页 / 输入 No.编号回车跳转',
                              hintStyle: const TextStyle(
                                color: Color(0xB3FFFFFF),
                              ),
                              fillColor: Colors.white.withValues(alpha: .1),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.white,
                                size: 18,
                              ),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0x55FFFFFF),
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      if (!wide)
                        IconButton(
                          onPressed: () =>
                              setState(() => _showSearch = !_showSearch),
                          tooltip: '筛选与跳转',
                          icon: const Icon(Icons.search, size: 21),
                        ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: const Key('cookie-button'),
                        onTap: _cookie,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 90 : 160,
                          ),
                          padding: const EdgeInsets.only(
                            left: 10,
                            top: 3,
                            bottom: 3,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.white, width: 2),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '我的饼干',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xB3FFFFFF),
                                ),
                              ),
                              Text(
                                cookieName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          drawer: wide
              ? null
              : Drawer(
                  width: 304,
                  shape: const RoundedRectangleBorder(),
                  child: SafeArea(child: sidebar()),
                ),
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border.symmetric(
                          vertical: BorderSide(color: ForumColors.line),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x12102220),
                            blurRadius: 44,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide) ...[
                            SizedBox(width: 240, child: sidebar()),
                            const VerticalDivider(width: 1),
                          ],
                          Expanded(
                            child: Column(
                              children: [
                                if (!wide && _showSearch)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: TextField(
                                      controller: _search,
                                      onChanged: (v) =>
                                          setState(() => _query = v.trim()),
                                      onSubmitted: _searchSubmit,
                                      decoration: const InputDecoration(
                                        labelText: '筛选本页 / No.编号回车跳转',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: () => _load(),
                                    child: SingleChildScrollView(
                                      controller: _scroll,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              horizontal,
                                              _isThread ? 20 : 38,
                                              horizontal,
                                              _isThread ? 12 : 32,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (_isThread)
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      if (context.canPop()) {
                                                        context.pop();
                                                      } else {
                                                        _navigate(
                                                          '/plate/${_thread?.plateId ?? 0}',
                                                        );
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons.arrow_back,
                                                      size: 16,
                                                    ),
                                                    label: const Text('返回列表'),
                                                  ),
                                                Text(
                                                  eyebrow,
                                                  style: const TextStyle(
                                                    color: ForumColors.accent,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 14),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        title,
                                                        style: TextStyle(
                                                          fontSize: compact
                                                              ? 31
                                                              : 38,
                                                          height: 1.1,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: _loading
                                                          ? null
                                                          : () => _load(),
                                                      tooltip: '刷新',
                                                      icon: const Icon(
                                                        Icons.refresh,
                                                        color:
                                                            ForumColors.muted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (!_isThread) ...[
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    description,
                                                    style: const TextStyle(
                                                      color: ForumColors.muted,
                                                      height: 1.7,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (!_isThread && !_isMine)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: horizontal,
                                              ),
                                              decoration: const BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: ForumColors.line,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  _SortTab(
                                                    label: widget.kind == 'sage'
                                                        ? '默认顺序'
                                                        : '最近回复',
                                                    selected: !_newest,
                                                    onTap: () => setState(
                                                      () => _newest = false,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 20),
                                                  _SortTab(
                                                    label: '本页最新发布',
                                                    selected: _newest,
                                                    onTap: () => setState(
                                                      () => _newest = true,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    '$_count 条',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: ForumColors.muted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (_loading)
                                            const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 48,
                                              ),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            )
                                          else if (_error != null)
                                            _Message(
                                              text: _error!,
                                              action: '重试',
                                              onTap: () => _load(
                                                resolve: _thread == null,
                                              ),
                                            )
                                          else if (_isMine && !auth.isLoggedIn)
                                            _Message(
                                              text: '导入饼干后查看自己的发串与回复',
                                              action: '导入 / 领取饼干',
                                              onTap: _cookie,
                                            )
                                          else ...[
                                            if (_notice != null)
                                              Padding(
                                                padding: EdgeInsets.all(
                                                  horizontal,
                                                ),
                                                child: Text(
                                                  _notice!,
                                                  style: const TextStyle(
                                                    color: ForumColors.muted,
                                                  ),
                                                ),
                                              ),
                                            if (_isThread &&
                                                _thread != null) ...[
                                              ForumPostView(
                                                key: ValueKey(
                                                  'root-${_thread!.id}',
                                                ),
                                                post: _thread!,
                                                boardName: boardName(
                                                  _thread!.plateId,
                                                ),
                                                onReply: (id) =>
                                                    _compose(quoteId: id),
                                                onChanged: () => _load(),
                                              ),
                                              Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  horizontal,
                                                  24,
                                                  horizontal,
                                                  12,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${(_count - 1).clamp(0, 1000000)} 个回复 · 第 ${_page + 1} 页',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          _load(last: true),
                                                      child: const Text(
                                                        '最新回复 ↓',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            if (visible.isEmpty)
                                              _Message(
                                                text: _query.isNotEmpty
                                                    ? '本页没有匹配内容'
                                                    : _isThread
                                                    ? '这一页还没有回复'
                                                    : '这里暂时没有内容',
                                                action: _query.isNotEmpty
                                                    ? '清除筛选'
                                                    : '刷新',
                                                onTap: () {
                                                  if (_query.isNotEmpty) {
                                                    _search.clear();
                                                    setState(() => _query = '');
                                                  } else {
                                                    _load();
                                                  }
                                                },
                                              ),
                                            ...visible.map(
                                              (post) => ForumPostView(
                                                key: post.id == _highlightId
                                                    ? _targetKey
                                                    : ValueKey(
                                                        'post-${post.id}',
                                                      ),
                                                post: post,
                                                boardName: boardName(
                                                  post.plateId,
                                                ),
                                                preview: !_isThread,
                                                highlighted:
                                                    post.id == _highlightId,
                                                onOpen: () => _open(post),
                                                onReply: (id) =>
                                                    _compose(quoteId: id),
                                                onChanged: () => _load(),
                                              ),
                                            ),
                                            if (_count > 0)
                                              Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  horizontal,
                                                  24,
                                                  horizontal,
                                                  16,
                                                ),
                                                child: Wrap(
                                                  spacing: 10,
                                                  runSpacing: 8,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    OutlinedButton(
                                                      onPressed: _page == 0
                                                          ? null
                                                          : () => _load(
                                                              page: _page - 1,
                                                            ),
                                                      child: const Text(
                                                        '← 上一页',
                                                      ),
                                                    ),
                                                    Text(
                                                      '${_page + 1} / $_pages',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            ForumColors.muted,
                                                      ),
                                                    ),
                                                    OutlinedButton(
                                                      onPressed:
                                                          _page + 1 >= _pages
                                                          ? null
                                                          : () => _load(
                                                              page: _page + 1,
                                                            ),
                                                      child: const Text(
                                                        '下一页 →',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                          SizedBox(height: shoreHeight + 60),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PixelShore(height: shoreHeight),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('fab-compose'),
            onPressed: _isThread && (_loading || _thread == null)
                ? null
                : () => _compose(),
            backgroundColor: ForumColors.accent,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(),
            elevation: 8,
            icon: const Icon(Icons.add, size: 20),
            label: Text(
              _isThread ? '回复' : '发新串',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }
}

class _ForumSidebar extends StatelessWidget {
  const _ForumSidebar({
    required this.kind,
    required this.boardId,
    required this.boards,
    required this.onNavigate,
    required this.onRetry,
  });
  final String kind;
  final int boardId;
  final AsyncValue<List<Plate>> boards;
  final ValueChanged<String> onNavigate;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            // Leave room to scroll the final links above the fixed shore.
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 176),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '浏览',
                  style: TextStyle(fontSize: 10, color: ForumColors.muted),
                ),
              ),
              _NavItem(
                index: '01',
                title: '时间线',
                selected: kind == 'timeline',
                onTap: () => onNavigate('/plate/0'),
              ),
              _NavItem(
                index: '02',
                title: 'SAGE 串',
                selected: kind == 'sage',
                onTap: () => onNavigate('/sage'),
              ),
              _NavItem(
                index: '03',
                title: '我的内容',
                selected: kind == 'mine',
                onTap: () => onNavigate('/mine'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: const Text(
                    '板块',
                    style: TextStyle(fontSize: 10, color: ForumColors.muted),
                  ),
                  children: [
                    boards.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => TextButton(
                        onPressed: onRetry,
                        child: const Text('板块加载失败，点击重试'),
                      ),
                      data: (items) => Column(
                        children: items
                            .map(
                              (p) => _NavItem(
                                index: '▪',
                                title: p.name,
                                subtitle: p.value,
                                selected:
                                    (kind == 'board' || kind == 'thread') &&
                                    boardId == p.id,
                                onTap: () => onNavigate('/plate/${p.id}'),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const ForumExternalLinks(),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 20, 28, 22),
          child: Text(
            'ISLANDER.TOP',
            style: TextStyle(fontSize: 10, color: ForumColors.muted),
          ),
        ),
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle = '',
  });
  final String index;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? ForumColors.soft : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selected ? ForumColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              index,
              style: const TextStyle(fontSize: 10, color: ForumColors.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? ForumColors.accent : ForumColors.ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: ForumColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SortTab extends StatelessWidget {
  const _SortTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 49,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? ForumColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ForumColors.accent : ForumColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.action,
    required this.onTap,
  });
  final String text;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: ForumColors.muted, height: 1.7),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}
