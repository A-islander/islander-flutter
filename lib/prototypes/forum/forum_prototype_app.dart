import 'package:flutter/material.dart';

import 'forum_models.dart';
import '../../shared/widgets/pixel_shore.dart';

const _accent = Color(0xFF007A73);
const _accentSoft = Color(0xFFE1F2F0);
const _canvas = Color(0xFFF2F3F1);
const _surface = Colors.white;
const _ink = Color(0xFF171918);
const _muted = Color(0xFF626765);
const _line = Color(0xFFDFE2DF);
const _lineStrong = Color(0xFFC9CECA);
const _wideBreakpoint = 1024.0;

class ForumPrototypeApp extends StatelessWidget {
  const ForumPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '岛民岛 · Flutter 论坛原型',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _canvas,
        colorScheme: const ColorScheme.light(
          primary: _accent,
          onPrimary: Colors.white,
          surface: _surface,
          onSurface: _ink,
          outline: _lineStrong,
        ),
        dividerColor: _line,
        fontFamilyFallback: const <String>[
          'Noto Sans CJK SC',
          'Source Han Sans SC',
          'PingFang SC',
        ],
        appBarTheme: const AppBarTheme(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(_accent),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            overlayColor: WidgetStatePropertyAll(
              Colors.white.withValues(alpha: 0.1),
            ),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: _lineStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: _lineStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: _accent, width: 2),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _ink,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      home: const ForumPrototypeScreen(),
    );
  }
}

enum _ForumView { timeline, sage, board, thread }

enum _SortMode { active, newest }

class ForumPrototypeScreen extends StatefulWidget {
  const ForumPrototypeScreen({super.key});

  @override
  State<ForumPrototypeScreen> createState() => _ForumPrototypeScreenState();
}

class _ForumPrototypeScreenState extends State<ForumPrototypeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  late final List<ForumThread> _threads = buildForumThreads();

  _ForumView _view = _ForumView.timeline;
  _SortMode _sortMode = _SortMode.active;
  int _selectedBoardId = 1;
  int _activeThreadId = 1842;
  String _query = '';

  ForumBoard get _activeBoard => forumBoards.firstWhere(
    (board) => board.id == _selectedBoardId,
    orElse: () => forumBoards.first,
  );

  ForumThread get _activeThread => _threads.firstWhere(
    (thread) => thread.id == _activeThreadId,
    orElse: () => _threads.first,
  );

  List<ForumThread> get _visibleThreads {
    Iterable<ForumThread> result = _threads;
    if (_view == _ForumView.board) {
      result = result.where((thread) => thread.boardId == _selectedBoardId);
    } else if (_view == _ForumView.sage) {
      result = result.where((thread) => thread.sage > 0);
    }

    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where(
        (thread) => '${thread.id} ${thread.title} ${thread.body}'
            .toLowerCase()
            .contains(query),
      );
    }

    final items = result.toList();
    return _sortMode == _SortMode.newest ? items.reversed.toList() : items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigate(_ForumView view, {int? boardId}) {
    setState(() {
      _view = view;
      if (boardId != null) _selectedBoardId = boardId;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _openThread(ForumThread thread) {
    setState(() {
      _activeThreadId = thread.id;
      _selectedBoardId = thread.boardId;
      _view = _ForumView.thread;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openComposer({int? quoteId}) async {
    final isReply = _view == _ForumView.thread;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final result = await showModalBottomSheet<_ComposerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      showDragHandle: false,
      barrierColor: _ink.withValues(alpha: 0.42),
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(width: viewportWidth),
      builder: (context) => _ComposerSheet(
        isReply: isReply,
        board: _activeBoard,
        thread: isReply ? _activeThread : null,
        initialBody: quoteId == null ? '' : 'No.$quoteId ',
      ),
    );

    if (result == null || !mounted) return;
    if (result.isReply) {
      final allIds = _threads
          .expand(
            (thread) => <int>[
              thread.id,
              ...thread.samples.map((reply) => reply.id),
            ],
          )
          .toList();
      final nextId = allIds.reduce((a, b) => a > b ? a : b) + 1;
      setState(() {
        _activeThread.samples.add(
          ForumReply(
            id: nextId,
            author: '海盐-42',
            time: '刚刚',
            body: result.body,
          ),
        );
        _activeThread.replies += 1;
        _activeThread.lastReply = 'No.$nextId';
      });
      _showMessage('已回复 No.${_activeThread.id}');
      return;
    }

    final nextId =
        _threads.map((thread) => thread.id).reduce((a, b) => a > b ? a : b) + 1;
    setState(() {
      _threads.insert(
        0,
        ForumThread(
          id: nextId,
          boardId: _selectedBoardId,
          author: '海盐-42',
          time: '刚刚',
          title: result.title.trim().isEmpty ? '无标题串' : result.title.trim(),
          body: result.body,
          replies: 0,
          lastReply: 'No.$nextId',
          sage: 0,
          samples: <ForumReply>[],
        ),
      );
    });
    _showMessage('No.$nextId 已发布');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        final shoreHeight = isWide ? 152.0 : 112.0;

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 64,
            titleSpacing: 0,
            title: _TopBar(
              isWide: isWide,
              searchController: _searchController,
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onHome: () => _navigate(_ForumView.timeline),
              onSearch: (value) => setState(() => _query = value),
              onCookie: () => _showMessage('当前饼干：海盐-42'),
            ),
          ),
          drawer: isWide
              ? null
              : Drawer(
                  width: 304,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  child: SafeArea(
                    child: _Sidebar(
                      view: _view,
                      selectedBoardId: _selectedBoardId,
                      onNavigate: _navigate,
                      onBar: () {
                        _scaffoldKey.currentState?.closeDrawer();
                        _showMessage('海浪之家暂不在本原型范围内');
                      },
                    ),
                  ),
                ),
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    decoration: const BoxDecoration(
                      color: _surface,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x12102220),
                          blurRadius: 44,
                          offset: Offset(0, 18),
                        ),
                      ],
                      border: Border.symmetric(
                        vertical: BorderSide(color: _line),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (isWide) ...<Widget>[
                          SizedBox(
                            width: 240,
                            child: _Sidebar(
                              view: _view,
                              selectedBoardId: _selectedBoardId,
                              onNavigate: _navigate,
                              onBar: () => _showMessage('海浪之家暂不在本原型范围内'),
                            ),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                        ],
                        Expanded(
                          child: _view == _ForumView.thread
                              ? _ThreadPage(
                                  thread: _activeThread,
                                  board: _activeBoard,
                                  bottomPadding: shoreHeight + 28,
                                  onBackToBoard: () => _navigate(
                                    _ForumView.board,
                                    boardId: _activeThread.boardId,
                                  ),
                                  onQuote: (id) => _openComposer(quoteId: id),
                                )
                              : _ThreadListPage(
                                  view: _view,
                                  board: _activeBoard,
                                  threads: _visibleThreads,
                                  sortMode: _sortMode,
                                  bottomPadding: shoreHeight + 28,
                                  onSort: (mode) =>
                                      setState(() => _sortMode = mode),
                                  onOpenThread: _openThread,
                                  onClearSearch: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
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
          floatingActionButton: SizedBox(
            height: 52,
            child: FloatingActionButton.extended(
              key: const Key('fab-compose'),
              onPressed: _openComposer,
              elevation: 8,
              highlightElevation: 4,
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              icon: const Icon(Icons.add, size: 19),
              label: Text(
                _view == _ForumView.thread ? '回复' : '发新串',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isWide,
    required this.searchController,
    required this.onMenu,
    required this.onHome,
    required this.onSearch,
    required this.onCookie,
  });

  final bool isWide;
  final TextEditingController searchController;
  final VoidCallback onMenu;
  final VoidCallback onHome;
  final ValueChanged<String> onSearch;
  final VoidCallback onCookie;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                if (!isWide)
                  IconButton(
                    onPressed: onMenu,
                    tooltip: '打开导航',
                    color: Colors.white,
                    icon: const Icon(Icons.menu, size: 21),
                  ),
                TextButton(
                  onPressed: onHome,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _WaveMark(),
                      SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '岛民岛',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.8,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'ISLANDER FORUM',
                            style: TextStyle(
                              color: Color(0xA8FFFFFF),
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isWide)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 448),
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearch,
                        cursorColor: Colors.white,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: '搜索标题、正文或 No.',
                          hintStyle: const TextStyle(color: Color(0x99FFFFFF)),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xC4FFFFFF),
                            size: 18,
                          ),
                          suffixText: '/',
                          suffixStyle: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontFamily: 'monospace',
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: Color(0x55FFFFFF)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 9,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: onCookie,
                  child: Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0xC8FFFFFF), width: 2),
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '当前饼干',
                          style: TextStyle(
                            color: Color(0xA8FFFFFF),
                            fontSize: 10,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '海盐-42',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
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
    );
  }
}

class _WaveMark extends StatelessWidget {
  const _WaveMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        children: <Widget>[
          Positioned(left: 0, top: 4, child: _MarkLine(width: 32)),
          Positioned(left: 8, top: 13, child: _MarkLine(width: 24)),
          Positioned(left: 0, top: 22, child: _MarkLine(width: 12)),
        ],
      ),
    );
  }
}

class _MarkLine extends StatelessWidget {
  const _MarkLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) =>
      Container(width: width, height: 2, color: Colors.white);
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.view,
    required this.selectedBoardId,
    required this.onNavigate,
    required this.onBar,
  });

  final _ForumView view;
  final int selectedBoardId;
  final void Function(_ForumView view, {int? boardId}) onNavigate;
  final VoidCallback onBar;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  bool _boardsOpen = true;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              children: <Widget>[
                const _SidebarLabel('浏览'),
                const SizedBox(height: 10),
                _SidebarItem(
                  index: '01',
                  label: '时间线',
                  selected: widget.view == _ForumView.timeline,
                  onTap: () => widget.onNavigate(_ForumView.timeline),
                ),
                _SidebarItem(
                  index: '02',
                  label: 'SAGE 串',
                  selected: widget.view == _ForumView.sage,
                  onTap: () => widget.onNavigate(_ForumView.sage),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1),
                ),
                InkWell(
                  onTap: () => setState(() => _boardsOpen = !_boardsOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: <Widget>[
                        const Expanded(child: _SidebarLabel('板块')),
                        Icon(
                          _boardsOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 17,
                          color: _muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_boardsOpen)
                  ...forumBoards.map(
                    (board) => _BoardItem(
                      board: board,
                      selected:
                          widget.view == _ForumView.board &&
                          widget.selectedBoardId == board.id,
                      onTap: () => widget.onNavigate(
                        _ForumView.board,
                        boardId: board.id,
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1),
                ),
                InkWell(
                  onTap: widget.onBar,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '海浪之家酒吧',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        ),
                        Text('↗', style: TextStyle(color: _muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 20, 28, 22),
              child: Text(
                'ISLANDER.TOP',
                style: TextStyle(
                  color: _muted,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _muted,
      fontFamily: 'monospace',
      fontSize: 10,
      letterSpacing: 0.2,
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? _accentSoft : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Text(
                index,
                style: TextStyle(
                  color: selected ? _accent : _muted,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: selected ? _accent : _muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardItem extends StatelessWidget {
  const _BoardItem({
    required this.board,
    required this.selected,
    required this.onTap,
  });

  final ForumBoard board;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(width: 6, height: 6, color: _accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    board.name,
                    style: TextStyle(
                      color: selected ? _accent : _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    board.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadListPage extends StatelessWidget {
  const _ThreadListPage({
    required this.view,
    required this.board,
    required this.threads,
    required this.sortMode,
    required this.bottomPadding,
    required this.onSort,
    required this.onOpenThread,
    required this.onClearSearch,
  });

  final _ForumView view;
  final ForumBoard board;
  final List<ForumThread> threads;
  final _SortMode sortMode;
  final double bottomPadding;
  final ValueChanged<_SortMode> onSort;
  final ValueChanged<ForumThread> onOpenThread;
  final VoidCallback onClearSearch;

  String get _title => switch (view) {
    _ForumView.board => board.name,
    _ForumView.sage => 'SAGE 串',
    _ => '时间线',
  };

  String get _eyebrow => switch (view) {
    _ForumView.board => 'BOARD',
    _ForumView.sage => 'MODERATION',
    _ => 'LATEST ACTIVITY',
  };

  String get _description => switch (view) {
    _ForumView.board => board.description,
    _ForumView.sage => '正在被社区讨论是否沉底的内容',
    _ => '全岛最近有回应的串',
  };

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final horizontal = compact ? 20.0 : 36.0;

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 38, horizontal, 38),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _eyebrow,
                style: const TextStyle(
                  color: _accent,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _title,
                style: TextStyle(
                  color: _ink,
                  fontSize: compact ? 31 : 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _description,
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        _SortBar(
          mode: sortMode,
          count: threads.length,
          horizontalPadding: horizontal,
          onSort: onSort,
        ),
        if (threads.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 72),
            child: Column(
              children: <Widget>[
                const Text(
                  '没有找到对应的串',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                TextButton(onPressed: onClearSearch, child: const Text('清除搜索')),
              ],
            ),
          )
        else
          ...threads.map(
            (thread) => _ThreadRow(
              key: Key('thread-${thread.id}'),
              thread: thread,
              board: forumBoards.firstWhere(
                (board) => board.id == thread.boardId,
              ),
              horizontalPadding: horizontal,
              onTap: () => onOpenThread(thread),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 8),
          child: const Row(
            children: <Widget>[
              _PageButton(label: '←'),
              SizedBox(width: 4),
              _PageButton(label: '1', selected: true),
              SizedBox(width: 4),
              _PageButton(label: '2'),
              SizedBox(width: 4),
              _PageButton(label: '3'),
              SizedBox(width: 4),
              _PageButton(label: '→'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.mode,
    required this.count,
    required this.horizontalPadding,
    required this.onSort,
  });

  final _SortMode mode;
  final int count;
  final double horizontalPadding;
  final ValueChanged<_SortMode> onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 49,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: <Widget>[
          _SortButton(
            label: '最近回应',
            selected: mode == _SortMode.active,
            onTap: () => onSort(_SortMode.active),
          ),
          const SizedBox(width: 24),
          _SortButton(
            label: '最新发布',
            selected: mode == _SortMode.newest,
            onTap: () => onSort(_SortMode.newest),
          ),
          const Spacer(),
          Text(
            '$count 条串',
            style: const TextStyle(
              color: _muted,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 49,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _accent : _muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    super.key,
    required this.thread,
    required this.board,
    required this.horizontalPadding,
    required this.onTap,
  });

  final ForumThread thread;
  final ForumBoard board;
  final double horizontalPadding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStatePropertyAll(_accent.withValues(alpha: 0.045)),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            26,
            horizontalPadding,
            26,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _BoardTag(board.name),
                        Text(
                          thread.author,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _MetaText(thread.time),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      thread.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 20,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      thread.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 14,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: <Widget>[
                        _MetaText('${thread.replies} 个回应'),
                        _MetaText('最后 ${thread.lastReply}'),
                        if (thread.sage > 0) _MetaText('SAGE ${thread.sage}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _NumberButton(label: 'No.${thread.id}', onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardTag extends StatelessWidget {
  const _BoardTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _accentSoft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: _accent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontFamily: 'monospace',
      fontSize: 10,
    ),
  );
}

class _NumberButton extends StatelessWidget {
  const _NumberButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: _muted,
      side: const BorderSide(color: _line),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 10),
    ),
    child: Text(label),
  );
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: selected ? _accent : Colors.transparent,
      border: selected ? null : Border.all(color: _line),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : _muted,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
  );
}

class _ThreadPage extends StatelessWidget {
  const _ThreadPage({
    required this.thread,
    required this.board,
    required this.bottomPadding,
    required this.onBackToBoard,
    required this.onQuote,
  });

  final ForumThread thread;
  final ForumBoard board;
  final double bottomPadding;
  final VoidCallback onBackToBoard;
  final ValueChanged<int> onQuote;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final horizontal = compact ? 20.0 : 36.0;

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: <Widget>[
        Container(
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: <Widget>[
              TextButton(
                onPressed: onBackToBoard,
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  board.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('/', style: TextStyle(color: _muted)),
              ),
              _MetaText('No.${thread.id}'),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(horizontal, 34, horizontal, 30),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _BoardTag(board.name),
                  Text(
                    thread.author,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _MetaText(thread.time),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                thread.title,
                style: TextStyle(
                  color: _ink,
                  fontSize: compact ? 25 : 31,
                  height: 1.28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                thread.body,
                style: const TextStyle(color: _ink, fontSize: 15, height: 2),
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  _MetaText('${thread.replies} 个回应'),
                  const SizedBox(width: 16),
                  _MetaText('SAGE ${thread.sage}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => onQuote(thread.id),
                    child: Text(
                      '引用 No.${thread.id}',
                      style: const TextStyle(
                        color: _accent,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ...thread.samples.map(
          (reply) => Container(
            padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      reply.author,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MetaText(reply.time),
                    const Spacer(),
                    TextButton(
                      onPressed: () => onQuote(reply.id),
                      child: Text(
                        'No.${reply.id}',
                        style: const TextStyle(
                          color: _accent,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reply.body,
                  style: const TextStyle(fontSize: 14, height: 1.8),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposerResult {
  const _ComposerResult({
    required this.isReply,
    required this.title,
    required this.body,
  });

  final bool isReply;
  final String title;
  final String body;
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({
    required this.isReply,
    required this.board,
    required this.thread,
    required this.initialBody,
  });

  final bool isReply;
  final ForumBoard board;
  final ForumThread? thread;
  final String initialBody;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController(text: widget.initialBody);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isReply) {
        _bodyFocus.requestFocus();
        _bodyController.selection = TextSelection.collapsed(
          offset: _bodyController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isReply ? '回复内容不能为空' : '请先写下正文')),
      );
      return;
    }
    Navigator.of(context).pop(
      _ComposerResult(
        isReply: widget.isReply,
        title: _titleController.text,
        body: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        key: const Key('composer-sheet-surface'),
        color: _surface,
        child: SafeArea(
          top: false,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _accent, width: 2)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          color: _lineStrong,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.isReply
                                      ? 'REPLY · NO.${widget.thread!.id}'
                                      : 'NEW THREAD · ${widget.board.name}',
                                  style: const TextStyle(
                                    color: _accent,
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  widget.isReply ? '写下回复' : '发布新串',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _muted,
                              side: const BorderSide(color: _line),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (!widget.isReply) ...<Widget>[
                        const Text(
                          '标题',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('composer-title'),
                          controller: _titleController,
                          autofocus: true,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            hintText: '标题（可选）',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '正文',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        key: const Key('composer-body'),
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        minLines: widget.isReply ? 5 : 4,
                        maxLines: 9,
                        decoration: InputDecoration(
                          hintText: widget.isReply
                              ? '写下回应，输入 No.编号 可以引用'
                              : '写下想和岛民讨论的内容',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          if (widget.isReply)
                            OutlinedButton(
                              onPressed: () {
                                final selection = _bodyController.selection;
                                final position = selection.isValid
                                    ? selection.end
                                    : _bodyController.text.length;
                                final value = _bodyController.text;
                                _bodyController.text =
                                    '${value.substring(0, position)}(´▽｀) ${value.substring(position)}';
                                _bodyController.selection =
                                    TextSelection.collapsed(
                                      offset: position + 7,
                                    );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _muted,
                                side: const BorderSide(color: _line),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                minimumSize: const Size(78, 44),
                              ),
                              child: const Text(
                                '颜文字',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            const Expanded(
                              child: Text(
                                '最多 5 个媒体 · 单项 20 MB',
                                style: TextStyle(
                                  color: _muted,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          if (widget.isReply) const Spacer(),
                          FilledButton(
                            key: const Key('composer-submit'),
                            onPressed: _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(112, 44),
                            ),
                            child: Text(widget.isReply ? '发布回复' : '发布新串'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
