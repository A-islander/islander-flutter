import 'dart:math' as math;

import 'package:flutter/material.dart';

class PixelShore extends StatefulWidget {
  const PixelShore({super.key, required this.height});

  final double height;

  @override
  State<PixelShore> createState() => _PixelShoreState();
}

class _PixelShoreState extends State<PixelShore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.isAnimating) _controller.stop();
    if (!reduceMotion && !_controller.isAnimating) _controller.repeat();
    final shore = IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _PixelShorePainter(
              animation: _controller,
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      ),
    );
    return Theme.of(context).brightness == Brightness.dark
        ? ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFF819A94),
              BlendMode.modulate,
            ),
            child: shore,
          )
        : shore;
  }
}

class _PixelShorePainter extends CustomPainter {
  _PixelShorePainter({required this.animation, required this.reduceMotion})
    : super(repaint: reduceMotion ? null : animation);

  final Animation<double> animation;
  final bool reduceMotion;
  double get progress => reduceMotion ? .46 : animation.value;

  static const _seaDeep = Color(0xFF168E91);
  static const _seaLight = Color(0xFF9CE1D7);
  static const _foam = Color(0xFFFFF9DF);
  static const _sand = Color(0xFFEFD58F);
  static const _wetSand = Color(0xFFD2AD62);
  static const _sandLine = Color(0xFFB78E45);

  @override
  void paint(Canvas canvas, Size size) {
    final sandHeight = math.min(34.0, size.height * 0.3);
    final sandTop = size.height - sandHeight;
    final seaTop = 0.0;

    final seaRect = Rect.fromLTRB(0, seaTop, size.width, sandTop + 8);
    canvas.drawRect(
      seaRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x0043BDB6),
            Color(0x2A9CE1D7),
            Color(0xBA43BDB6),
          ],
          stops: <double>[0, 0.42, 1],
        ).createShader(seaRect),
    );

    _paintWaveTrain(canvas, size, sandTop);
    _paintGlints(canvas, size, sandTop);
    _paintSand(canvas, size, sandTop);
    _paintFoamWash(canvas, size, sandTop);
  }

  void _paintWaveTrain(Canvas canvas, Size size, double sandTop) {
    const spacing = 56.0;
    final travel = progress * spacing;
    final horizontalShift = (progress * 80).floorToDouble();

    for (double base = -spacing; base < sandTop; base += spacing) {
      final y = base + travel;
      if (y < 4 || y > sandTop + 4) continue;
      final visibility = (y / math.max(1, sandTop)).clamp(0.0, 1.0);
      _paintPixelLine(
        canvas,
        size.width,
        y,
        horizontalShift,
        _foam.withValues(alpha: 0.18 + visibility * 0.7),
        thickness: 4,
      );
      _paintPixelLine(
        canvas,
        size.width,
        y + 10,
        horizontalShift + 24,
        _seaLight.withValues(alpha: 0.18 + visibility * 0.42),
        thickness: 4,
      );
    }
  }

  void _paintGlints(Canvas canvas, Size size, double sandTop) {
    final light = Paint()
      ..isAntiAlias = false
      ..color = _foam.withValues(alpha: 0.44);
    final dark = Paint()
      ..isAntiAlias = false
      ..color = _seaDeep.withValues(alpha: 0.2);
    final shift = (progress * 48).floorToDouble();

    for (var row = 0; row < 3; row++) {
      final y = sandTop - 18 - row * 22 + (progress * 18 % 18);
      for (double x = -64; x < size.width + 64; x += 96) {
        final left = x - shift + row * 31;
        canvas.drawRect(Rect.fromLTWH(left, y, 24, 4), light);
        canvas.drawRect(Rect.fromLTWH(left + 42, y + 9, 16, 4), dark);
      }
    }
  }

  void _paintSand(Canvas canvas, Size size, double sandTop) {
    final wet = Paint()
      ..isAntiAlias = false
      ..color = _wetSand;
    final dry = Paint()
      ..isAntiAlias = false
      ..color = _sand;
    final grain = Paint()
      ..isAntiAlias = false
      ..color = _sandLine.withValues(alpha: 0.72);
    final highlight = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFFFFF0BD);

    canvas.drawRect(Rect.fromLTRB(0, sandTop, size.width, size.height), wet);
    for (double x = 0; x < size.width + 16; x += 32) {
      final step = ((x / 32).floor() % 4) * 2.0;
      canvas.drawRect(
        Rect.fromLTWH(x, sandTop + 5 + step, 34, size.height),
        dry,
      );
    }

    for (double x = 12; x < size.width; x += 78) {
      canvas.drawRect(Rect.fromLTWH(x, sandTop + 21, 10, 4), grain);
      canvas.drawRect(Rect.fromLTWH(x + 32, sandTop + 13, 4, 4), highlight);
    }
  }

  void _paintFoamWash(Canvas canvas, Size size, double sandTop) {
    final wash = (1 - math.cos(progress * math.pi * 2)) / 2;
    final frontY = sandTop - 7 + wash * 24;

    if (frontY > sandTop - 4) {
      canvas.drawRect(
        Rect.fromLTRB(0, sandTop - 4, size.width, frontY),
        Paint()
          ..isAntiAlias = false
          ..color = _seaLight.withValues(alpha: 0.48),
      );
    }

    _paintPixelLine(
      canvas,
      size.width,
      frontY,
      (progress * 104).floorToDouble(),
      _foam.withValues(alpha: 0.94),
      thickness: 4,
      detachedFoam: true,
    );
  }

  void _paintPixelLine(
    Canvas canvas,
    double width,
    double baseY,
    double shift,
    Color color, {
    required double thickness,
    bool detachedFoam = false,
  }) {
    const grid = 8.0;
    const offsets = <double>[0, -4, -4, 0, 4, 4, 0, -4, 0, 0, 4, 0];
    final paint = Paint()
      ..isAntiAlias = false
      ..color = color;
    final startIndex = (shift / grid).floor();

    for (double x = -grid; x < width + grid; x += grid) {
      final index = ((x / grid).floor() + startIndex) % offsets.length;
      final offset = offsets[index < 0 ? index + offsets.length : index];
      canvas.drawRect(Rect.fromLTWH(x, baseY + offset, grid, thickness), paint);
      if (detachedFoam && index % 4 == 0) {
        canvas.drawRect(
          Rect.fromLTWH(x + grid, baseY + offset + 9, grid * 1.5, thickness),
          paint..color = color.withValues(alpha: 0.62),
        );
        paint.color = color;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelShorePainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.reduceMotion != reduceMotion;
}
