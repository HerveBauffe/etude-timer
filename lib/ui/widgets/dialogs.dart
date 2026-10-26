import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatting.dart';
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

/// Choix d'un dossier de destination (pour déplacer une UE). `null` = annulé ; chaîne vide = racine.
Future<String?> pickFolder(
  BuildContext context, {
  required String title,
  required List<({String id, String label})> folders,
  String? current,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(''),
          child: Row(children: [
            Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
            const SizedBox(width: 12),
            const Text('(Racine)'),
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

/// Formate une durée pour l'historique (ex. « 25 min »).
String durationLabel(int seconds) => seconds <= 0 ? '' : formatMinutesLabel(seconds);
