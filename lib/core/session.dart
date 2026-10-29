import 'dart:convert';
import 'dart:io';

import 'flow.dart';
import 'formatting.dart';
import 'models.dart';
import 'pomodoro.dart';

/// Séance en cours, vue « de l'extérieur » : ce qu'il faut pour l'afficher dans une notification,
/// programmer l'alarme de fin de phase et la retrouver si le système tue l'appli.
///
/// Tout est dérivé de l'état des moteurs ([PomodoroEngine] / [FlowEngine]) ; le modèle de temps
/// étant basé sur l'horloge, une séance « retrouvée » continue exactement là où elle en serait.
/// Logique pure (aucun Flutter) : testable et utilisable depuis un isolat d'arrière-plan.
class SessionSnapshot {
  final String mode; // 'pomodoro' | 'flow'
  final String courseLabel;
  final DateTime savedAt;
  final Map<String, dynamic> pomodoro;
  final Map<String, dynamic> flow;

  const SessionSnapshot({
    required this.mode,
    required this.courseLabel,
    required this.savedAt,
    this.pomodoro = const {},
    this.flow = const {},
  });

  SessionSnapshot copyWith({Map<String, dynamic>? pomodoro, Map<String, dynamic>? flow, DateTime? savedAt}) => SessionSnapshot(
        mode: mode,
        courseLabel: courseLabel,
        savedAt: savedAt ?? this.savedAt,
        pomodoro: pomodoro ?? this.pomodoro,
        flow: flow ?? this.flow,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'mode': mode,
        'courseLabel': courseLabel,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'pomodoro': pomodoro,
        'flow': flow,
      };

  static SessionSnapshot? fromJson(Object? j) {
    if (j is! Map) return null;
    final mode = j['mode'];
    if (mode != 'pomodoro' && mode != 'flow') return null;
    Map<String, dynamic> m(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    return SessionSnapshot(
      mode: mode as String,
      courseLabel: (j['courseLabel'] as String?) ?? '',
      savedAt: DateTime.tryParse((j['savedAt'] as String?) ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      pomodoro: m(j['pomodoro']),
      flow: m(j['flow']),
    );
  }
}

/// Fichier `session.json` : au plus une séance. Écriture atomique ; ne lève jamais d'exception.
class SessionStore {
  final String path;
  SessionStore(this.path);

  SessionSnapshot? load() {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return SessionSnapshot.fromJson(jsonDecode(f.readAsStringSync()));
    } catch (_) {
      return null; // fichier illisible : on repart au repos
    }
  }

  void save(SessionSnapshot s) {
    try {
      final tmp = File('$path.tmp');
      tmp.writeAsStringSync(jsonEncode(s.toJson()), flush: true);
      tmp.renameSync(path);
    } catch (_) {}
  }

  void clear() {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

// ───────────────────────── Plan : quoi afficher, quand sonner ─────────────────────────

/// Ce que le système doit montrer pour une séance : notification persistante (avec chronomètre
/// natif, qui avance sans que l'appli ait besoin de tourner) et alarme de fin de phase.
class SessionPlan {
  /// Une notification persistante (service de premier plan) doit être affichée.
  final bool active;
  final String title;
  final String body;

  /// Le chronomètre natif de la notification avance (faux : en pause → texte fixe).
  final bool ticking;

  /// Base du chronomètre natif (ms depuis 1970) : cible d'un compte à rebours, ou point de départ d'un chrono.
  final int? chronoMs;
  final bool countDown;
  final bool paused;

  /// Le bouton Pause / Reprendre a un sens (pas pour la pause méritée du Flow).
  final bool canToggle;

  /// Fin de la phase (ms depuis 1970) : alarme à programmer ; null = pas d'alarme.
  final int? alarmAtMs;
  final String alarmTitle;
  final String alarmBody;

  const SessionPlan({
    required this.active,
    this.title = '',
    this.body = '',
    this.ticking = false,
    this.chronoMs,
    this.countDown = false,
    this.paused = false,
    this.canToggle = false,
    this.alarmAtMs,
    this.alarmTitle = '',
    this.alarmBody = '',
  });

  static const SessionPlan inactive = SessionPlan(active: false);

  Map<String, Object?> toJson() => {
        'active': active,
        'title': title,
        'body': body,
        'ticking': ticking,
        'chronoMs': chronoMs,
        'countDown': countDown,
        'paused': paused,
        'canToggle': canToggle,
        'alarmAtMs': alarmAtMs,
        'alarmTitle': alarmTitle,
        'alarmBody': alarmBody,
      };

  /// Clé de comparaison : deux plans identiques n'ont pas besoin d'être ré-appliqués.
  String get key => jsonEncode(toJson());
}

PomodoroEngine _pomo(SessionSnapshot s, DateTime now) => PomodoroEngine(
      settings: Settings.new,
      onWorkLogged: (_) {},
      onEvent: (_, __) {},
      now: () => now,
    )..restore(s.pomodoro);

FlowEngine _flow(SessionSnapshot s, DateTime now) => FlowEngine(
      settings: Settings.new,
      onWorkLogged: (_, __) {},
      onBreakEnded: (_) {},
      now: () => now,
    )..restore(s.flow);

int? _ms(Object? iso) => iso is String ? DateTime.tryParse(iso)?.millisecondsSinceEpoch : null;

SessionPlan planSession(SessionSnapshot s, DateTime now) {
  final label = s.courseLabel;
  String withLabel(String t) => label.isEmpty ? t : '$t · $label';
  final nowMs = now.millisecondsSinceEpoch;

  if (s.mode == 'pomodoro') {
    final p = _pomo(s, now);
    if (!p.isRunning) return SessionPlan.inactive; // attente d'un démarrage manuel : rien à faire tourner
    final remaining = p.remainingSeconds;
    final isWork = p.isWork;
    final long = p.phase == PomoPhase.longBreak;
    final phaseName = isWork ? 'Travail' : (long ? 'Pause longue' : 'Pause');

    if (p.paused) {
      final body = isWork
          ? (remaining > 0
              ? 'Bloc ${p.blockIndex} · reste ${formatHMS(remaining)}'
              : 'Bloc ${p.blockIndex} · +${formatHMS(-remaining)} au-delà de l\'objectif')
          : 'Reste ${formatHMS(remaining)}';
      return SessionPlan(active: true, title: withLabel('En pause'), body: body, paused: true, canToggle: true);
    }
    if (!isWork && remaining <= 0) return SessionPlan.inactive; // pause finie, l'événement va suivre

    final seg = _ms(s.pomodoro['segmentStart']);
    final beforeMs = (((s.pomodoro['elapsedBeforePause'] as num?) ?? 0) * 1000).round();
    final targetMs = seg == null ? nowMs + (remaining * 1000).round() : seg + (p.totalSeconds * 1000 - beforeMs);

    if (isWork && remaining <= 0) {
      // Dépassement : le chrono repart à 0 à l'instant de l'objectif et continue (le temps compte).
      return SessionPlan(
        active: true,
        title: withLabel(phaseName),
        body: 'Objectif atteint · le chrono continue (bloc ${p.blockIndex})',
        ticking: true,
        chronoMs: targetMs,
        canToggle: true,
      );
    }
    return SessionPlan(
      active: true,
      title: withLabel(phaseName),
      body: isWork ? 'Bloc ${p.blockIndex} · objectif ${formatHMS(p.totalSeconds)}' : 'Reprise du travail à la fin du décompte',
      ticking: true,
      chronoMs: targetMs,
      countDown: true,
      canToggle: true,
      alarmAtMs: targetMs,
      alarmTitle: isWork ? 'Bloc terminé' : (long ? 'Pause longue terminée' : 'Pause terminée'),
      alarmBody: isWork
          ? (label.isEmpty ? 'Le chrono continue : passe à la pause quand tu veux.' : '$label — le chrono continue, passe à la pause quand tu veux.')
          : (label.isEmpty ? 'Prêt à reprendre ?' : '$label — prêt à reprendre ?'),
    );
  }

  // Flow Zone
  final f = _flow(s, now);
  if (f.phase == FlowPhase.working) {
    if (f.paused) {
      return SessionPlan(
        active: true,
        title: withLabel('En pause'),
        body: 'Flow Zone · ${formatHMS(f.elapsedSeconds)} travaillées',
        paused: true,
        canToggle: true,
      );
    }
    final seg = _ms(s.flow['segmentStart']) ?? nowMs;
    final beforeMs = (s.flow['elapsedBeforeMs'] as num?)?.toInt() ?? 0;
    return SessionPlan(
      active: true,
      title: withLabel('Flow Zone'),
      body: 'Chronomètre libre · touche Pause pour t\'arrêter sans clore la séance',
      ticking: true,
      chronoMs: seg - beforeMs,
      canToggle: true,
    );
  }
  if (f.phase == FlowPhase.breakTime) {
    final end = _ms(s.flow['breakEndsAt']);
    if (end == null || end <= nowMs) return SessionPlan.inactive;
    return SessionPlan(
      active: true,
      title: withLabel('Pause méritée'),
      body: 'Reprise à la fin du décompte',
      ticking: true,
      chronoMs: end,
      countDown: true,
      alarmAtMs: end,
      alarmTitle: 'Pause terminée',
      alarmBody: label.isEmpty ? 'Prêt à reprendre ?' : '$label — prêt à reprendre ?',
    );
  }
  return SessionPlan.inactive;
}

/// Pause / reprise appliquée directement à une séance sauvegardée (bouton de la notification
/// pressé alors que l'appli n'est plus en mémoire). `null` si rien à basculer.
SessionSnapshot? toggledSnapshot(SessionSnapshot s, DateTime now) {
  if (s.mode == 'pomodoro') {
    final p = _pomo(s, now);
    if (!p.isRunning) return null;
    p.togglePause();
    return s.copyWith(pomodoro: p.toJson(), savedAt: now);
  }
  final f = _flow(s, now);
  if (f.phase != FlowPhase.working) return null;
  f.togglePause();
  return s.copyWith(flow: f.toJson(), savedAt: now);
}

// ───────────────────────── Coordination ─────────────────────────

/// Applique un [SessionPlan] au système (Android : service de premier plan + alarme).
abstract class SessionBackend {
  Future<void> apply(SessionPlan plan);
}

/// Autorisations système liées à la notification du chrono (Android).
abstract class SessionPermissions {
  /// Notifications autorisées pour l'appli.
  bool get notificationsEnabled;

  /// Demande l'autorisation d'afficher des notifications ; true si accordée.
  Future<bool> requestNotifications();

  /// Ouvre le réglage système « notifications plein écran » (réveil de l'écran à la fin d'une phase).
  Future<void> requestFullScreen();

  /// Rafraîchit [notificationsEnabled] (l'utilisateur a pu changer le réglage dans Android).
  Future<void> refresh();
}

class NoopSessionBackend implements SessionBackend {
  const NoopSessionBackend();
  @override
  Future<void> apply(SessionPlan plan) async {}
}

class RestoreResult {
  final String? mode;
  final bool stale;
  const RestoreResult(this.mode, {this.stale = false});
  static const none = RestoreResult(null);
  bool get restored => mode != null;
}

/// Relie les moteurs, le fichier `session.json` et le système. À appeler après chaque
/// changement d'état d'une séance ([sync]) et une fois au démarrage ([restore]).
class SessionCoordinator {
  /// Une séance de travail Pomodoro qui dépasse l'objectif de plus que ça est jugée oubliée.
  static const int staleOvertimeSeconds = 2 * 3600;

  /// Un chrono Flow plus long que ça est jugé oublié ; il est ramené à [flowCapSeconds] et mis en pause.
  static const int staleFlowSeconds = 6 * 3600;
  static const int flowCapSeconds = 4 * 3600;

  final PomodoroEngine pomodoro;
  final FlowEngine flow;
  final SessionStore store;
  final SessionBackend backend;
  final String Function(String? courseId) courseLabel;
  final DateTime Function() now;

  /// Appelé (une fois) si le système refuse la notification / l'alarme.
  void Function(Object error)? onError;
  bool _errorReported = false;

  String? _lastKey;

  SessionCoordinator({
    required this.pomodoro,
    required this.flow,
    required this.store,
    required this.backend,
    required this.courseLabel,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  SessionSnapshot? _snapshot() {
    final t = now();
    if (pomodoro.inSession) {
      return SessionSnapshot(mode: 'pomodoro', courseLabel: courseLabel(pomodoro.courseId), savedAt: t, pomodoro: pomodoro.toJson());
    }
    if (flow.isBusy) {
      return SessionSnapshot(mode: 'flow', courseLabel: courseLabel(flow.courseId), savedAt: t, flow: flow.toJson());
    }
    return null;
  }

  /// Enregistre l'état de la séance et met à jour la notification / l'alarme (seulement si le plan a changé).
  Future<void> sync({bool force = false}) async {
    final snap = _snapshot();
    if (snap == null) {
      store.clear();
    } else {
      store.save(snap);
    }
    final plan = snap == null ? SessionPlan.inactive : planSession(snap, now());
    if (!force && plan.key == _lastKey) return;
    _lastKey = plan.key;
    try {
      await backend.apply(plan);
    } catch (e) {
      // la notification est un confort : l'appli ne doit jamais planter à cause d'elle
      if (!_errorReported) {
        _errorReported = true;
        onError?.call(e);
      }
    }
  }

  /// Au démarrage : remet les moteurs dans l'état de la séance sauvegardée, s'il y en a une.
  RestoreResult restore() {
    final snap = store.load();
    if (snap == null) return RestoreResult.none;
    if (snap.mode == 'pomodoro') {
      pomodoro.restore(snap.pomodoro);
      if (!pomodoro.inSession) {
        store.clear();
        return RestoreResult.none;
      }
      var stale = false;
      if (pomodoro.isWork && pomodoro.elapsedSeconds > pomodoro.totalSeconds + staleOvertimeSeconds) {
        pomodoro.capElapsed(pomodoro.totalSeconds.toDouble());
        stale = true;
      }
      return RestoreResult('pomodoro', stale: stale);
    }
    flow.restore(snap.flow);
    if (!flow.isBusy) {
      store.clear();
      return RestoreResult.none;
    }
    var stale = false;
    if (flow.phase == FlowPhase.working && flow.elapsedSeconds > staleFlowSeconds) {
      flow.capElapsed(flowCapSeconds);
      stale = true;
    }
    return RestoreResult('flow', stale: stale);
  }
}
