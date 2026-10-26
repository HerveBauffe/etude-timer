import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/stats.dart';
import '../../core/util.dart';

/// Carte thermique façon « calendrier de contributions » (53 semaines, lundi en haut).
class Heatmap extends StatefulWidget {
  final Map<String, int> minutesByDate;
  final DateTime now;
  const Heatmap({super.key, required this.minutesByDate, required this.now});

  @override
  State<Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<Heatmap> {
  static const double cell = 13, gap = 3, leftGutter = 30, topGutter = 18;
  String? _hover;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Au premier affichage seulement : se placer sur la semaine courante (à droite).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _levelColor(ColorScheme s, int level) {
    if (level == 0) return s.surfaceContainerHighest;
    const mix = [0.0, 0.28, 0.5, 0.75, 1.0];
    return Color.lerp(s.surfaceContainerHighest, s.primary, mix[level])!;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grid = heatmapGrid(widget.now);
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final width = leftGutter + grid.length * (cell + gap);
    const height = topGutter + 7 * (cell + gap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Text(_hover ?? 'Survole une case pour voir le détail',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: MouseRegion(
            onExit: (_) => setState(() => _hover = null),
            onHover: (e) {
              final x = e.localPosition.dx - leftGutter;
              final y = e.localPosition.dy - topGutter;
              String? text;
              if (x >= 0 && y >= 0) {
                final w = (x / (cell + gap)).floor();
                final d = (y / (cell + gap)).floor();
                if (w >= 0 && w < grid.length && d >= 0 && d < 7) {
                  final day = grid[w][d];
                  if (!day.isAfter(today)) {
                    final k = dateKey(day);
                    text = '${weekdaysFrShort[day.weekday % 7]} ${day.day} ${monthsFrShort[day.month - 1]} ${day.year} — '
                        '${formatMinutesLabel((widget.minutesByDate[k] ?? 0) * 60)}';
                  }
                }
              }
              if (text != _hover) setState(() => _hover = text);
            },
            child: CustomPaint(
              size: Size(width, height),
              painter: _HeatPainter(
                grid: grid,
                today: today,
                minutes: widget.minutesByDate,
                colorFor: (l) => _levelColor(scheme, l),
                labelStyle: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Moins', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            for (var l = 0; l <= 4; l++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(color: _levelColor(scheme, l), borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 6),
            Text('Plus', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _HeatPainter extends CustomPainter {
  final List<List<DateTime>> grid;
  final DateTime today;
  final Map<String, int> minutes;
  final Color Function(int level) colorFor;
  final TextStyle labelStyle;

  _HeatPainter({
    required this.grid,
    required this.today,
    required this.minutes,
    required this.colorFor,
    required this.labelStyle,
  });

  void _text(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(text: TextSpan(text: s, style: labelStyle), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const cell = _HeatmapState.cell, gap = _HeatmapState.gap;
    const lg = _HeatmapState.leftGutter, tg = _HeatmapState.topGutter;
    // Jours : lun / mer / ven
    for (final d in [0, 2, 4]) {
      _text(canvas, weekdaysFrShort[(d + 1) % 7].replaceAll('.', ''), Offset(0, tg + d * (cell + gap) + 1));
    }
    var lastMonth = -1;
    for (var w = 0; w < grid.length; w++) {
      final first = grid[w].first;
      if (first.month != lastMonth && !first.isAfter(today)) {
        lastMonth = first.month;
        _text(canvas, monthsFrShort[first.month - 1], Offset(lg + w * (cell + gap), 0));
      }
      for (var d = 0; d < 7; d++) {
        final day = grid[w][d];
        if (day.isAfter(today)) continue;
        final level = heatLevel(minutes[dateKey(day)] ?? 0);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(lg + w * (cell + gap), tg + d * (cell + gap), cell, cell),
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = colorFor(level));
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter o) => o.minutes != minutes || o.today != today || o.labelStyle != labelStyle;
}
