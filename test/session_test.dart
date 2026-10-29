import 'dart:io';

import 'package:etude_timer/core/flow.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/pomodoro.dart';
import 'package:etude_timer/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _Backend implements SessionBackend {
  final List<SessionPlan> plans = [];
  bool failing = false;
  @override
  Future<void> apply(SessionPlan plan) async {
    if (failing) throw StateError('notification indisponible');
    plans.add(plan);
  }
}

void main() {
  late FakeClock clock;
  late PomodoroEngine pomo;
  late FlowEngine flow;

  PomodoroEngine newPomo() => PomodoroEngine(settings: Settings.new, onWorkLogged: (_) {}, onEvent: (_, __) {}, now: clock.call);
  FlowEngine newFlow() => FlowEngine(settings: Settings.new, onWorkLogged: (_, __) {}, onBreakEnded: (_) {}, now: clock.call);

  setUp(() {
    clock = FakeClock();
    pomo = newPomo();
    flow = newFlow();
  });

  group('Flow Zone : pause / reprise', () {
    test('le temps en pause n\'est pas compté', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      flow.togglePause();
      expect(flow.paused, isTrue);
      clock.advance(minutes: 30); // pause
      expect(flow.elapsedSeconds, equals(600));
      flow.togglePause();
      clock.advance(minutes: 5);
      expect(flow.elapsedSeconds, equals(900));
    });

    test('arrêter pendant la pause : le bilan reprend le temps travaillé', () {
      flow.start('c1');
      clock.advance(minutes: 20);
      flow.togglePause();
      clock.advance(minutes: 10);
      flow.stop();
      expect(flow.phase, FlowPhase.review);
      expect(flow.reviewSeconds, equals(1200));
      expect(flow.paused, isFalse);
    });

    test('fermeture en pause : enregistre le temps travaillé', () {
      final logged = <WorkLog>[];
      final f = FlowEngine(settings: Settings.new, onWorkLogged: (l, _) => logged.add(l), onBreakEnded: (_) {}, now: clock.call);
      f.start('c1');
      clock.advance(minutes: 12);
      f.togglePause();
      clock.advance(hours: 2);
      expect(f.flushOnClose(), isTrue);
      expect(logged.single.seconds, equals(720));
    });
  });

  group('moteurs : reprise après arrêt du processus', () {
    test('Pomodoro en cours : le temps « mort » compte (chrono basé sur l\'horloge)', () {
      pomo.startWork('c1');
      clock.advance(minutes: 10);
      final saved = pomo.toJson();
      clock.advance(minutes: 5); // appli tuée pendant 5 min
      final revived = newPomo()..restore(saved);
      expect(revived.phase, PomoPhase.work);
      expect(revived.courseId, 'c1');
      expect(revived.elapsedSeconds, closeTo(900, 1));
      expect(revived.remainingSeconds, closeTo(600, 1));
    });

    test('Pomodoro en pause : rien ne s\'écoule pendant que l\'appli est morte', () {
      pomo.startWork('c1');
      clock.advance(minutes: 7);
      pomo.togglePause();
      final saved = pomo.toJson();
      clock.advance(hours: 3);
      final revived = newPomo()..restore(saved);
      expect(revived.paused, isTrue);
      expect(revived.elapsedSeconds, closeTo(420, 1));
    });

    test('Pomodoro : objectif déjà dépassé à la reprise → pas de nouvelle alerte', () {
      var events = 0;
      pomo.startWork('c1');
      clock.advance(minutes: 40);
      final saved = pomo.toJson();
      final revived = PomodoroEngine(settings: Settings.new, onWorkLogged: (_) {}, onEvent: (_, __) => events++, now: clock.call)
        ..restore(saved);
      revived.tick();
      expect(events, equals(0));
      expect(revived.isOvertime, isTrue);
    });

    test('Flow en cours et Flow en pause', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      flow.togglePause();
      clock.advance(minutes: 20);
      flow.togglePause();
      clock.advance(minutes: 5);
      final saved = flow.toJson();
      clock.advance(minutes: 5);
      final revived = newFlow()..restore(saved);
      expect(revived.phase, FlowPhase.working);
      expect(revived.elapsedSeconds, equals(20 * 60));
    });

    test('JSON incomplet ou inconnu : retour au repos, sans exception', () {
      expect((newPomo()..restore({'phase': 'nimportequoi'})).phase, PomoPhase.idle);
      expect((newPomo()..restore({'phase': 'work', 'paused': false})).phase, PomoPhase.idle);
      expect((newFlow()..restore({'phase': 'working'})).phase, FlowPhase.idle);
      expect((newFlow()..restore({})).phase, FlowPhase.idle);
    });
  });

  group('plan de notification', () {
    SessionSnapshot snapPomo(String label) =>
        SessionSnapshot(mode: 'pomodoro', courseLabel: label, savedAt: clock.t, pomodoro: pomo.toJson());
    SessionSnapshot snapFlow(String label) => SessionSnapshot(mode: 'flow', courseLabel: label, savedAt: clock.t, flow: flow.toJson());

    test('bloc de travail en cours : compte à rebours natif + alarme à l\'objectif', () {
      pomo.startWork('c1');
      clock.advance(minutes: 5);
      final plan = planSession(snapPomo('UE — Cours'), clock.t);
      final target = clock.t.add(const Duration(minutes: 20)).millisecondsSinceEpoch;
      expect(plan.active, isTrue);
      expect(plan.ticking, isTrue);
      expect(plan.countDown, isTrue);
      expect(plan.chronoMs, closeTo(target, 5));
      expect(plan.alarmAtMs, closeTo(target, 5));
      expect(plan.title, contains('UE — Cours'));
      expect(plan.body, contains('Bloc 1'));
      expect(plan.canToggle, isTrue);
      expect(plan.alarmTitle, 'Bloc terminé');
    });

    test('plan stable : une fraction de seconde plus tard, même plan (pas de ré-application)', () {
      pomo.startWork('c1');
      clock.advance(minutes: 5);
      final a = planSession(snapPomo('X'), clock.t).key;
      final b = planSession(snapPomo('X'), clock.t.add(const Duration(milliseconds: 400))).key;
      expect(a, equals(b));
    });

    test('dépassement : le chrono repart à 0 à l\'objectif, plus d\'alarme', () {
      pomo.startWork('c1');
      clock.advance(minutes: 30);
      final plan = planSession(snapPomo('X'), clock.t);
      final target = clock.t.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      expect(plan.ticking, isTrue);
      expect(plan.countDown, isFalse);
      expect(plan.chronoMs, closeTo(target, 5));
      expect(plan.alarmAtMs, isNull);
      expect(plan.body, contains('Objectif atteint'));
    });

    test('en pause : pas de chrono natif, texte fixe avec le temps restant, bouton « reprendre »', () {
      pomo.startWork('c1');
      clock.advance(minutes: 10);
      pomo.togglePause();
      final plan = planSession(snapPomo('X'), clock.t.add(const Duration(hours: 1)));
      expect(plan.paused, isTrue);
      expect(plan.ticking, isFalse);
      expect(plan.alarmAtMs, isNull);
      expect(plan.body, contains('15:00'));
      expect(plan.canToggle, isTrue);
    });

    test('en pause avec dépassement : le temps au-delà de l\'objectif est indiqué', () {
      pomo.startWork('c1');
      clock.advance(minutes: 28);
      pomo.togglePause();
      expect(planSession(snapPomo('X'), clock.t).body, contains('+03:00'));
    });

    test('pause de repos : compte à rebours + alarme « Pause terminée »', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      final plan = planSession(snapPomo('X'), clock.t);
      expect(plan.title, startsWith('Pause'));
      expect(plan.countDown, isTrue);
      expect(plan.alarmTitle, 'Pause terminée');
      expect(plan.alarmAtMs, closeTo(clock.t.add(const Duration(minutes: 5)).millisecondsSinceEpoch, 5));
    });

    test('attente d\'un démarrage manuel (pause finie) : plus de service', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      clock.advance(minutes: 6);
      pomo.tick();
      expect(pomo.phase, PomoPhase.breakEnded);
      expect(planSession(snapPomo('X'), clock.t).active, isFalse);
    });

    test('Flow : chrono natif croissant, décalé par les pauses', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      var plan = planSession(snapFlow('X'), clock.t);
      expect(plan.ticking, isTrue);
      expect(plan.countDown, isFalse);
      expect(plan.chronoMs, closeTo(clock.t.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch, 5));
      flow.togglePause();
      clock.advance(minutes: 30);
      flow.togglePause();
      clock.advance(minutes: 2);
      plan = planSession(snapFlow('X'), clock.t);
      expect(plan.chronoMs, closeTo(clock.t.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch, 5));
      expect(plan.alarmAtMs, isNull);
    });

    test('Flow : bilan = pas de service ; pause méritée = compte à rebours + alarme, sans bouton pause', () {
      flow.start('c1');
      clock.advance(minutes: 30);
      flow.stop();
      expect(planSession(snapFlow('X'), clock.t).active, isFalse);
      flow.confirmReview(withBreak: true);
      final plan = planSession(snapFlow('X'), clock.t);
      expect(plan.active, isTrue);
      expect(plan.countDown, isTrue);
      expect(plan.alarmAtMs, isNotNull);
      expect(plan.canToggle, isFalse);
    });

    test('le libellé du cours vide ne laisse pas de « · » orphelin', () {
      pomo.startWork('c1');
      expect(planSession(snapPomo(''), clock.t).title, equals('Travail'));
    });
  });

  group('bouton Pause/Reprendre sans l\'appli en mémoire', () {
    test('Pomodoro : pause puis reprise sur la séance sauvegardée', () {
      pomo.startWork('c1');
      clock.advance(minutes: 10);
      var snap = SessionSnapshot(mode: 'pomodoro', courseLabel: 'X', savedAt: clock.t, pomodoro: pomo.toJson());

      snap = toggledSnapshot(snap, clock.t)!; // pause à 10 min
      clock.advance(hours: 1);
      snap = toggledSnapshot(snap, clock.t)!; // reprise
      clock.advance(minutes: 5);

      final revived = newPomo()..restore(snap.pomodoro);
      expect(revived.paused, isFalse);
      expect(revived.elapsedSeconds, closeTo(900, 1));
    });

    test('Flow : pause, et rien à basculer pendant la pause méritée', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      var snap = SessionSnapshot(mode: 'flow', courseLabel: 'X', savedAt: clock.t, flow: flow.toJson());
      snap = toggledSnapshot(snap, clock.t)!;
      expect(newFlow().let((f) => f..restore(snap.flow)).paused, isTrue);

      final g = newFlow()..start('c1');
      clock.advance(minutes: 1);
      g.stop();
      g.confirmReview(withBreak: true);
      final breakSnap = SessionSnapshot(mode: 'flow', courseLabel: 'X', savedAt: clock.t, flow: g.toJson());
      expect(toggledSnapshot(breakSnap, clock.t), isNull);
    });
  });

  group('fichier de séance', () {
    late Directory dir;
    late SessionStore store;
    setUp(() {
      dir = tempDir('session');
      store = SessionStore('${dir.path}/session.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('aller-retour, effacement, fichier corrompu ignoré', () {
      expect(store.load(), isNull);
      pomo.startWork('c1');
      store.save(SessionSnapshot(mode: 'pomodoro', courseLabel: 'UE — Cours', savedAt: clock.t, pomodoro: pomo.toJson()));
      final back = store.load()!;
      expect(back.mode, 'pomodoro');
      expect(back.courseLabel, 'UE — Cours');
      expect(back.pomodoro['phase'], 'work');
      store.clear();
      expect(store.load(), isNull);
      File('${dir.path}/session.json').writeAsStringSync('{pas du json');
      expect(store.load(), isNull);
      File('${dir.path}/session.json').writeAsStringSync('{"mode":"autre"}');
      expect(store.load(), isNull);
    });
  });

  group('coordination', () {
    late Directory dir;
    late SessionStore store;
    late _Backend backend;
    late SessionCoordinator coord;
    setUp(() {
      dir = tempDir('coord');
      store = SessionStore('${dir.path}/session.json');
      backend = _Backend();
      coord = SessionCoordinator(
        pomodoro: pomo,
        flow: flow,
        store: store,
        backend: backend,
        courseLabel: (id) => id == null ? '' : 'Cours $id',
        now: clock.call,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('sync : enregistre la séance, applique le plan, ne répète pas un plan identique', () async {
      await coord.sync(); // repos : un « inactif » initial
      expect(backend.plans.single.active, isFalse);
      pomo.startWork('c1');
      await coord.sync();
      expect(store.load()!.courseLabel, 'Cours c1');
      expect(backend.plans.last.active, isTrue);
      final n = backend.plans.length;
      await coord.sync(); // rien n'a changé
      expect(backend.plans.length, equals(n));
      pomo.togglePause();
      await coord.sync();
      expect(backend.plans.last.paused, isTrue);
      await coord.sync(force: true);
      expect(backend.plans.length, equals(n + 2));
    });

    test('fin de séance : fichier supprimé, service arrêté', () async {
      pomo.startWork('c1');
      clock.advance(minutes: 3);
      await coord.sync();
      pomo.endSession();
      await coord.sync();
      expect(store.load(), isNull);
      expect(backend.plans.last.active, isFalse);
    });

    test('une erreur de la notification ne remonte pas à l\'appli', () async {
      backend.failing = true;
      pomo.startWork('c1');
      await coord.sync(); // ne doit pas lever
      expect(store.load(), isNotNull); // la séance reste sauvegardée
    });

    test('restore : retrouve la séance et continue le temps écoulé', () async {
      pomo.startWork('c1');
      clock.advance(minutes: 10);
      await coord.sync();
      // « l'appli est tuée » : nouveaux moteurs, même fichier, 5 minutes plus tard
      clock.advance(minutes: 5);
      final p2 = newPomo();
      final f2 = newFlow();
      final c2 = SessionCoordinator(pomodoro: p2, flow: f2, store: store, backend: backend, courseLabel: (_) => '', now: clock.call);
      final r = c2.restore();
      expect(r.restored, isTrue);
      expect(r.mode, 'pomodoro');
      expect(r.stale, isFalse);
      expect(p2.courseId, 'c1');
      expect(p2.elapsedSeconds, closeTo(900, 1));
    });

    test('restore : séance Pomodoro très ancienne → plafonnée à l\'objectif et mise en pause', () async {
      pomo.startWork('c1');
      await coord.sync();
      clock.advance(hours: 9);
      final p2 = newPomo();
      final c2 = SessionCoordinator(pomodoro: p2, flow: newFlow(), store: store, backend: backend, courseLabel: (_) => '', now: clock.call);
      final r = c2.restore();
      expect(r.stale, isTrue);
      expect(p2.paused, isTrue);
      expect(p2.elapsedSeconds, closeTo(25 * 60, 1));
    });

    test('restore : chrono Flow oublié → plafonné et mis en pause', () async {
      flow.start('c1');
      await coord.sync();
      clock.advance(hours: 20);
      final f2 = newFlow();
      final c2 = SessionCoordinator(pomodoro: newPomo(), flow: f2, store: store, backend: backend, courseLabel: (_) => '', now: clock.call);
      final r = c2.restore();
      expect(r.mode, 'flow');
      expect(r.stale, isTrue);
      expect(f2.paused, isTrue);
      expect(f2.elapsedSeconds, equals(SessionCoordinator.flowCapSeconds));
    });

    test('restore : fichier au repos ou absent → rien', () {
      expect(coord.restore().restored, isFalse);
      store.save(SessionSnapshot(mode: 'pomodoro', courseLabel: '', savedAt: clock.t, pomodoro: {'phase': 'idle'}));
      expect(coord.restore().restored, isFalse);
      expect(store.load(), isNull); // nettoyé
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
