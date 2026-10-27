import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/models.dart';
import '../../core/planning.dart';
import '../../core/util.dart';
import '../controller.dart';
import '../widgets/dialogs.dart';

/// Onglet « Planning » : révisions et examens sur un calendrier (vue mois ou semaine),
/// limité aux cours du quadrimestre choisi.
class PlanningScreen extends StatefulWidget {
  final AppController c;
  const PlanningScreen({super.key, required this.c});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  bool _monthView = true;
  DateTime _anchor = _today();
  DateTime? _selected; // jour choisi dans la vue mois compacte (téléphone)

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  AppController get c => widget.c;

  // ───────────── Navigation ─────────────

  void _shift(int delta) {
    setState(() {
      _anchor = _monthView
          ? DateTime(_anchor.year, _anchor.month + delta, 1)
          : DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * delta);
    });
  }

  String _title() {
    if (_monthView) {
      final l = monthLabel(_anchor.year, _anchor.month - 1);
      return l[0].toUpperCase() + l.substring(1);
    }
    final days = weekDays(_anchor);
    final a = days.first;
    final b = days.last;
    final left = a.month == b.month ? '${a.day}' : '${a.day} ${monthsFrShort[a.month - 1]}';
    return '$left – ${b.day} ${monthsFrShort[b.month - 1]} ${b.year}';
  }

  // ───────────── Édition ─────────────

  List<({String id, String label})> _courseOptions({String? alsoInclude}) {
    final ids = {...c.visibleIds, if (alsoInclude != null && c.store.courseById(alsoInclude) != null) alsoInclude};
    final l = [for (final id in ids) (id: id, label: c.courseLabel(id))]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return l;
  }

  Future<void> _add(PlanKind kind, DateTime day) async {
    final options = _courseOptions();
    if (options.isEmpty) {
      c.showMessage("Aucun cours en ${c.quadri.label} : crée-en d'abord un dans l'onglet Cours.");
      return;
    }
    final r = await promptPlan(
      context,
      courses: options,
      kind: kind,
      date: dateKey(day),
      courseId: c.selectedCourseId != null && c.isCourseVisible(c.selectedCourseId) ? c.selectedCourseId : null,
    );
    if (r == null || r.delete) return;
    c.store.addPlan(
      kind: r.kind,
      title: r.title,
      courseId: r.courseId,
      date: r.date,
      time: r.time,
      estimatedMinutes: r.estimatedMinutes,
    );
    // Se place sur la date de l'élément créé pour qu'il soit visible.
    final d = parseDateKey(r.date);
    if (d != null) setState(() => _anchor = d);
  }

  Future<void> _edit(PlanItem p) async {
    final r = await promptPlan(
      context,
      courses: _courseOptions(alsoInclude: p.courseId),
      existing: p,
      date: p.date,
    );
    if (r == null) return;
    if (r.delete) {
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Supprimer « ${p.title} » ?',
        message: p.isExam ? 'Cet examen sera retiré du planning.' : 'Cette révision sera retirée du planning.',
        confirmLabel: 'Supprimer',
        danger: true,
      );
      if (ok) c.store.deletePlan(p.id);
      return;
    }
    c.store.updatePlan(
      p.id,
      kind: r.kind,
      title: r.title,
      courseId: r.courseId,
      date: r.date,
      time: r.time,
      estimatedMinutes: r.estimatedMinutes,
      done: r.done,
    );
  }

  // ───────────── Éléments ─────────────

  String _tooltip(PlanItem p) {
    final parts = <String>[p.title, c.courseLabel(p.courseId)];
    if (p.isExam && p.time != null) parts.add('Examen à ${p.time}');
    if (!p.isExam && p.estimatedMinutes != null) parts.add('Durée estimée : ${estimateLabel(p.estimatedMinutes!)}');
    if (p.done) parts.add('Fait');
    return parts.join('\n');
  }

  Widget _chip(PlanItem p) {
    final scheme = Theme.of(context).colorScheme;
    final exam = p.isExam;
    final bg = exam ? scheme.primary : (p.done ? scheme.surfaceContainerHighest : scheme.secondaryContainer);
    final fg = exam ? scheme.onPrimary : (p.done ? scheme.onSurfaceVariant : scheme.onSecondaryContainer);
    final label = exam
        ? '${p.time ?? ''} ${p.title}'.trim()
        : (p.estimatedMinutes != null ? '${p.title} · ${estimateLabel(p.estimatedMinutes!)}' : p.title);
    return Tooltip(
      message: _tooltip(p),
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _edit(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(children: [
                Icon(exam ? Icons.assignment_outlined : (p.done ? Icons.check_circle_outline : Icons.edit_note), size: 13, color: fg),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: fg,
                      fontWeight: exam ? FontWeight.w600 : FontWeight.w400,
                      decoration: p.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekCard(PlanItem p, {bool fill = false}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final exam = p.isExam;
    final subtitle = [
      c.courseLabel(p.courseId),
      if (exam && p.time != null) 'à ${p.time}',
      if (!exam && p.estimatedMinutes != null) '~ ${estimateLabel(p.estimatedMinutes!)}',
    ].join(' · ');
    return SizedBox(
      width: fill ? double.infinity : 300,
      child: Material(
        color: exam ? scheme.primary : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _edit(p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Icon(exam ? Icons.assignment_outlined : Icons.edit_note, size: 20, color: exam ? scheme.onPrimary : scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: exam ? scheme.onPrimary : scheme.onSecondaryContainer,
                      decoration: p.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: exam ? scheme.onPrimary : scheme.onSecondaryContainer),
                  ),
                ]),
              ),
              if (!exam)
                Tooltip(
                  message: 'Marquer comme fait',
                  child: Checkbox(
                    value: p.done,
                    onChanged: (v) => c.store.setPlanDone(p.id, v ?? false),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────────── Vues ─────────────

  Widget _monthBody() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weeks = monthGrid(_anchor.year, _anchor.month);
    final today = _today();
    return Column(children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(weekdaysFrShort[(i + 1) % 7], textAlign: TextAlign.center, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
      ]),
      for (final week in weeks)
        SizedBox(
          height: 124,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final day in week) Expanded(child: _monthCell(day, today)),
          ]),
        ),
    ]);
  }

  Widget _monthCell(DateTime day, DateTime today) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = day.month == _anchor.month;
    final isToday = day == today;
    final items = plansOn(c.store.data, dateKey(day), courseIds: c.visibleIds);
    const maxShown = 3;
    final shown = items.take(maxShown).toList();
    final more = items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: inMonth ? scheme.surfaceContainerLow : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isToday ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _add(PlanKind.revision, day),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: ClipRect(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      color: inMonth ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                for (final p in shown) _chip(p),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('+$more autre${more > 1 ? 's' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekBody({bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final today = _today();
    return Column(children: [
      for (final day in weekDays(_anchor))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: day == today ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _add(PlanKind.revision, day),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: compact ? 64 : 84,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, top: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(weekdaysFrShort[day.weekday % 7], style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                        Text('${day.day} ${monthsFrShort[day.month - 1]}', style: text.titleSmall),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: Builder(builder: (context) {
                      final items = plansOn(c.store.data, dateKey(day), courseIds: c.visibleIds);
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('—', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        );
                      }
                      return Wrap(spacing: 8, runSpacing: 8, children: [for (final p in items) _weekCard(p)]);
                    }),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ───────────── Vue mois compacte (téléphone / petite fenêtre) ─────────────

  /// Jour affiché sous le calendrier compact : celui choisi s'il est dans le mois, sinon
  /// aujourd'hui (si on est dans le mois affiché) ou le 1ᵉʳ.
  DateTime _effectiveSelected() {
    final s = _selected;
    if (s != null && s.year == _anchor.year && s.month == _anchor.month) return s;
    final t = _today();
    if (t.year == _anchor.year && t.month == _anchor.month) return t;
    return DateTime(_anchor.year, _anchor.month, 1);
  }

  /// Jour proposé par défaut aux boutons « Révision » / « Examen ».
  DateTime _defaultDay({required bool compact}) {
    if (!_monthView) return _anchor;
    if (compact) return _effectiveSelected();
    final n = DateTime.now();
    return _anchor.month == n.month && _anchor.year == n.year ? _today() : _anchor;
  }

  Widget _compactMonthBody() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weeks = monthGrid(_anchor.year, _anchor.month);
    final today = _today();
    final sel = _effectiveSelected();
    final selItems = plansOn(c.store.data, dateKey(sel), courseIds: c.visibleIds);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(weekdaysFrShort[(i + 1) % 7].substring(0, 1).toUpperCase(),
                  textAlign: TextAlign.center, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
      ]),
      for (final week in weeks)
        SizedBox(
          height: 52,
          child: Row(children: [
            for (final day in week) Expanded(child: _compactCell(day, today, sel)),
          ]),
        ),
      const SizedBox(height: 14),
      Text(
        '${weekdaysFrShort[sel.weekday % 7]} ${sel.day} ${monthsFrShort[sel.month - 1]}',
        style: text.titleSmall,
      ),
      const SizedBox(height: 8),
      if (selItems.isEmpty)
        Text('Rien de prévu ce jour-là.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
      else
        for (final p in selItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _weekCard(p, fill: true),
          ),
    ]);
  }

  Widget _compactCell(DateTime day, DateTime today, DateTime sel) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = day.month == _anchor.month;
    final isToday = day == today;
    final isSel = day == sel;
    final items = plansOn(c.store.data, dateKey(day), courseIds: c.visibleIds);
    final hasExam = items.any((p) => p.isExam);
    final revisions = items.where((p) => !p.isExam).length;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSel ? scheme.primaryContainer : (inMonth ? scheme.surfaceContainerLow : Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isToday ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = day),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w400,
                color: isSel
                    ? scheme.onPrimaryContainer
                    : (inMonth ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (hasExam) _dot(scheme.primary, big: true),
                for (var i = 0; i < revisions.clamp(0, 3); i++) _dot(scheme.secondary),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dot(Color color, {bool big = false}) => Container(
        width: big ? 8 : 6,
        height: big ? 8 : 6,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(color: color, shape: big ? BoxShape.rectangle : BoxShape.circle, borderRadius: big ? BorderRadius.circular(2) : null),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final next = nextExam(c.store.data, now, courseIds: c.visibleIds);

    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < 720;
      final pad = compact ? 12.0 : 24.0;
      final nextLine = Text(
        next == null
            ? 'Aucun examen planifié.'
            : 'Prochain examen : ${next.title} — ${c.courseLabel(next.courseId)} · ${daysUntilLabel(daysUntil(next.date, now))}'
                '${next.time != null ? ' à ${next.time}' : ''}',
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
      final addRevision = FilledButton.tonalIcon(
        onPressed: () => _add(PlanKind.revision, _defaultDay(compact: compact)),
        icon: const Icon(Icons.edit_note, size: 18),
        label: const Text('Révision'),
      );
      final addExam = FilledButton.icon(
        onPressed: () => _add(PlanKind.exam, _defaultDay(compact: compact)),
        icon: const Icon(Icons.assignment_outlined, size: 18),
        label: const Text('Examen'),
      );
      final modeToggle = SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: false, label: const Text('Semaine'), icon: compact ? null : const Icon(Icons.view_week_outlined)),
          ButtonSegment(value: true, label: const Text('Mois'), icon: compact ? null : const Icon(Icons.calendar_month_outlined)),
        ],
        selected: {_monthView},
        onSelectionChanged: (s) => setState(() => _monthView = s.first),
      );
      final title = Text(_title(), textAlign: TextAlign.center, style: text.titleMedium);

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) ...[
                  Row(children: [Expanded(child: addRevision), const SizedBox(width: 8), Expanded(child: addExam)]),
                  const SizedBox(height: 8),
                  nextLine,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: modeToggle),
                  const SizedBox(height: 4),
                  Row(children: [
                    IconButton(tooltip: _monthView ? 'Mois précédent' : 'Semaine précédente', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                    Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: title)),
                    IconButton(tooltip: _monthView ? 'Mois suivant' : 'Semaine suivante', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
                    IconButton(tooltip: "Aujourd'hui", icon: const Icon(Icons.today), onPressed: () => setState(() {
                          _anchor = _today();
                          _selected = _today();
                        })),
                  ]),
                ] else ...[
                  Row(children: [
                    Text('Planning', style: text.headlineSmall),
                    const SizedBox(width: 12),
                    Text(c.quadri.label, style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    addRevision,
                    const SizedBox(width: 8),
                    addExam,
                  ]),
                  const SizedBox(height: 4),
                  nextLine,
                  const SizedBox(height: 12),
                  Row(children: [
                    modeToggle,
                    const SizedBox(width: 12),
                    IconButton(tooltip: _monthView ? 'Mois précédent' : 'Semaine précédente', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                    SizedBox(width: 190, child: title),
                    IconButton(tooltip: _monthView ? 'Mois suivant' : 'Semaine suivante', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
                    TextButton(onPressed: () => setState(() => _anchor = _today()), child: const Text("Aujourd'hui")),
                  ]),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _monthView ? (compact ? _compactMonthBody() : _monthBody()) : _weekBody(compact: compact),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
