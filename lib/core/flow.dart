import 'models.dart';
import 'pomodoro.dart' show WorkLog;

enum FlowPhase { idle, working, review, breakTime }

/// Flow Zone : chronomètre libre ; à l'arrêt, une pause « méritée » proportionnelle
/// au temps travaillé (pourcentage réglable). La pause n'est jamais enregistrée.
class FlowEngine {
  final DateTime Function() now;
  final Settings Function() settings;
  final void Function(WorkLog log, String note) onWorkLogged;
  final void Function(String? courseId) onBreakEnded;

  FlowPhase phase = FlowPhase.idle;
  String? courseId;

  /// Début de la séance (sert à dater l'enregistrement).
  DateTime? _startedAt;

  /// Temps de travail effectif : cumul avant la pause en cours + segment actif depuis `_segmentStart`.
  int _elapsedBeforeMs = 0;
  DateTime? _segmentStart;
  bool paused = false;

  int reviewSeconds = 0;
  DateTime? _breakEndsAt;
  int breakTotalSeconds = 0;

  FlowEngine({
    required this.settings,
    required this.onWorkLogged,
    required this.onBreakEnded,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  bool get isBusy => phase != FlowPhase.idle;

  int get elapsedSeconds {
    if (phase == FlowPhase.working && _startedAt != null) {
      final seg = (paused || _segmentStart == null) ? 0 : now().difference(_segmentStart!).inMilliseconds;
      return (_elapsedBeforeMs + seg) ~/ 1000;
    }
    return phase == FlowPhase.review ? reviewSeconds : 0;
  }

  double get breakRemainingSeconds {
    if (phase != FlowPhase.breakTime || _breakEndsAt == null) return 0;
    final ms = _breakEndsAt!.difference(now()).inMilliseconds;
    return ms <= 0 ? 0 : ms / 1000.0;
  }

  /// Pause méritée pour une durée de travail donnée.
  int earnedBreakSeconds(int workSeconds) {
    final v = (workSeconds * settings().flowBreakPercent / 100).round();
    return v < 1 ? 1 : v;
  }

  void start(String course) {
    courseId = course;
    phase = FlowPhase.working;
    _startedAt = now();
    _segmentStart = _startedAt;
    _elapsedBeforeMs = 0;
    paused = false;
  }

  /// Pause / reprise du chronomètre (le temps en pause n'est pas compté).
  void togglePause() {
    if (phase != FlowPhase.working || _startedAt == null) return;
    if (paused) {
      _segmentStart = now();
      paused = false;
    } else {
      if (_segmentStart != null) _elapsedBeforeMs += now().difference(_segmentStart!).inMilliseconds;
      _segmentStart = null;
      paused = true;
    }
  }

  /// Arrête le chronomètre → écran de bilan.
  void stop() {
    if (phase != FlowPhase.working || _startedAt == null) return;
    reviewSeconds = elapsedSeconds;
    paused = false;
    phase = FlowPhase.review;
  }

  /// Valide le bilan : enregistre le temps de travail (avec la note), puis démarre la pause ou revient au repos.
  void confirmReview({required bool withBreak, String note = ''}) {
    if (phase != FlowPhase.review || _startedAt == null || courseId == null) return;
    final start = _startedAt!;
    final secs = reviewSeconds;
    final c = courseId!;
    if (withBreak) {
      breakTotalSeconds = earnedBreakSeconds(secs);
      _breakEndsAt = now().add(Duration(seconds: breakTotalSeconds));
      phase = FlowPhase.breakTime;
    } else {
      phase = FlowPhase.idle;
    }
    if (secs > 0 || note.trim().isNotEmpty) {
      onWorkLogged(WorkLog(c, 'flow', start, start.add(Duration(seconds: secs)), secs), note);
    }
  }

  /// Abandonne la pause (« Arrêter la pause »).
  void stopBreak() {
    if (phase == FlowPhase.breakTime) phase = FlowPhase.idle;
  }

  /// À appeler régulièrement : détecte la fin naturelle de la pause.
  void tick() {
    if (phase == FlowPhase.breakTime && breakRemainingSeconds <= 0) {
      phase = FlowPhase.idle;
      onBreakEnded(courseId);
    }
  }

  /// Fermeture de l'application en plein travail : on enregistre ce qui a été fait.
  /// Retourne true si une séance a été enregistrée.
  bool flushOnClose() {
    if ((phase == FlowPhase.working || phase == FlowPhase.review) && _startedAt != null && courseId != null) {
      final secs = phase == FlowPhase.review ? reviewSeconds : elapsedSeconds;
      final start = _startedAt!;
      phase = FlowPhase.idle;
      if (secs >= 1) {
        onWorkLogged(WorkLog(courseId!, 'flow', start, start.add(Duration(seconds: secs)), secs), '');
        return true;
      }
    }
    return false;
  }

  // ───────────── Persistance (reprise après arrêt du processus) ─────────────

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'courseId': courseId,
        'startedAt': _startedAt?.toUtc().toIso8601String(),
        'elapsedBeforeMs': _elapsedBeforeMs,
        'segmentStart': _segmentStart?.toUtc().toIso8601String(),
        'paused': paused,
        'reviewSeconds': reviewSeconds,
        'breakEndsAt': _breakEndsAt?.toUtc().toIso8601String(),
        'breakTotalSeconds': breakTotalSeconds,
      };

  void restore(Map<String, dynamic> j) {
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    phase = FlowPhase.values.asNameMap()[j['phase']] ?? FlowPhase.idle;
    courseId = j['courseId'] as String?;
    _startedAt = d(j['startedAt']);
    _elapsedBeforeMs = (j['elapsedBeforeMs'] as num?)?.toInt() ?? 0;
    _segmentStart = d(j['segmentStart']);
    paused = j['paused'] == true;
    reviewSeconds = (j['reviewSeconds'] as num?)?.toInt() ?? 0;
    _breakEndsAt = d(j['breakEndsAt']);
    breakTotalSeconds = (j['breakTotalSeconds'] as num?)?.toInt() ?? 0;
    if (phase == FlowPhase.working && (_startedAt == null || (!paused && _segmentStart == null))) phase = FlowPhase.idle;
    if (phase == FlowPhase.breakTime && _breakEndsAt == null) phase = FlowPhase.idle;
  }

  /// Plafonne le temps de travail et met en pause (reprise d'une séance très ancienne).
  void capElapsed(int maxSeconds) {
    if (phase != FlowPhase.working || elapsedSeconds <= maxSeconds) return;
    _elapsedBeforeMs = maxSeconds * 1000;
    _segmentStart = null;
    paused = true;
  }
}
