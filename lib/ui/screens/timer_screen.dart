import 'package:flutter/material.dart';

import '../../core/flow.dart';
import '../../core/formatting.dart';
import '../../core/models.dart';
import '../../core/pomodoro.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/timer_ring.dart';

class TimerScreen extends StatelessWidget {
  final AppController c;
  const TimerScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final courseId = c.activeCourseId;
    final course = c.store.courseById(courseId);
    final busy = c.busy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              SegmentedButton<TimerMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TimerMode.pomodoro, label: Text('Pomodoro'), icon: Icon(Icons.timer_outlined)),
                  ButtonSegment(value: TimerMode.flow, label: Text('Flow Zone'), icon: Icon(Icons.all_inclusive)),
                ],
                selected: {c.mode},
                onSelectionChanged: busy ? null : (s) => c.setMode(s.first),
              ),
              const SizedBox(height: 20),
              _CourseHeader(c: c, courseId: courseId, hasCourse: course != null, busy: busy),
              if (course != null && !busy) _ResumeBanner(c: c, courseId: courseId!),
              const SizedBox(height: 12),
              if (c.mode == TimerMode.pomodoro) _PomodoroCore(c: c) else _FlowCore(c: c),
              if (course != null) _History(c: c, courseId: courseId!),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── En-tête cours ─────────────────────────

class _CourseHeader extends StatelessWidget {
  final AppController c;
  final String? courseId;
  final bool hasCourse;
  final bool busy;
  const _CourseHeader({required this.c, required this.courseId, required this.hasCourse, required this.busy});

  Future<void> _quickNote(BuildContext context) async {
    final text = await promptText(
      context,
      title: 'Ajouter une note',
      message: 'Un repère pour la prochaine fois (page, chapitre, exercice…).',
      label: 'Note',
      multiline: true,
      confirmLabel: 'Enregistrer',
    );
    if (text != null && text.isNotEmpty) c.addNote(courseId!, text);
  }

  Future<void> _quickTime(BuildContext context) async {
    final r = await promptDuration(
      context,
      title: 'Ajouter du temps manuellement',
      message: "Utile si tu as oublié de lancer ou d'arrêter le minuteur.",
    );
    if (r != null) c.store.addManualTime(courseId: courseId!, seconds: r.minutes * 60, date: r.date);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!hasCourse) {
      return Card(
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.arrow_back, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            const Expanded(child: Text('Choisis un cours dans la liste de gauche (bouton ‹ › pour la replier ou la rouvrir) pour commencer.')),
          ]),
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(c.courseLabel(courseId), style: Theme.of(context).textTheme.titleMedium),
        if (!busy) ...[
          FilledButton.tonalIcon(
            onPressed: () => _quickNote(context),
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            label: const Text('Note'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _quickTime(context),
            icon: const Icon(Icons.more_time, size: 18),
            label: const Text('Temps'),
          ),
        ],
      ],
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  final AppController c;
  final String courseId;
  const _ResumeBanner({required this.c, required this.courseId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = c.store.lastNoteFor(courseId);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: last == null
          ? Text('Pas encore de note de reprise pour ce cours.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          : Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.bookmark_outline, size: 18, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Text('Reprise · ${relativeDate(last.end)}',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer)),
                    ]),
                    const SizedBox(height: 6),
                    SelectableText(last.note, style: TextStyle(color: scheme.onSecondaryContainer)),
                  ],
                ),
              ),
            ),
    );
  }
}

// ───────────────────────── Pomodoro ─────────────────────────

class _PomodoroCore extends StatelessWidget {
  final AppController c;
  const _PomodoroCore({required this.c});

  Future<void> _endSession(BuildContext context) async {
    final course = c.endPomodoroSession();
    if (course == null) return;
    final note = await promptText(
      context,
      title: 'Où en es-tu ?',
      message: 'Note un repère pour reprendre plus facilement la prochaine fois (optionnel).',
      label: 'Note',
      multiline: true,
      allowEmpty: true,
      confirmLabel: 'Enregistrer',
    );
    if (note != null && note.isNotEmpty) c.addNote(course, note);
  }

  @override
  Widget build(BuildContext context) {
    final p = c.pomodoro;
    final s = c.store.data.settings;
    final n = s.blocksBeforeLongBreak;
    final hasCourse = c.selectedCourseId != null;

    Widget controls;
    switch (p.phase) {
      case PomoPhase.idle:
        controls = FilledButton.icon(
          onPressed: hasCourse ? c.startPomodoro : null,
          icon: const Icon(Icons.play_arrow),
          label: Text('Démarrer le bloc 1/$n (${s.workMin} min)'),
        );
      case PomoPhase.work || PomoPhase.shortBreak || PomoPhase.longBreak:
        controls = Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton.tonalIcon(
            onPressed: c.togglePomodoroPause,
            icon: Icon(p.paused ? Icons.play_arrow : Icons.pause),
            label: Text(p.paused ? 'Reprendre' : 'Pause'),
          ),
          OutlinedButton.icon(
            onPressed: c.skipPomodoroPhase,
            icon: const Icon(Icons.skip_next),
            label: const Text('Passer'),
          ),
        ]);
      case PomoPhase.breakEnded:
        controls = FilledButton.icon(
          onPressed: hasCourse ? c.startPomodoro : null,
          icon: const Icon(Icons.play_arrow),
          label: Text('Démarrer le bloc ${p.blockIndex}/$n (${s.workMin} min)'),
        );
      case PomoPhase.cycleComplete:
        controls = FilledButton.icon(
          onPressed: c.newPomodoroCycle,
          icon: const Icon(Icons.refresh),
          label: const Text('Nouveau cycle'),
        );
    }

    return Column(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: c.tick,
          builder: (context, _, __) => _PomodoroRing(c: c),
        ),
        const SizedBox(height: 20),
        controls,
        if (p.inSession) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: () => _endSession(context), child: const Text("Terminer la session d'étude")),
        ],
      ],
    );
  }
}

class _PomodoroRing extends StatelessWidget {
  final AppController c;
  const _PomodoroRing({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = c.pomodoro;
    final s = c.store.data.settings;
    final scheme = Theme.of(context).colorScheme;
    final n = s.blocksBeforeLongBreak;

    var digits = formatHMS(s.workMin * 60);
    var progress = 0.0;
    var label = 'Prêt à démarrer';
    var overtime = false;
    String? chip;
    final pausedSuffix = p.paused ? ' · en pause' : '';

    switch (p.phase) {
      case PomoPhase.idle:
        break;
      case PomoPhase.work:
        final rem = p.remainingSeconds;
        if (rem > 0) {
          digits = formatHMS(rem.ceil());
          progress = p.elapsedSeconds / p.totalSeconds;
          label = 'Bloc ${p.blockIndex}/$n · Travail$pausedSuffix';
        } else {
          overtime = true;
          digits = formatHMS(p.elapsedSeconds);
          progress = 1;
          label = 'Bloc ${p.blockIndex}/$n · Travail$pausedSuffix';
          chip = 'Objectif atteint · +${formatHMS(-rem)}';
        }
      case PomoPhase.shortBreak || PomoPhase.longBreak:
        digits = formatHMS(p.remainingSeconds.ceil());
        progress = p.elapsedSeconds / p.totalSeconds;
        label = (p.phase == PomoPhase.longBreak ? 'Pause longue' : 'Pause courte') + pausedSuffix;
      case PomoPhase.breakEnded:
        label = 'Pause terminée';
      case PomoPhase.cycleComplete:
        label = 'Cycle terminé';
    }

    return TimerRing(
      progress: progress,
      overtime: overtime,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(digits, style: timerDigitsStyle(context, size: digits.length > 5 ? 54 : 64)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          if (chip != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(chip, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onTertiaryContainer)),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Flow Zone ─────────────────────────

class _FlowCore extends StatelessWidget {
  final AppController c;
  const _FlowCore({required this.c});

  @override
  Widget build(BuildContext context) {
    final f = c.flow;
    final scheme = Theme.of(context).colorScheme;
    if (f.phase == FlowPhase.review) return _FlowReview(c: c);

    final Widget controls = switch (f.phase) {
      FlowPhase.idle => FilledButton.icon(
          onPressed: c.selectedCourseId == null ? null : c.startFlow,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Démarrer'),
        ),
      FlowPhase.working => FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: c.stopFlow,
          icon: const Icon(Icons.stop),
          label: const Text('Arrêter'),
        ),
      FlowPhase.breakTime => OutlinedButton.icon(
          onPressed: c.stopFlowBreak,
          icon: const Icon(Icons.stop),
          label: const Text('Arrêter la pause'),
        ),
      FlowPhase.review => const SizedBox.shrink(),
    };

    return Column(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: c.tick,
          builder: (context, _, __) {
            var digits = '00:00';
            var progress = 0.0;
            var label = 'Chronomètre libre';
            if (f.phase == FlowPhase.working) {
              final e = f.elapsedSeconds;
              digits = formatHMS(e);
              progress = (e % 3600) / 3600; // un tour d'anneau par heure
              label = 'Dans la zone';
            } else if (f.phase == FlowPhase.breakTime) {
              final rem = f.breakRemainingSeconds;
              digits = formatHMS(rem.ceil());
              progress = f.breakTotalSeconds == 0 ? 0 : 1 - rem / f.breakTotalSeconds;
              label = 'Pause méritée';
            }
            return TimerRing(
              progress: progress,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(digits, style: timerDigitsStyle(context, size: digits.length > 5 ? 54 : 64)),
                const SizedBox(height: 4),
                Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            );
          },
        ),
        const SizedBox(height: 20),
        controls,
      ],
    );
  }
}

class _FlowReview extends StatefulWidget {
  final AppController c;
  const _FlowReview({required this.c});

  @override
  State<_FlowReview> createState() => _FlowReviewState();
}

class _FlowReviewState extends State<_FlowReview> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;
    final secs = c.flow.reviewSeconds;
    final pct = c.store.data.settings.flowBreakPercent;
    final earned = c.flow.earnedBreakSeconds(secs);
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Séance terminée', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(formatHMS(secs), style: timerDigitsStyle(context, size: 48)),
            Text('de travail', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('+ ${formatHMS(earned)} de pause méritée ($pct %)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Où en es-tu ? (optionnel)'),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
              OutlinedButton(
                onPressed: () => c.confirmFlowReview(withBreak: false, note: _note.text),
                child: const Text('Enregistrer sans pause'),
              ),
              FilledButton(
                onPressed: () => c.confirmFlowReview(withBreak: true, note: _note.text),
                child: const Text('Enregistrer et lancer la pause'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Historique ─────────────────────────

class _History extends StatelessWidget {
  final AppController c;
  final String courseId;
  const _History({required this.c, required this.courseId});

  Future<void> _edit(BuildContext context, Session s) async {
    final initial = (s.seconds / 60).round().clamp(1, 24 * 60);
    final r = await promptDuration(
      context,
      title: 'Corriger cette durée',
      initialMinutes: initial,
      initialDate: s.date,
      confirmLabel: 'Mettre à jour',
    );
    if (r == null) return;
    // Durée inchangée : on garde les secondes exactes, seule la date bouge.
    c.store.updateSessionTime(s.id, seconds: r.minutes == initial ? s.seconds : r.minutes * 60, date: r.date);
  }

  Future<void> _delete(BuildContext context, Session s) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer cet élément ?',
      message: 'Cette action est définitive.',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteSession(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = c.store.sessionsForCourse(courseId);
    final items = all.take(8).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Historique récent', style: Theme.of(context).textTheme.titleSmall),
          ),
          Card(
            color: scheme.surfaceContainerLow,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _row(context, items[i], scheme),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Session s, ColorScheme scheme) {
    final isNote = s.kind == SessionKind.note;
    final kindLabel = isNote ? 'Note' : (s.mode == 'flow' ? 'Flow' : (s.mode == null ? 'Temps ajouté' : 'Travail'));
    return ListTile(
      leading: Icon(isNote ? Icons.sticky_note_2_outlined : Icons.timer_outlined, color: scheme.onSurfaceVariant),
      title: Text('$kindLabel · ${relativeDate(s.end)}'),
      subtitle: s.note.isEmpty ? null : Text(s.note),
      isThreeLine: s.note.length > 60,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.seconds > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(formatHMS(s.seconds), style: const TextStyle(fontFeatures: tabularFigures)),
            ),
          if (!isNote)
            IconButton(
              tooltip: 'Corriger la durée',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _edit(context, s),
            ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _delete(context, s),
          ),
        ],
      ),
    );
  }
}
