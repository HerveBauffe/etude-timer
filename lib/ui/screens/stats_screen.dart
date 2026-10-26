import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/models.dart';
import '../../core/stats.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/heatmap.dart';
import '../widgets/line_chart.dart';

class StatsScreen extends StatefulWidget {
  final AppController c;
  const StatsScreen({super.key, required this.c});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _rangeDays = 90;
  late int _year;
  late int _month;

  AppController get c => widget.c;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _year = n.year;
    _month = n.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month < 1) {
        _month = 12;
        _year--;
      } else if (_month > 12) {
        _month = 1;
        _year++;
      }
    });
  }

  List<({String? id, String label})> _courseOptions() {
    final d = c.store.data;
    final out = <({String? id, String label})>[(id: null, label: 'Tous les cours')];
    final items = [
      for (final x in d.courses) (id: x.id, label: c.courseLabel(x.id)),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    out.addAll(items);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sessions = workSessions(c.store.data, courseId: c.statsCourseId);
    final cards = summaryCards(sessions, now);
    final byDate = minutesByDate(sessions);
    final series = dailySeries(sessions, _rangeDays, now);
    final weeks = monthWeeks(sessions, _year, _month);
    final monthTotal = monthTotalSeconds(sessions, _year, _month);
    final blocus = blocusRows(sessions, c.store.data.blocus);
    final options = _courseOptions();

    Widget section(String title, {Widget? trailing, required Widget child}) => Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(children: [
                  Expanded(child: Text(title, style: text.titleMedium)),
                  if (trailing != null) trailing,
                ]),
              ),
              Card(color: scheme.surfaceContainerLow, child: Padding(padding: const EdgeInsets.all(16), child: child)),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statistiques', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text('Ton temps de travail effectif (les pauses ne sont pas comptées).',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              DropdownMenu<String?>(
                key: ValueKey(c.statsCourseId),
                width: 360,
                initialSelection: c.statsCourseId,
                label: const Text('Filtrer par cours'),
                leadingIcon: const Icon(Icons.filter_list),
                dropdownMenuEntries: [
                  for (final o in options) DropdownMenuEntry<String?>(value: o.id, label: o.label),
                ],
                onSelected: (v) => c.setStatsCourse(v),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth >= 640 ? 3 : 1;
                final w = (box.maxWidth - (cols - 1) * 12) / cols;
                Widget card(String label, int secs) => SizedBox(
                      width: w,
                      child: Card(
                        color: scheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: text.labelLarge?.copyWith(color: scheme.onSecondaryContainer)),
                            const SizedBox(height: 6),
                            Text(formatMinutesLabel(secs),
                                style: text.headlineMedium?.copyWith(color: scheme.onSecondaryContainer, fontFeatures: tabularFigures)),
                          ]),
                        ),
                      ),
                    );
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  card("Aujourd'hui", cards.todaySeconds),
                  card('Cette semaine', cards.weekSeconds),
                  card('Ce mois-ci', cards.monthSeconds),
                ]);
              }),
              section("Activité de l'année", child: Heatmap(minutesByDate: byDate, now: now)),
              section(
                'Minutes étudiées par jour',
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30 j')),
                    ButtonSegment(value: 90, label: Text('90 j')),
                    ButtonSegment(value: 365, label: Text('365 j')),
                  ],
                  selected: {_rangeDays},
                  onSelectionChanged: (s) => setState(() => _rangeDays = s.first),
                ),
                child: MinutesLineChart(points: series),
              ),
              section(
                'Détail mensuel',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Mois précédent', icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
                  SizedBox(
                    width: 140,
                    child: Text(monthLabel(_year, _month - 1), textAlign: TextAlign.center, style: text.titleSmall),
                  ),
                  IconButton(tooltip: 'Mois suivant', icon: const Icon(Icons.chevron_right), onPressed: () => _shiftMonth(1)),
                ]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Total du mois : ', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    TextSpan(text: formatMinutesLabel(monthTotal), style: text.titleMedium),
                  ])),
                  const SizedBox(height: 12),
                  if (weeks.isEmpty)
                    Text('Aucune activité ce mois-ci.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
                  else
                    Table(
                      columnWidths: const {0: FixedColumnWidth(80), 2: IntrinsicColumnWidth()},
                      children: [
                        _headerRow(context, const ['Semaine', 'Période', 'Temps']),
                        for (final w in weeks)
                          _row(context, [w.label, '${shortDate(w.from)} – ${shortDate(w.to)}', formatMinutesLabel(w.seconds)]),
                      ],
                    ),
                ]),
              ),
              section(
                'Temps par blocus',
                trailing: FilledButton.tonalIcon(
                  onPressed: _addBlocus,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nouveau blocus'),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Table(
                    columnWidths: const {1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth(), 3: IntrinsicColumnWidth()},
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      _headerRow(context, const ['Blocus', 'Période', 'Temps', '']),
                      for (final r in blocus) _blocusRow(context, r),
                      TableRow(children: [
                        _cell(context, 'Total (toute la période)', bold: true),
                        _cell(context, ''),
                        _cell(context, formatMinutesLabel(totalSeconds(sessions)), bold: true, right: true),
                        const SizedBox.shrink(),
                      ]),
                    ],
                  ),
                  if (blocus.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        "Aucun blocus défini pour l'instant. Un blocus = une période (début → fin) ; chaque blocus a son propre total, "
                        'calculé pour le cours choisi ci-dessus.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String t, {bool bold = false, bool right = false, bool muted = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        t,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: muted ? scheme.onSurfaceVariant : null,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }

  TableRow _headerRow(BuildContext context, List<String> cols) => TableRow(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
        children: [
          for (var i = 0; i < cols.length; i++) _cell(context, cols[i], muted: true, right: i == 2),
        ],
      );

  TableRow _row(BuildContext context, List<String> cols) => TableRow(
        children: [
          for (var i = 0; i < cols.length; i++) _cell(context, cols[i], right: i == cols.length - 1),
        ],
      );

  TableRow _blocusRow(BuildContext context, BlocusRow r) {
    final b = r.blocus;
    return TableRow(children: [
      _cell(context, b.name),
      _cell(context, '${shortDateKey(b.startDate)} – ${shortDateKey(b.endDate)}', muted: true),
      _cell(context, formatMinutesLabel(r.seconds), right: true),
      Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
        IconButton(
          tooltip: 'Modifier',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _editBlocus(b),
        ),
        IconButton(
          tooltip: 'Supprimer',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => _deleteBlocus(b),
        ),
      ]),
    ]);
  }

  Future<void> _addBlocus() async {
    final r = await promptBlocus(
      context,
      title: 'Nouveau blocus',
      message: "Ex. la période de révision avant une session d'examens.",
    );
    if (r != null) c.store.addBlocus(r.name, r.startDate, r.endDate);
  }

  Future<void> _editBlocus(Blocus b) async {
    final r = await promptBlocus(
      context,
      title: 'Modifier le blocus',
      initialName: b.name,
      initialStart: b.startDate,
      initialEnd: b.endDate,
      confirmLabel: 'Mettre à jour',
    );
    if (r != null) c.store.updateBlocus(b.id, name: r.name, startDate: r.startDate, endDate: r.endDate);
  }

  Future<void> _deleteBlocus(Blocus b) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer ce blocus ?',
      message: "Seule la période est supprimée, ton temps d'étude déjà enregistré reste intact.",
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteBlocus(b.id);
  }
}
