import 'models.dart';

/// Bloc de travail terminé, à enregistrer (les pauses ne sont jamais enregistrées).
class WorkLog {
  final String courseId;
  final String mode; // 'pomodoro' | 'flow'
  final DateTime start;
  final DateTime end;
  final int seconds;
  const WorkLog(this.courseId, this.mode, this.start, this.end, this.seconds);
}

enum PomoPhase { idle, work, shortBreak, longBreak, breakEnded, cycleComplete }

enum PomoEvent {
  /// La durée prévue du bloc est atteinte : notification, mais le minuteur continue.
  workTargetReached,
  shortBreakEnded,
  longBreakEnded,
}

/// Machine à états du Pomodoro. Aucune dépendance : l'horloge est injectable pour les tests.
///
/// Modèle de temps : `elapsedBeforePause` (secondes cumulées avant la pause en cours) +
/// segment actif depuis `_segmentStart`. Cela permet Pause/Reprendre ET le dépassement
/// (un bloc de travail ne s'arrête jamais tout seul).
class PomodoroEngine {
  final DateTime Function() now;
  final Settings Function() settings;
  final void Function(WorkLog log) onWorkLogged;
  final void Function(PomoEvent event, String? courseId) onEvent;

  PomoPhase phase = PomoPhase.idle;
  int blockIndex = 1;
  int totalSeconds = 0;
  bool paused = false;
  String? courseId;

  double _elapsedBeforePause = 0;
  DateTime? _segmentStart;
  bool _overtimeNotified = false;

  PomodoroEngine({
    required this.settings,
    required this.onWorkLogged,
    required this.onEvent,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  bool get isIdle => phase == PomoPhase.idle;
  bool get isRunning => phase == PomoPhase.work || phase == PomoPhase.shortBreak || phase == PomoPhase.longBreak;
  bool get isWork => phase == PomoPhase.work;
  bool get isBreak => phase == PomoPhase.shortBreak || phase == PomoPhase.longBreak;

  /// Vrai dès qu'une session d'étude est en cours (y compris entre deux blocs).
  bool get inSession => phase != PomoPhase.idle;

  double get elapsedSeconds {
    final seg = (paused || _segmentStart == null) ? 0.0 : now().difference(_segmentStart!).inMilliseconds / 1000.0;
    return _elapsedBeforePause + seg;
  }

  /// Secondes restantes de la phase (négatif = dépassement).
  double get remainingSeconds => totalSeconds - elapsedSeconds;

  bool get isOvertime => phase == PomoPhase.work && remainingSeconds <= 0;

  void _begin(PomoPhase p, int seconds) {
    phase = p;
    totalSeconds = seconds;
    _elapsedBeforePause = 0;
    _segmentStart = now();
    paused = false;
    _overtimeNotified = false;
  }

  /// Démarre un bloc de travail (depuis idle, après une pause terminée ou un cycle terminé).
  void startWork(String course) {
    if (phase == PomoPhase.cycleComplete) blockIndex = 1;
    courseId = course;
    _begin(PomoPhase.work, settings().workMin * 60);
  }

  void togglePause() {
    if (!isRunning) return;
    if (paused) {
      _segmentStart = now();
      paused = false;
    } else {
      _elapsedBeforePause = elapsedSeconds;
      _segmentStart = null;
      paused = true;
    }
  }

  void _logWork() {
    if (phase != PomoPhase.work || courseId == null) return;
    final secs = elapsedSeconds.round();
    if (secs < 1) return;
    final end = now();
    final start = end.subtract(Duration(seconds: secs));
    onWorkLogged(WorkLog(courseId!, 'pomodoro', start, end, secs));
  }

  /// « Passer » : termine la phase en cours et enchaîne directement sur la suivante.
  void skip() {
    if (!isRunning) return;
    final s = settings();
    if (phase == PomoPhase.work) {
      _logWork();
      final long = blockIndex >= s.blocksBeforeLongBreak;
      _begin(long ? PomoPhase.longBreak : PomoPhase.shortBreak, (long ? s.longBreakMin : s.shortBreakMin) * 60);
    } else {
      if (phase == PomoPhase.longBreak) {
        blockIndex = 1;
      } else {
        blockIndex += 1;
      }
      _begin(PomoPhase.work, s.workMin * 60);
    }
  }

  /// Termine toute la session : enregistre silencieusement le travail en cours.
  /// Retourne le cours concerné (pour proposer la note de fin de session).
  String? endSession() {
    final c = courseId;
    _logWork();
    phase = PomoPhase.idle;
    blockIndex = 1;
    paused = false;
    _segmentStart = null;
    _elapsedBeforePause = 0;
    return c;
  }

  /// À appeler régulièrement (≈ 2×/s). Déclenche les événements de fin de phase.
  void tick() {
    if (paused) return;
    if (phase == PomoPhase.work) {
      if (!_overtimeNotified && remainingSeconds <= 0) {
        _overtimeNotified = true;
        onEvent(PomoEvent.workTargetReached, courseId);
      }
    } else if (isBreak) {
      if (remainingSeconds <= 0) {
        final long = phase == PomoPhase.longBreak;
        if (long) {
          phase = PomoPhase.cycleComplete;
          blockIndex = 1;
        } else {
          blockIndex += 1;
          phase = PomoPhase.breakEnded;
        }
        _segmentStart = null;
        onEvent(long ? PomoEvent.longBreakEnded : PomoEvent.shortBreakEnded, courseId);
      }
    }
  }

  /// Depuis « Nouveau cycle ».
  void resetToIdle() {
    if (phase == PomoPhase.cycleComplete || phase == PomoPhase.breakEnded) {
      phase = PomoPhase.idle;
      blockIndex = 1;
    }
  }
}
