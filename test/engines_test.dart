import 'package:etude_timer/core/flow.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/pomodoro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late FakeClock clock;
  late Settings settings;
  late List<WorkLog> logs;
  late List<PomoEvent> events;
  late PomodoroEngine pomo;

  setUp(() {
    clock = FakeClock();
    settings = Settings(); // 25 / 5 / 15, 4 blocs
    logs = [];
    events = [];
    pomo = PomodoroEngine(
      settings: () => settings,
      now: clock.call,
      onWorkLogged: logs.add,
      onEvent: (e, c) => events.add(e),
    );
  });

  group('Pomodoro', () {
    test('démarre un bloc de 25 min et décompte', () {
      pomo.startWork('c1');
      expect(pomo.phase, PomoPhase.work);
      expect(pomo.remainingSeconds, closeTo(1500, 0.01));
      clock.advance(minutes: 10);
      expect(pomo.remainingSeconds, closeTo(900, 0.01));
      expect(pomo.isOvertime, isFalse);
    });

    test('à 25 min : notifie UNE fois, mais continue (dépassement)', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25, seconds: 1);
      pomo.tick();
      pomo.tick();
      expect(events, equals([PomoEvent.workTargetReached]));
      expect(pomo.phase, PomoPhase.work);
      expect(pomo.isOvertime, isTrue);
      clock.advance(minutes: 5);
      pomo.tick();
      expect(pomo.elapsedSeconds, closeTo(30 * 60 + 1, 0.01));
      expect(logs, isEmpty); // rien d'enregistré tant qu'on n'a pas terminé
    });

    test('pause / reprise : le temps en pause ne compte pas', () {
      pomo.startWork('c1');
      clock.advance(minutes: 10);
      pomo.togglePause();
      expect(pomo.paused, isTrue);
      clock.advance(minutes: 30);
      pomo.tick();
      expect(pomo.elapsedSeconds, closeTo(600, 0.01));
      pomo.togglePause();
      clock.advance(minutes: 5);
      expect(pomo.elapsedSeconds, closeTo(900, 0.01));
    });

    test('pas de notification de dépassement pendant la pause', () {
      pomo.startWork('c1');
      clock.advance(minutes: 24);
      pomo.togglePause();
      clock.advance(minutes: 60);
      pomo.tick();
      expect(events, isEmpty);
    });

    test('« Passer » depuis le travail : enregistre le bloc puis lance la pause courte', () {
      pomo.startWork('c1');
      clock.advance(minutes: 12);
      pomo.skip();
      expect(logs, hasLength(1));
      expect(logs.first.courseId, equals('c1'));
      expect(logs.first.seconds, equals(720));
      expect(logs.first.mode, equals('pomodoro'));
      expect(pomo.phase, PomoPhase.shortBreak);
      expect(pomo.totalSeconds, equals(300));
    });

    test('« Passer » depuis une pause : bloc suivant tout de suite, la pause n\'est jamais enregistrée', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      clock.advance(minutes: 2);
      pomo.skip();
      expect(logs, hasLength(1));
      expect(pomo.phase, PomoPhase.work);
      expect(pomo.blockIndex, equals(2));
    });

    test('pause longue après N blocs, puis le compteur repart à 1', () {
      settings.blocksBeforeLongBreak = 2;
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip(); // pause courte
      pomo.skip(); // bloc 2
      expect(pomo.blockIndex, equals(2));
      clock.advance(minutes: 25);
      pomo.skip(); // → pause longue
      expect(pomo.phase, PomoPhase.longBreak);
      expect(pomo.totalSeconds, equals(900));
      pomo.skip();
      expect(pomo.phase, PomoPhase.work);
      expect(pomo.blockIndex, equals(1));
    });

    test('fin naturelle d\'une pause courte : attend un démarrage manuel, rien d\'enregistré', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      logs.clear();
      clock.advance(minutes: 5, seconds: 1);
      pomo.tick();
      expect(pomo.phase, PomoPhase.breakEnded);
      expect(pomo.blockIndex, equals(2));
      expect(events, equals([PomoEvent.shortBreakEnded]));
      expect(logs, isEmpty);
      pomo.startWork('c1');
      expect(pomo.phase, PomoPhase.work);
      expect(pomo.blockIndex, equals(2));
    });

    test('fin naturelle d\'une pause longue : cycle terminé', () {
      settings.blocksBeforeLongBreak = 1;
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      expect(pomo.phase, PomoPhase.longBreak);
      clock.advance(minutes: 16);
      pomo.tick();
      expect(pomo.phase, PomoPhase.cycleComplete);
      expect(events, equals([PomoEvent.longBreakEnded]));
      pomo.startWork('c1');
      expect(pomo.blockIndex, equals(1));
    });

    test('terminer la session : enregistre le travail en cours et retourne le cours', () {
      pomo.startWork('c1');
      clock.advance(minutes: 7);
      final c = pomo.endSession();
      expect(c, equals('c1'));
      expect(logs, hasLength(1));
      expect(logs.first.seconds, equals(420));
      expect(pomo.phase, PomoPhase.idle);
    });

    test('terminer pendant une pause : rien d\'enregistré en plus', () {
      pomo.startWork('c1');
      clock.advance(minutes: 25);
      pomo.skip();
      logs.clear();
      clock.advance(minutes: 2);
      pomo.endSession();
      expect(logs, isEmpty);
      expect(pomo.phase, PomoPhase.idle);
    });

    test('terminer un bloc de moins d\'une seconde : rien d\'enregistré', () {
      pomo.startWork('c1');
      pomo.endSession();
      expect(logs, isEmpty);
    });

    test('terminer en dépassement : enregistre tout le temps (pas plafonné à 25 min)', () {
      pomo.startWork('c1');
      clock.advance(minutes: 40);
      pomo.endSession();
      expect(logs.single.seconds, equals(2400));
    });

    test('respecte une durée de bloc personnalisée', () {
      settings.workMin = 50;
      pomo.startWork('c1');
      expect(pomo.totalSeconds, equals(3000));
    });
  });

  group('Flow Zone', () {
    late FlowEngine flow;
    late List<WorkLog> flowLogs;
    late List<String> flowNotes;
    late List<String?> breakEnds;

    setUp(() {
      flowLogs = [];
      flowNotes = [];
      breakEnds = [];
      flow = FlowEngine(
        settings: () => settings,
        now: clock.call,
        onWorkLogged: (l, n) {
          flowLogs.add(l);
          flowNotes.add(n);
        },
        onBreakEnded: breakEnds.add,
      );
    });

    test('chronomètre puis bilan avec pause méritée = 20 % du temps travaillé', () {
      flow.start('c1');
      clock.advance(minutes: 50);
      flow.stop();
      expect(flow.phase, FlowPhase.review);
      expect(flow.reviewSeconds, equals(3000));
      expect(flow.earnedBreakSeconds(3000), equals(600));
    });

    test('enregistrer avec pause : séance enregistrée avec sa note, puis pause décomptée', () {
      flow.start('c1');
      clock.advance(minutes: 50);
      flow.stop();
      flow.confirmReview(withBreak: true, note: 'page 42');
      expect(flowLogs.single.seconds, equals(3000));
      expect(flowLogs.single.mode, equals('flow'));
      expect(flowNotes.single, equals('page 42'));
      expect(flow.phase, FlowPhase.breakTime);
      expect(flow.breakRemainingSeconds, closeTo(600, 0.01));
      clock.advance(minutes: 10, seconds: 1);
      flow.tick();
      expect(flow.phase, FlowPhase.idle);
      expect(breakEnds, equals(['c1']));
      expect(flowLogs, hasLength(1)); // la pause n'est jamais enregistrée
    });

    test('enregistrer sans pause : retour au repos', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      flow.stop();
      flow.confirmReview(withBreak: false);
      expect(flow.phase, FlowPhase.idle);
      expect(flowLogs, hasLength(1));
    });

    test('pourcentage réglable, pause d\'au moins 1 s', () {
      settings.flowBreakPercent = 50;
      expect(flow.earnedBreakSeconds(600), equals(300));
      expect(flow.earnedBreakSeconds(0), equals(1));
    });

    test('« Arrêter la pause » revient au repos', () {
      flow.start('c1');
      clock.advance(minutes: 10);
      flow.stop();
      flow.confirmReview(withBreak: true);
      flow.stopBreak();
      expect(flow.phase, FlowPhase.idle);
      expect(breakEnds, isEmpty);
    });

    test('fermeture de l\'appli en plein travail : le temps est enregistré', () {
      flow.start('c1');
      clock.advance(minutes: 20);
      expect(flow.flushOnClose(), isTrue);
      expect(flowLogs.single.seconds, equals(1200));
      expect(flow.phase, FlowPhase.idle);
    });
  });
}
