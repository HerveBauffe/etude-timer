import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatting.dart';
import '../../core/models.dart';
import '../../core/util.dart';

/// Boîtes de dialogue Material 3 communes à toute l'appli.

String formatDateFr(String key) {
  final d = parseDateKey(key);
  return d == null ? key : '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Nom',
  String initial = '',
  String confirmLabel = 'Valider',
  bool multiline = false,
  bool allowEmpty = false,
  String? hint,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      message: message,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
      multiline: multiline,
      allowEmpty: allowEmpty,
      hint: hint,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String label;
  final String initial;
  final String confirmLabel;
  final bool multiline;
  final bool allowEmpty;
  final String? hint;
  const _TextDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    required this.multiline,
    required this.allowEmpty,
    required this.hint,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty && !widget.allowEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _c,
              autofocus: true,
              minLines: widget.multiline ? 3 : 1,
              maxLines: widget.multiline ? 6 : 1,
              textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
              decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
              onSubmitted: widget.multiline ? null : (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmer',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : SizedBox(width: 420, child: Text(message)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return r ?? false;
}

class DurationResult {
  final int minutes;
  final String date;
  const DurationResult(this.minutes, this.date);
}

/// Durée (en minutes) + date : temps ajouté à la main ou correction d'une séance.
Future<DurationResult?> promptDuration(
  BuildContext context, {
  required String title,
  String? message,
  int initialMinutes = 30,
  String? initialDate,
  String confirmLabel = 'Ajouter',
}) {
  return showDialog<DurationResult>(
    context: context,
    builder: (_) => _DurationDialog(
      title: title,
      message: message,
      initialMinutes: initialMinutes,
      initialDate: initialDate ?? dateKey(DateTime.now()),
      confirmLabel: confirmLabel,
    ),
  );
}

class _DurationDialog extends StatefulWidget {
  final String title;
  final String? message;
  final int initialMinutes;
  final String initialDate;
  final String confirmLabel;
  const _DurationDialog({
    required this.title,
    required this.message,
    required this.initialMinutes,
    required this.initialDate,
    required this.confirmLabel,
  });

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final TextEditingController _min = TextEditingController(text: '${widget.initialMinutes}');
  late String _date = widget.initialDate;
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: parseDateKey(_date) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (d != null) setState(() => _date = dateKey(d));
  }

  void _submit() {
    final m = int.tryParse(_min.text.trim());
    if (m == null || m < 1 || m > 24 * 60) {
      setState(() => _error = 'Entre une durée entre 1 et 1440 minutes.');
      return;
    }
    Navigator.of(context).pop(DurationResult(m, _date));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _min,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Durée (minutes)', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Date : ${formatDateFr(_date)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class BlocusResult {
  final String name;
  final String startDate;
  final String endDate;
  const BlocusResult(this.name, this.startDate, this.endDate);
}

Future<BlocusResult?> promptBlocus(
  BuildContext context, {
  required String title,
  String? message,
  String initialName = '',
  String? initialStart,
  String? initialEnd,
  String confirmLabel = 'Créer',
}) {
  return showDialog<BlocusResult>(
    context: context,
    builder: (_) => _BlocusDialog(
      title: title,
      message: message,
      initialName: initialName,
      initialStart: initialStart,
      initialEnd: initialEnd,
      confirmLabel: confirmLabel,
    ),
  );
}

class _BlocusDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String initialName;
  final String? initialStart;
  final String? initialEnd;
  final String confirmLabel;
  const _BlocusDialog({
    required this.title,
    required this.message,
    required this.initialName,
    required this.initialStart,
    required this.initialEnd,
    required this.confirmLabel,
  });

  @override
  State<_BlocusDialog> createState() => _BlocusDialogState();
}

class _BlocusDialogState extends State<_BlocusDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late String _start = widget.initialStart ?? dateKey(DateTime.now());
  late String _end = widget.initialEnd ?? dateKey(DateTime.now().add(const Duration(days: 14)));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<String?> _pick(String current) async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseDateKey(current) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    return d == null ? null : dateKey(d);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(BlocusResult(name, _start, _end));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom', hintText: 'Ex. Blocus janvier 2027'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _pick(_start);
                    if (d != null) setState(() => _start = d);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('Début : ${formatDateFr(_start)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _pick(_end);
                    if (d != null) setState(() => _end = d);
                  },
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text('Fin : ${formatDateFr(_end)}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Toutes les minutes étudiées entre ces deux dates (incluses) comptent dans ce blocus.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Choix d'une destination dans une liste (dossier pour une UE, UE pour un cours).
/// `null` = annulé ; chaîne vide = racine (si `rootLabel` est fourni).
Future<String?> pickFolder(
  BuildContext context, {
  required String title,
  required List<({String id, String label})> folders,
  String? current,
  String? rootLabel = '(Racine)',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        if (rootLabel != null)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: Row(children: [
              Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              const SizedBox(width: 12),
              Text(rootLabel),
            ]),
          ),
        for (final f in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(f.id),
            child: Row(children: [
              Icon(current == f.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              const SizedBox(width: 12),
              Flexible(child: Text(f.label, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
    ),
  );
}

class CourseResult {
  final String name;
  final int quadri;
  const CourseResult(this.name, this.quadri);
}

/// Création / modification d'un cours : nom + quadrimestre (un cours ne porte que sur un quadrimestre).
Future<CourseResult?> promptCourse(
  BuildContext context, {
  required String title,
  String initialName = '',
  int initialQuadri = 1,
  String confirmLabel = 'Créer',
}) {
  return showDialog<CourseResult>(
    context: context,
    builder: (_) => _CourseDialog(title: title, initialName: initialName, initialQuadri: initialQuadri, confirmLabel: confirmLabel),
  );
}

class _CourseDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialQuadri;
  final String confirmLabel;
  const _CourseDialog({required this.title, required this.initialName, required this.initialQuadri, required this.confirmLabel});

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late int _quadri = widget.initialQuadri == 2 ? 2 : 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.of(context).pop(CourseResult(n, _quadri));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom du cours'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('Quadrimestre', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Q1')),
                ButtonSegment(value: 2, label: Text('Q2')),
              ],
              selected: {_quadri},
              onSelectionChanged: (v) => setState(() => _quadri = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              "Un cours (et son examen) ne porte que sur un quadrimestre ; une UE peut en couvrir deux.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Résultat du dialogue de planning. `delete` = l'utilisateur a demandé la suppression.
class PlanResult {
  final bool delete;
  final PlanKind kind;
  final String title;
  final String courseId;
  final String date;
  final String? time;
  final int? estimatedMinutes;
  final bool done;
  const PlanResult({
    this.delete = false,
    required this.kind,
    required this.title,
    required this.courseId,
    required this.date,
    this.time,
    this.estimatedMinutes,
    this.done = false,
  });
}

/// Ajout / modification d'une révision ou d'un examen.
Future<PlanResult?> promptPlan(
  BuildContext context, {
  required List<({String id, String label})> courses,
  PlanItem? existing,
  PlanKind kind = PlanKind.revision,
  required String date,
  String? courseId,
}) {
  return showDialog<PlanResult>(
    context: context,
    builder: (_) => _PlanDialog(courses: courses, existing: existing, kind: existing?.kind ?? kind, date: existing?.date ?? date, courseId: existing?.courseId ?? courseId),
  );
}

class _PlanDialog extends StatefulWidget {
  final List<({String id, String label})> courses;
  final PlanItem? existing;
  final PlanKind kind;
  final String date;
  final String? courseId;
  const _PlanDialog({required this.courses, required this.existing, required this.kind, required this.date, required this.courseId});

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late PlanKind _kind = widget.kind;
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _minutes =
      TextEditingController(text: widget.existing?.estimatedMinutes?.toString() ?? '');
  late String _date = widget.date;
  late String? _time = widget.existing?.time ?? '09:00';
  late String? _courseId = widget.courseId ?? (widget.courses.isEmpty ? null : widget.courses.first.id);
  late bool _done = widget.existing?.done ?? false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseDateKey(_date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = dateKey(d));
  }

  Future<void> _pickTime() async {
    final parts = (_time ?? '09:00').split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _time = '${pad2(t.hour)}:${pad2(t.minute)}');
  }

  void _submit() {
    if (_courseId == null) {
      setState(() => _error = "Choisis un cours (crée-en d'abord un dans l'onglet Cours).");
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Donne un titre.');
      return;
    }
    final m = int.tryParse(_minutes.text.trim());
    Navigator.of(context).pop(PlanResult(
      kind: _kind,
      title: _title.text.trim(),
      courseId: _courseId!,
      date: _date,
      time: _kind == PlanKind.exam ? (_time ?? '09:00') : null,
      estimatedMinutes: _kind == PlanKind.revision && m != null && m > 0 ? m : null,
      done: _kind == PlanKind.revision && _done,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final exam = _kind == PlanKind.exam;
    return AlertDialog(
      title: Text(editing ? 'Modifier' : 'Planifier'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<PlanKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PlanKind.revision, label: Text('Révision'), icon: Icon(Icons.edit_note)),
                  ButtonSegment(value: PlanKind.exam, label: Text('Examen'), icon: Icon(Icons.assignment_outlined)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Titre',
                  hintText: exam ? 'Ex. Examen écrit' : 'Ex. Chapitres 1 à 3',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _courseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cours'),
                items: [
                  for (final c in widget.courses) DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _courseId = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text('Date : ${formatDateFr(_date)}'),
                ),
                if (exam)
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('Heure : ${_time ?? '09:00'}'),
                  ),
              ]),
              if (!exam) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Durée estimée (facultatif)', suffixText: 'min'),
                ),
                if (editing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Fait'),
                    value: _done,
                    onChanged: (v) => setState(() => _done = v ?? false),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(const PlanResult(delete: true, kind: PlanKind.revision, title: '', courseId: '', date: '')),
            child: const Text('Supprimer'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Enregistrer' : 'Ajouter')),
      ],
    );
  }
}

/// Formate une durée pour l'historique (ex. « 25 min »).
String durationLabel(int seconds) => seconds <= 0 ? '' : formatMinutesLabel(seconds);
