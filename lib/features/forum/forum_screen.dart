import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'page_jump_sheet.dart';
import 'prepend_sliver.dart';

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
  int _startPage = 0;
  final Map<int, int> _postPages = {};
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _moreError;
  bool _loadingPrevious = false;
  bool _previousExhausted = false;
  String? _previousError;
  int? _prependPage;
  int? _pendingPrependPage;
  final Map<int, GlobalKey> _pageKeys = {};
  bool _pullFromMiddle = false;
  bool _previousRequestedThisDrag = false;
  int _count = 0;
  int _request = 0;
  int? _retryPage;
  bool _retryLast = false;
  bool _loading = true;
  bool _newest = false;
  bool _showSearch = false;
  String? _error;
  String? _notice;
  String _query = '';
  bool get _isThread => widget.kind == 'thread';
  bool get _isMine => widget.kind == 'mine';
  bool get _hasMore => !_exhausted && _page + 1 < _pages;
  bool get _hasPrevious => _startPage > 0 && !_previousExhausted;
  String get _pageRange =>
      _startPage == _page ? '${_page + 1}' : '${_startPage + 1}–${_page + 1}';
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
      _startPage = 0;
      _retryPage = null;
      _retryLast = false;
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
    var currentPage = page ?? _retryPage ?? _startPage;
    final loadLast = last || (page == null && _retryLast);
    _loadingMore = false;
    _moreError = null;
    _loadingPrevious = false;
    _previousError = null;
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
      if (loadLast || currentPage > maxPage) {
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
        _posts = {for (final post in data.posts) post.id: post}.values.toList();
        _postPages
          ..clear()
          ..addEntries(_posts.map((post) => MapEntry(post.id, currentPage)));
        _count = data.count;
        _page = currentPage;
        _startPage = currentPage;
        _prependPage = null;
        _pendingPrependPage = null;
        _pageKeys.clear();
        _previousExhausted = false;
        _exhausted = data.posts.isEmpty;
        _retryPage = null;
        _retryLast = false;
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
          _retryPage = currentPage;
          _retryLast = loadLast;
          _loading = false;
        });
      }
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_scroll.hasClients) return false;
    if (notification is ScrollEndNotification) {
      _previousRequestedThisDrag = false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pullFromMiddle = _hasPrevious;
      _previousRequestedThisDrag = false;
    }
    final movingUp = notification is ScrollUpdateNotification
        ? (notification.scrollDelta ?? 0) < 0
        : notification is OverscrollNotification && notification.overscroll < 0;
    if (movingUp &&
        _scroll.position.userScrollDirection == ScrollDirection.forward &&
        notification.metrics.extentBefore < 180 &&
        _previousError == null &&
        !_previousRequestedThisDrag &&
        ModalRoute.of(context)?.isCurrent == true &&
        !_loadingMore &&
        !_loadingPrevious &&
        _hasPrevious) {
      _previousRequestedThisDrag = true;
      _loadPrevious();
    }
    final movingDown = notification is ScrollUpdateNotification
        ? (notification.scrollDelta ?? 0) > 0
        : notification is OverscrollNotification && notification.overscroll > 0;
    if (notification.depth == 0 &&
        movingDown &&
        _scroll.position.userScrollDirection == ScrollDirection.reverse &&
        notification.metrics.extentAfter < 240 &&
        _moreError == null &&
        ModalRoute.of(context)?.isCurrent == true) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (!mounted ||
        _loading ||
        _loadingMore ||
        _loadingPrevious ||
        _error != null ||
        !_hasMore ||
        (_isMine && !ref.read(authProvider).isLoggedIn)) {
      return;
    }
    final ticket = ++_request;
    final nextPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final data = await ref
          .read(forumRepositoryProvider)
          .page(
            kind: widget.kind,
            boardId: widget.boardId,
            postId: _thread?.id ?? 0,
            page: nextPage,
          );
      if (!mounted || ticket != _request) return;
      setState(() {
        // Live timelines can move between requests. Keep existing rows stable.
        final known = _posts.map((post) => post.id).toSet();
        for (final post in data.posts) {
          if (known.add(post.id)) {
            _posts.add(post);
            _postPages[post.id] = nextPage;
          }
        }
        _count = data.count;
        _page = nextPage;
        _exhausted = data.posts.isEmpty;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || ticket != _request) return;
      setState(() {
        _loadingMore = false;
        _moreError = error.toString();
      });
    }
  }

  Future<void> _loadPrevious() async {
    if (!mounted ||
        _loading ||
        _loadingMore ||
        _loadingPrevious ||
        _error != null ||
        !_hasPrevious ||
        (_isMine && !ref.read(authProvider).isLoggedIn)) {
      return;
    }
    final ticket = ++_request;
    final previousPage = _startPage - 1;
    setState(() {
      _loadingPrevious = true;
      _previousError = null;
    });
    try {
      final data = await ref
          .read(forumRepositoryProvider)
          .page(
            kind: widget.kind,
            boardId: widget.boardId,
            postId: _thread?.id ?? 0,
            page: previousPage,
          );
      if (!mounted || ticket != _request) return;
      setState(() {
        final known = _posts.map((post) => post.id).toSet();
        final added = data.posts.where((post) => known.add(post.id)).toList();
        for (final post in added) {
          _postPages[post.id] = previousPage;
        }
        _posts.insertAll(0, added);
        _startPage = previousPage;
        _count = data.count;
        _previousExhausted = data.posts.isEmpty;
        // Only the newest prepended page is eagerly measured; all remaining
        // pages return to the lazy list. Stable global page keys retain rows.
        _prependPage = added.any((post) => !_isThread || post.id != _thread?.id)
            ? previousPage
            : _prependPage;
        _pendingPrependPage =
            added.any(
              (post) =>
                  (!_isThread || post.id != _thread?.id) &&
                  '${post.id} ${post.title} ${post.value}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
            )
            ? previousPage
            : null;
        _loadingPrevious = false;
      });
    } catch (error) {
      if (!mounted || ticket != _request) return;
      setState(() {
        _loadingPrevious = false;
        _previousError = error.toString();
      });
    }
  }

  bool _canRefresh(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pullFromMiddle = _hasPrevious;
      _previousRequestedThisDrag = false;
    }
    return !_hasPrevious && !_pullFromMiddle && !_loadingPrevious;
  }

  void _navigate(String route) {
    _scaffold.currentState?.closeDrawer();
    context.go(route);
  }

  void _open(Post post) => context.push('/post/${post.id}');
  Future<void> _openPageJump(String title) async {
    if (_loading || _count == 0 || _error != null) return;
    final destination = await forumSheet<PageDestination>(
      context,
      PageJumpSheet(
        currentPage: _page,
        totalPages: _pages,
        title: title,
        isThread: _isThread,
      ),
    );
    if (!mounted || destination == null) return;
    if (!destination.latest &&
        destination.page == _page &&
        _startPage == _page) {
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          0,
          duration: Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    _search.clear();
    setState(() => _query = '');
    await _load(page: destination.page, last: destination.latest);
  }

  Future<void> _cookie() async {
    await forumSheet(context, CookieSheet());
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
      ).showSnackBar(SnackBar(content: Text('正在加载板块，请稍后再试')));
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
    if (_newest && !_isThread) {
      visible.sort((a, b) {
        final pageOrder = _postPages[a.id]!.compareTo(_postPages[b.id]!);
        return pageOrder != 0 ? pageOrder : b.time.compareTo(a.time);
      });
    }
    // Build lazily by API page (20 rows). The first page stays a single group
    // so direct reply links can still locate a variable-height reply by key.
    final grouped = <int, List<Post>>{};
    for (final post in visible) {
      grouped.putIfAbsent(_postPages[post.id]!, () => []).add(post);
    }
    final visiblePages = grouped.values.toList();
    final prepended = grouped[_prependPage];
    final lazyPages = visiblePages.where((page) => page != prepended).toList();
    Widget pageView(List<Post> posts) => Column(
      key: _pageKeys.putIfAbsent(_postPages[posts.first.id]!, GlobalKey.new),
      children: posts
          .map(
            (post) => ForumPostView(
              key: post.id == _highlightId
                  ? _targetKey
                  : ValueKey('post-${post.id}'),
              post: post,
              boardName: boardName(post.plateId),
              preview: !_isThread,
              highlighted: post.id == _highlightId,
              onOpen: () => _open(post),
              onReply: (id) => _compose(quoteId: id),
              onChanged: () => _load(),
            ),
          )
          .toList(),
    );

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
                constraints: BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
                  child: Row(
                    children: [
                      if (!wide)
                        IconButton(
                          onPressed: () => _scaffold.currentState?.openDrawer(),
                          tooltip: '打开导航',
                          icon: Icon(Icons.menu, size: 21),
                        ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => _navigate('/plate/0'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!compact)
                                    Padding(
                                      padding: EdgeInsets.only(right: 12),
                                      child: Icon(Icons.waves, size: 28),
                                    ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                          ),
                        ),
                      ),
                      if (wide)
                        SizedBox(
                          width: 360,
                          height: 40,
                          child: TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v.trim()),
                            onSubmitted: _searchSubmit,
                            style: TextStyle(color: Colors.white, fontSize: 13),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: '筛选已加载内容 / No.编号跳转',
                              hintStyle: TextStyle(color: Color(0xB3FFFFFF)),
                              fillColor: Colors.white.withValues(alpha: .1),
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.white,
                                size: 18,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0x55FFFFFF),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
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
                          icon: Icon(Icons.search, size: 21),
                        ),
                      if (!compact) SizedBox(width: 8),
                      if (compact)
                        IconButton(
                          key: Key('cookie-button'),
                          onPressed: _cookie,
                          tooltip: '我的饼干 · $cookieName',
                          icon: Icon(Icons.person_outline, size: 21),
                        )
                      else
                        InkWell(
                          key: Key('cookie-button'),
                          onTap: _cookie,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: compact ? 90 : 160,
                            ),
                            padding: EdgeInsets.only(
                              left: 10,
                              top: 3,
                              bottom: 3,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!compact) SizedBox(width: 12),
                      Tooltip(
                        message: '跳转页码',
                        child: SizedBox(
                          width: compact ? 64 : 84,
                          child: TextButton(
                            key: Key('page-jump-trigger'),
                            onPressed: _loading || _count == 0 || _error != null
                                ? null
                                : () => _openPageJump(title),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white54,
                              minimumSize: Size(44, 48),
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              shape: RoundedRectangleBorder(),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _loading
                                    ? '… / …'
                                    : _count == 0 || _error != null
                                    ? '— / —'
                                    : '$_pageRange / $_pages',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
                  shape: RoundedRectangleBorder(),
                  child: SafeArea(child: sidebar()),
                ),
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 1200),
                      decoration: BoxDecoration(
                        color: ForumPalette.of(context).surface,
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: ForumPalette.of(context).line,
                          ),
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
                            VerticalDivider(width: 1),
                          ],
                          Expanded(
                            child: Column(
                              children: [
                                if (!wide && _showSearch)
                                  Padding(
                                    padding: EdgeInsets.all(16),
                                    child: TextField(
                                      controller: _search,
                                      onChanged: (v) =>
                                          setState(() => _query = v.trim()),
                                      onSubmitted: _searchSubmit,
                                      decoration: InputDecoration(
                                        labelText: '筛选已加载内容 / No.编号跳转',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: _onScroll,
                                    child: RefreshIndicator(
                                      key: Key('forum-refresh'),
                                      notificationPredicate: _canRefresh,
                                      onRefresh: () => _hasPrevious
                                          ? _loadPrevious()
                                          : _load(),
                                      child: CustomScrollView(
                                        key: Key('forum-scroll'),
                                        controller: _scroll,
                                        physics:
                                            AlwaysScrollableScrollPhysics(),
                                        slivers: [
                                          SliverToBoxAdapter(
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
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (_isThread && !compact)
                                                        TextButton.icon(
                                                          onPressed: () {
                                                            if (context
                                                                .canPop()) {
                                                              context.pop();
                                                            } else {
                                                              _navigate(
                                                                '/plate/${_thread?.plateId ?? 0}',
                                                              );
                                                            }
                                                          },
                                                          icon: Icon(
                                                            Icons.arrow_back,
                                                            size: 16,
                                                          ),
                                                          label: Text('返回列表'),
                                                        ),
                                                      Text(
                                                        eyebrow,
                                                        style: TextStyle(
                                                          color:
                                                              ForumPalette.of(
                                                                context,
                                                              ).accent,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      SizedBox(height: 14),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              title,
                                                              style: TextStyle(
                                                                fontSize:
                                                                    compact
                                                                    ? 31
                                                                    : 38,
                                                                height: 1.1,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                              ),
                                                            ),
                                                          ),
                                                          if (wide)
                                                            IconButton(
                                                              onPressed:
                                                                  _loading
                                                                  ? null
                                                                  : () =>
                                                                        _load(),
                                                              tooltip: '刷新',
                                                              icon: Icon(
                                                                Icons.refresh,
                                                                color:
                                                                    ForumPalette.of(
                                                                      context,
                                                                    ).muted,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      if (!_isThread) ...[
                                                        SizedBox(height: 12),
                                                        Text(
                                                          description,
                                                          style: TextStyle(
                                                            color:
                                                                ForumPalette.of(
                                                                  context,
                                                                ).muted,
                                                            height: 1.7,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                if (!_isThread && !_isMine)
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal:
                                                              horizontal,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              ForumPalette.of(
                                                                context,
                                                              ).line,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        _SortTab(
                                                          label:
                                                              widget.kind ==
                                                                  'sage'
                                                              ? '默认顺序'
                                                              : '最近回复',
                                                          selected: !_newest,
                                                          onTap: () => setState(
                                                            () =>
                                                                _newest = false,
                                                          ),
                                                        ),
                                                        SizedBox(width: 20),
                                                        _SortTab(
                                                          label: '页内最新发布',
                                                          selected: _newest,
                                                          onTap: () => setState(
                                                            () =>
                                                                _newest = true,
                                                          ),
                                                        ),
                                                        Spacer(),
                                                        Text(
                                                          '$_count 条',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color:
                                                                ForumPalette.of(
                                                                  context,
                                                                ).muted,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                if (_loading)
                                                  Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
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
                                                else if (_isMine &&
                                                    !auth.isLoggedIn)
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
                                                        style: TextStyle(
                                                          color:
                                                              ForumPalette.of(
                                                                context,
                                                              ).muted,
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
                                                      padding:
                                                          EdgeInsets.fromLTRB(
                                                            horizontal,
                                                            24,
                                                            horizontal,
                                                            12,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              '${(_count - 1).clamp(0, 1000000)} 个回复 · 第 $_pageRange 页',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                _load(
                                                                  last: true,
                                                                ),
                                                            child: Text(
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
                                                          ? '已加载内容中没有匹配项'
                                                          : _isThread
                                                          ? '这一页还没有回复'
                                                          : '这里暂时没有内容',
                                                      action: _query.isNotEmpty
                                                          ? '清除筛选'
                                                          : '刷新',
                                                      onTap: () {
                                                        if (_query.isNotEmpty) {
                                                          _search.clear();
                                                          setState(
                                                            () => _query = '',
                                                          );
                                                        } else {
                                                          _load();
                                                        }
                                                      },
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (!_loading &&
                                              _error == null &&
                                              !(_isMine &&
                                                  !auth.isLoggedIn)) ...[
                                            if (_count > 0)
                                              SliverToBoxAdapter(
                                                child: SizedBox(
                                                  height: 60,
                                                  child: Center(
                                                    child: _loadingPrevious
                                                        ? SizedBox(
                                                            key: Key(
                                                              'load-previous-progress',
                                                            ),
                                                            width: 20,
                                                            height: 20,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          )
                                                        : _previousError != null
                                                        ? TextButton(
                                                            key: Key(
                                                              'load-previous-retry',
                                                            ),
                                                            onPressed:
                                                                _loadPrevious,
                                                            child: Text(
                                                              '上一页加载失败，点击重试',
                                                            ),
                                                          )
                                                        : _hasPrevious
                                                        ? TextButton(
                                                            key: Key(
                                                              'load-previous-button',
                                                            ),
                                                            onPressed:
                                                                _loadPrevious,
                                                            child: Text(
                                                              '继续下拉，或点击加载上一页 ↑',
                                                            ),
                                                          )
                                                        : Text(
                                                            _previousExhausted
                                                                ? '没有更早的内容，下拉刷新'
                                                                : '已到第一页，下拉刷新',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  ForumPalette.of(
                                                                    context,
                                                                  ).muted,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            if (prepended != null)
                                              PrependSliver(
                                                compensate:
                                                    _pendingPrependPage ==
                                                    _prependPage,
                                                onAdjusted: () =>
                                                    _pendingPrependPage = null,
                                                key: ValueKey(
                                                  'prepend-$_prependPage',
                                                ),
                                                sliver: SliverToBoxAdapter(
                                                  child: pageView(prepended),
                                                ),
                                              ),
                                            SliverList.builder(
                                              key: ValueKey(
                                                'forward-$_prependPage',
                                              ),
                                              itemCount: lazyPages.length,
                                              itemBuilder: (context, index) =>
                                                  pageView(lazyPages[index]),
                                            ),
                                            if (_count > 0)
                                              SliverToBoxAdapter(
                                                child: Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                    horizontal,
                                                    24,
                                                    horizontal,
                                                    16,
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      if (_loadingMore)
                                                        Padding(
                                                          key: Key(
                                                            'load-more-progress',
                                                          ),
                                                          padding:
                                                              EdgeInsets.all(
                                                                12,
                                                              ),
                                                          child: SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          ),
                                                        )
                                                      else if (_moreError !=
                                                          null) ...[
                                                        Text(
                                                          _moreError!,
                                                          style: TextStyle(
                                                            color:
                                                                ForumPalette.of(
                                                                  context,
                                                                ).muted,
                                                          ),
                                                        ),
                                                        TextButton.icon(
                                                          key: Key(
                                                            'load-more-retry',
                                                          ),
                                                          onPressed: _loadMore,
                                                          icon: Icon(
                                                            Icons.refresh,
                                                            size: 16,
                                                          ),
                                                          label: Text(
                                                            '重试加载下一页',
                                                          ),
                                                        ),
                                                      ] else if (_hasMore)
                                                        TextButton(
                                                          key: Key(
                                                            'load-more-button',
                                                          ),
                                                          onPressed: _loadMore,
                                                          child: Text(
                                                            '继续上滑，或点击加载更多 ↓',
                                                          ),
                                                        )
                                                      else ...[
                                                        Padding(
                                                          key: Key(
                                                            'load-more-end',
                                                          ),
                                                          padding:
                                                              EdgeInsets.all(
                                                                12,
                                                              ),
                                                          child: Text(
                                                            '已经到底了',
                                                            style: TextStyle(
                                                              color:
                                                                  ForumPalette.of(
                                                                    context,
                                                                  ).muted,
                                                            ),
                                                          ),
                                                        ),
                                                        TextButton.icon(
                                                          key: const Key(
                                                            'end-refresh',
                                                          ),
                                                          onPressed: () {
                                                            if (!_loading) {
                                                              _load();
                                                            }
                                                          },
                                                          icon: const Icon(
                                                            Icons.refresh,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            '刷新',
                                                          ),
                                                        ),
                                                      ],
                                                      Text(
                                                        '已加载第 $_pageRange 页 · 共 $_pages 页',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              ForumPalette.of(
                                                                context,
                                                              ).muted,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                          SliverToBoxAdapter(
                                            child: SizedBox(
                                              height: shoreHeight + 60,
                                            ),
                                          ),
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
            key: Key('fab-compose'),
            onPressed: _isThread && (_loading || _thread == null)
                ? null
                : () => _compose(),
            backgroundColor: ForumColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(),
            elevation: 8,
            icon: Icon(Icons.add, size: 20),
            label: Text(
              _isThread ? '回复' : '发新串',
              style: TextStyle(fontWeight: FontWeight.w800),
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
    color: ForumPalette.of(context).surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            // Leave room to scroll the final links above the fixed shore.
            padding: EdgeInsets.fromLTRB(16, 24, 16, 176),
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '浏览',
                  style: TextStyle(
                    fontSize: 10,
                    color: ForumPalette.of(context).muted,
                  ),
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
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.symmetric(horizontal: 12),
                  title: Text(
                    '板块',
                    style: TextStyle(
                      fontSize: 10,
                      color: ForumPalette.of(context).muted,
                    ),
                  ),
                  children: [
                    boards.when(
                      loading: () => LinearProgressIndicator(),
                      error: (error, _) => TextButton(
                        onPressed: onRetry,
                        child: Text('板块加载失败，点击重试'),
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
              ForumExternalLinks(),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(28, 20, 28, 22),
          child: Text(
            'ISLANDER.TOP',
            style: TextStyle(
              fontSize: 10,
              color: ForumPalette.of(context).muted,
            ),
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
      constraints: BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? ForumPalette.of(context).soft : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selected
                ? ForumPalette.of(context).accent
                : Colors.transparent,
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
              style: TextStyle(
                fontSize: 10,
                color: ForumPalette.of(context).accent,
              ),
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
                    color: selected
                        ? ForumPalette.of(context).accent
                        : ForumPalette.of(context).ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: ForumPalette.of(context).muted,
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
            color: selected
                ? ForumPalette.of(context).accent
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? ForumPalette.of(context).accent
              : ForumPalette.of(context).muted,
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
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: ForumPalette.of(context).muted, height: 1.7),
        ),
        SizedBox(height: 12),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}
