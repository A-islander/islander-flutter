import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/widgets/pixel_shore.dart';

/// Only the reading pane consumes this scope. Chrome is never transformed.
class ForumBackMotion extends InheritedWidget {
  const ForumBackMotion({
    super.key,
    required super.child,
    this.scale = 1,
    this.opacity = 1,
    this.radius = 0,
    this.blockInput = false,
  });
  final double scale, opacity, radius;
  final bool blockInput;
  static ForumBackMotion? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumBackMotion>();
  @override
  bool updateShouldNotify(ForumBackMotion old) =>
      scale != old.scale ||
      opacity != old.opacity ||
      radius != old.radius ||
      blockInput != old.blockInput;
}

class ForumReadingTransition extends StatelessWidget {
  const ForumReadingTransition({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final motion = ForumBackMotion.of(context);
    if (motion == null || MediaQuery.disableAnimationsOf(context)) return child;
    return IgnorePointer(
      ignoring: motion.blockInput,
      child: Opacity(
        opacity: motion.opacity,
        child: Transform.scale(
          key: const ValueKey('forum-reading-scale'),
          scale: motion.scale,
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(motion.radius),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The outgoing page must not double-paint translucent waves under the next one.
class ForumCurrentShore extends StatelessWidget {
  const ForumCurrentShore({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: forumMotionObserver.page,
      child: PixelShore(height: height),
      builder: (_, page, child) => Visibility(
        visible: page == null || page == route,
        maintainState: true,
        child: child!,
      ),
    );
  }
}

class ForumMotionObserver extends NavigatorObserver {
  final top = ValueNotifier<Route<dynamic>?>(null);
  final page = ValueNotifier<Route<dynamic>?>(null);
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    top.value = topRoute;
    if (topRoute is PageRoute) page.value = topRoute;
  }
}

final forumMotionObserver = ForumMotionObserver();

class _FabRegistry extends ChangeNotifier {
  final entries = <Route<dynamic>, Widget>{};
  final hidden = <Route<dynamic>>{};
  bool _disposed = false;
  void put(Route<dynamic> route, Widget? child, {bool hide = false}) {
    if (_disposed) return;
    if (child == null) {
      entries.remove(route);
    } else {
      entries[route] = child;
    }
    if (hide) {
      hidden.add(route);
    } else {
      hidden.remove(route);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    entries.clear();
    hidden.clear();
    super.dispose();
  }
}

class _FabScope extends InheritedWidget {
  const _FabScope({required this.registry, required super.child});
  final _FabRegistry registry;
  @override
  bool updateShouldNotify(_FabScope old) => registry != old.registry;
}

/// Publishes a route's action without moving it with the reading pane or Heroes.
class ForumFabSlot extends StatefulWidget {
  const ForumFabSlot({super.key, required this.child, this.hidden = false});
  final Widget? child;
  final bool hidden;
  @override
  State<ForumFabSlot> createState() => _ForumFabSlotState();
}

class _ForumFabSlotState extends State<ForumFabSlot> {
  _FabRegistry? _registry;
  Route<dynamic>? _route;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry = context
        .dependOnInheritedWidgetOfExactType<_FabScope>()
        ?.registry;
    _route = ModalRoute.of(context);
    _publish();
  }

  @override
  void didUpdateWidget(ForumFabSlot old) {
    super.didUpdateWidget(old);
    _publish();
  }

  void _publish() {
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && _route != null) {
        _registry?.put(_route!, widget.child, hide: widget.hidden);
      }
    });
  }

  @override
  void dispose() {
    final registry = _registry;
    final route = _route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null) registry?.put(route, null);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _registry == null
      ? widget.child ?? const SizedBox.shrink()
      : const SizedBox.shrink();
}

/// Linear amplitude envelope, two small horizontal oscillations, exact rest.
double forumFabBounce(double t) =>
    t <= 0 || t >= 1 ? 0 : -6 * (1 - t) * math.sin(4 * math.pi * t);

class _FabFlight extends StatefulWidget {
  const _FabFlight({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;
  @override
  State<_FabFlight> createState() => _FabFlightState();
}

class _FabFlightState extends State<_FabFlight> {
  double _exitStart = 1, _exitSlide = 0, _exitBounce = 0;
  double _entry(double value) => ((value * 320 - 60) / 260).clamp(0.0, 1.0);
  double _slide(double value) =>
      1.3 *
      (1 - Curves.easeOutCubic.transform((_entry(value) / .4).clamp(0.0, 1.0)));
  double _bounce(double value) =>
      forumFabBounce(((_entry(value) - .4) / .6).clamp(0.0, 1.0));
  void _status(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _exitStart = widget.animation.value;
      _exitSlide = _slide(_exitStart);
      _exitBounce = _bounce(_exitStart);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_status);
  }

  @override
  void didUpdateWidget(_FabFlight old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_status);
      widget.animation.addStatusListener(_status);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final exiting = widget.animation.status == AnimationStatus.reverse;
        final t = widget.animation.value;
        final slide = exiting ? _exitSlide : _slide(t);
        final bounce = exiting ? _exitBounce : _bounce(t);
        final down = exiting
            ? (1 - t / math.max(_exitStart, .00001)) *
                  (96 +
                      MediaQuery.paddingOf(context).bottom +
                      MediaQuery.viewInsetsOf(context).bottom)
            : 0.0;
        return IgnorePointer(
          ignoring: exiting || t < 1,
          child: ExcludeSemantics(
            excluding: exiting,
            child: FractionalTranslation(
              translation: Offset(slide, 0),
              child: Transform.translate(
                offset: Offset(bounce, down),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single overlay owns the outgoing and incoming actions across page routes.
/// It is hidden (not animated over) drawers/dialogs/sheets and has no Hero flight.
class ForumMotionHost extends StatefulWidget {
  const ForumMotionHost({super.key, required this.child});
  final Widget child;
  @override
  State<ForumMotionHost> createState() => _ForumMotionHostState();
}

class _ForumMotionHostState extends State<ForumMotionHost> {
  final _registry = _FabRegistry();
  Route<dynamic>? _page;
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    forumMotionObserver.top.addListener(_refresh);
    _registry.addListener(_refresh);
  }

  void _refresh() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    forumMotionObserver.top.removeListener(_refresh);
    _registry.removeListener(_refresh);
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = forumMotionObserver.top.value;
    if (top is PageRoute) _page = top;
    final fab = _registry.entries[_page];
    final reduce = MediaQuery.disableAnimationsOf(context);
    return PixelShoreClock(
      child: _FabScope(
        registry: _registry,
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            Positioned(
              right: 16,
              bottom:
                  16 +
                  MediaQuery.paddingOf(context).bottom +
                  MediaQuery.viewInsetsOf(context).bottom,
              child: Offstage(
                offstage: top is! PageRoute || _registry.hidden.contains(_page),
                child: ValueListenableBuilder<bool>(
                  valueListenable:
                      _page?.navigator?.userGestureInProgressNotifier ??
                      const AlwaysStoppedAnimation(false),
                  builder: (_, busy, child) =>
                      IgnorePointer(ignoring: busy, child: child),
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 320),
                    reverseDuration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    transitionBuilder: (child, animation) =>
                        _FabFlight(animation: animation, child: child),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomRight,
                      clipBehavior: Clip.none,
                      children: [...previous, ?current],
                    ),
                    child: fab == null
                        ? null
                        : KeyedSubtree(key: ObjectKey(_page), child: fab),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
