import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/stats.dart';
import '../../core/util.dart';
import '../layout.dart';

/// Courbe « minutes étudiées par jour » dessinée à la main (aucune dépendance).
class MinutesLineChart extends StatefulWidget {
  final List<DayPoint> points;
  final double height;
  const MinutesLineChart({super.key, required this.points, this.height = 220});

  @override
  State<MinutesLineChart> createState() => _MinutesLineChartState();
}

class _MinutesLineChartState extends State<MinutesLineChart> {
  int? _hoverIndex;
  static const EdgeInsets pad = EdgeInsets.fromLTRB(40, 16, 16, 26);

  int _niceMax() {
    final m = widget.points.fold<int>(10, (a, p) => p.minutes > a ? p.minutes : a);
    return ((m / 30).ceil()) * 30;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pts = widget.points;
    if (pts.isEmpty) {
      return const SizedBox(height: 80, child: Center(child: Text('Pas encore de données pour cette période.')));
    }
    final hover = _hoverIndex != null && _hoverIndex! < pts.length ? pts[_hoverIndex!] : null;
    final hoverDate = hover == null ? null : parseDateKey(hover.date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Text(
            hover == null || hoverDate == null
                ? (isMobilePlatform ? 'Touche la courbe pour voir le détail' : 'Survole la courbe pour voir le détail')
                : '${hoverDate.day} ${monthsFrShort[hoverDate.month - 1]} ${hoverDate.year} — ${formatMinutesLabel(hover.minutes * 60)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          void pick(Offset pos) {
            final innerW = c.maxWidth - pad.left - pad.right;
            if (innerW <= 0) return;
            final f = ((pos.dx - pad.left) / innerW).clamp(0.0, 1.0);
            final i = pts.length == 1 ? 0 : (f * (pts.length - 1)).round();
            if (i != _hoverIndex) setState(() => _hoverIndex = i);
          }

          return MouseRegion(
            onExit: (_) => setState(() => _hoverIndex = null),
            onHover: (e) => pick(e.localPosition),
            child: GestureDetector(
              onTapDown: (d) => pick(d.localPosition),
              onHorizontalDragUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(
                size: Size(c.maxWidth, widget.height),
                painter: _LinePainter(
                  points: pts,
                  niceMax: _niceMax(),
                  hoverIndex: _hoverIndex,
                  line: scheme.primary,
                  grid: scheme.outlineVariant,
                  fill: scheme.primary.withValues(alpha: 0.14),
                  labelStyle: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<DayPoint> points;
  final int niceMax;
  final int? hoverIndex;
  final Color line;
  final Color grid;
  final Color fill;
  final TextStyle labelStyle;

  _LinePainter({
    required this.points,
    required this.niceMax,
    required this.hoverIndex,
    required this.line,
    required this.grid,
    required this.fill,
    required this.labelStyle,
  });

  void _text(Canvas canvas, String s, Offset anchor, {TextAlign align = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: labelStyle), textDirection: TextDirection.ltr)..layout();
    final dx = switch (align) {
      TextAlign.right => -tp.width,
      TextAlign.center => -tp.width / 2,
      _ => 0.0,
    };
    tp.paint(canvas, anchor + Offset(dx, -tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pad = _MinutesLineChartState.pad;
    final w = size.width - pad.left - pad.right;
    final h = size.height - pad.top - pad.bottom;
    double x(int i) => pad.left + (points.length == 1 ? w / 2 : i / (points.length - 1) * w);
    double y(num v) => pad.top + h - v / niceMax * h;

    // Grille + graduations
    const steps = 4;
    for (var i = 0; i <= steps; i++) {
      final v = niceMax / steps * i;
      final gy = y(v);
      canvas.drawLine(Offset(pad.left, gy), Offset(size.width - pad.right, gy), Paint()..color = grid..strokeWidth = 1);
      _text(canvas, '${v.round()}', Offset(pad.left - 8, gy), align: TextAlign.right);
    }

    // Aire + courbe
    final area = Path()..moveTo(x(0), y(0));
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      area.lineTo(x(i), y(points[i].minutes));
      if (i == 0) {
        path.moveTo(x(i), y(points[i].minutes));
      } else {
        path.lineTo(x(i), y(points[i].minutes));
      }
    }
    area.lineTo(x(points.length - 1), y(0));
    area.close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Étiquettes de l'axe X (~8 repères)
    final every = (points.length / 8).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < points.length; i++) {
      if (i % every == 0 || i == points.length - 1) {
        final d = parseDateKey(points[i].date);
        if (d != null) _text(canvas, '${d.day}/${d.month}', Offset(x(i), size.height - 8));
      }
    }

    // Point survolé
    final hi = hoverIndex;
    if (hi != null && hi < points.length) {
      canvas.drawLine(
        Offset(x(hi), pad.top),
        Offset(x(hi), pad.top + h),
        Paint()..color = line.withValues(alpha: 0.35)..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x(hi), y(points[hi].minutes)), 4.5, Paint()..color = line);
    } else if (points.length <= 60) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(Offset(x(i), y(points[i].minutes)), 2.2, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.points != points || o.hoverIndex != hoverIndex || o.line != line;
}
