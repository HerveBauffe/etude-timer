import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Anneau de progression du minuteur, avec contenu centré (chiffres + libellé).
class TimerRing extends StatelessWidget {
  final double progress; // 0..1
  final bool overtime;
  final Color? color;
  final double size;
  final Widget child;

  const TimerRing({
    super.key,
    required this.progress,
    required this.child,
    this.overtime = false,
    this.color,
    this.size = 280,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          track: scheme.surfaceContainerHighest,
          bar: overtime ? scheme.tertiary : (color ?? scheme.primary),
          overtime: overtime,
          overtimeOuter: scheme.tertiary,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color bar;
  final bool overtime;
  final Color overtimeOuter;

  _RingPainter({
    required this.progress,
    required this.track,
    required this.bar,
    required this.overtime,
    required this.overtimeOuter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final c = size.center(Offset.zero);
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = bar,
      );
    }
    if (overtime) {
      // Anneau extérieur en pointillés : lisible même en noir et blanc, sans dépendre de la couleur.
      final outerR = r + stroke / 2 + 7;
      const dots = 60;
      final p = Paint()..color = overtimeOuter;
      for (var i = 0; i < dots; i++) {
        final a = 2 * math.pi * i / dots;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * outerR, 1.8, p);
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.track != track || o.bar != bar || o.overtime != overtime;
}

/// Style des chiffres du minuteur.
TextStyle timerDigitsStyle(BuildContext context, {double size = 64}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w300,
      letterSpacing: -1,
      fontFeatures: tabularFigures,
      color: Theme.of(context).colorScheme.onSurface,
    );
