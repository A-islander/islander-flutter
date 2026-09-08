import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'forum_motion.dart';

/// Predictive back progress is shared only with the reading pane, not chrome.
/// Uses public route APIs so PopScope, dialogs and system gesture cancellation
/// keep their normal behavior. No in-page drag recognizers are installed.
class ForumBackTransitionsBuilder extends PageTransitionsBuilder {
  const ForumBackTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(
    milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
  );

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _ForumBackTransition(
    route: route,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

class _ForumBackTransition extends StatefulWidget {
  const _ForumBackTransition({
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation, secondaryAnimation;
  final Widget child;

  @override
  State<_ForumBackTransition> createState() => _ForumBackTransitionState();
}

class _ForumBackTransitionState extends State<_ForumBackTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ValueNotifier<bool> _gestureInProgress;
  late final AnimationController _cancelController;
  bool _participating = false, _committing = false;
  double _commitStart = 0, _cancelStart = 0;

  @override
  void initState() {
    super.initState();
    _cancelController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 140),
          )
          ..addListener(() {
            if (!_participating || _committing) return;
            final remaining =
                _cancelStart *
                (1 - Curves.easeOutCubic.transform(_cancelController.value));
            widget.route.handleUpdateBackGestureProgress(
              progress: 1 - remaining,
            );
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed &&
                _participating &&
                !_committing) {
              widget.route.handleCancelBackGesture();
            }
          });
    _gestureInProgress = widget.route.navigator!.userGestureInProgressNotifier;
    _gestureInProgress.addListener(_gestureChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _gestureChanged() {
    if (!_gestureInProgress.value && _participating && mounted) {
      _cancelController.stop();
      setState(() {
        _participating = false;
        _committing = false;
      });
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (event.isButtonEvent ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    setState(() {
      _participating = true;
      _committing = false;
    });
    widget.route.handleStartBackGesture(progress: 1 - event.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (!_participating || _cancelController.isAnimating) return;
    // Only gesture progress is used; neither edge nor finger position moves it.
    widget.route.handleUpdateBackGestureProgress(progress: 1 - event.progress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_participating) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.route.handleUpdateBackGestureProgress(progress: 1);
      widget.route.handleCancelBackGesture();
      return;
    }
    _cancelStart = (1 - widget.animation.value).clamp(0.0, 1.0);
    _cancelController.forward(from: 0);
  }

  @override
  void handleCommitBackGesture() {
    if (!_participating || _cancelController.isAnimating) return;
    setState(() {
      // Flutter restarts the route's reverse animation at 1 on commit. Capture
      // the last gesture scale to avoid snapping back to full size first.
      _commitStart = (1 - widget.animation.value).clamp(0.0, 1.0);
      _committing = true;
    });
    // Reserve a full completion animation even if the gesture reached 100%.
    // The captured scale keeps this controller reset visually continuous.
    widget.route.handleUpdateBackGestureProgress(progress: 1);
    widget.route.handleCommitBackGesture();
  }

  @override
  void dispose() {
    _cancelController.dispose();
    _gestureInProgress.removeListener(_gestureChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.animation,
      widget.secondaryAnimation,
      _gestureInProgress,
    ]),
    child: widget.child,
    builder: (context, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return ForumBackMotion(child: child!);
      }
      if (!_gestureInProgress.value || !_participating) {
        final reverse = widget.animation.status == AnimationStatus.reverse;
        final progress = 1 - widget.animation.value;
        return ForumBackMotion(
          scale: reverse ? 1 - Curves.easeOutCubic.transform(progress) : 1,
          opacity: reverse
              ? 1 - Curves.easeIn.transform(progress)
              : Curves.easeOut.transform(widget.animation.value),
          radius: reverse ? 28 * progress : 0,
          blockInput: widget.animation.status != AnimationStatus.completed,
          child: child!,
        );
      }
      final progress = (1 - widget.animation.value).clamp(0.0, 1.0);
      final startScale = 1 - .08 * _commitStart;
      final scale = _committing
          ? startScale * (1 - Curves.easeOutCubic.transform(progress))
          : 1 - .08 * progress;
      return ForumBackMotion(
        scale: scale,
        opacity: _committing ? 1 - Curves.easeIn.transform(progress) : 1,
        radius:
            28 *
            Curves.easeOutCubic.transform(
              _committing
                  ? _commitStart + (1 - _commitStart) * progress
                  : progress,
            ),
        blockInput: true,
        child: child!,
      );
    },
  );
}
