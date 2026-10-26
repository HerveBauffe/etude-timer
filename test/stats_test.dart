import 'package:etude_timer/core/formatting.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

Session s(String date, int minutes, {String course = 'c1', SessionKind kind = SessionKind.work}) => Session(
      id: '$date-$minutes-$course-${kind.name}',
      courseId: course,
      mode: 'pomodoro',
      kind: kind,
      start: '${date}T10:00:00.000Z',
      end: '${date}T11:00:00.000Z',
      seconds: minutes * 60,
      date: date,
    );

void main() {
  group('formatage', () {
    test('formatHMS', () {
      expect(formatHMS(0), equals('00:00'));
      expect(formatHMS(65), equals('01:05'));
      expect(formatHMS(3725), equals('01:02:05'));
      expect(formatHMS(-5), equals('00:00'));
    });
    test('formatMinutesLabel', () {
      expect(formatMinutesLabel(45 * 60), equals('45 min'));
      expect(formatMinutesLabel(120 * 60), equals('2 h'));
      expect(formatMinutesLabel(65 * 60), equals('1 h 05'));
      expect(formatMinutesLabel(0), equals('0 min'));
    });
    test('numéro de semaine ISO', () {
      expect(isoWeekLabel(DateTime(2026, 1, 1)), equals('S1'));
      expect(isoWeekLabel(DateTime(2026, 10, 23)), equals('S43'));
      expect(isoWeekLabel(DateTime(2024, 12, 30)), equals('S1'));
      expect(isoWeekLabel(DateTime(2021, 1, 3)), equals('S53'));
    });
    test('startOfWeek tombe un lundi', () {
      expect(startOfWeek(DateTime(2026, 10, 23)), equals(DateTime(2026, 10, 19)));
      expect(startOfWeek(DateTime(2026, 10, 25)), equals(DateTime(2026, 10, 19)));
      expect(startOfWeek(DateTime(2026, 10, 19)), equals(DateTime(2026, 10, 19)));
    });
    test('date relative', () {
      final now = DateTime(2026, 10, 23, 12);
      expect(relativeDate(DateTime(2026, 10, 23, 8).toIso8601String(), now: now), equals("aujourd'hui"));
      expect(relativeDate(DateTime(2026, 10, 22, 23).toIso8601String(), now: now), equals('hier'));
      expect(relativeDate(DateTime(2026, 10, 20, 9).toIso8601String(), now: now), equals('il y a 3 jours'));
      expect(relativeDate(DateTime(2026, 3, 5, 9).toIso8601String(), now: now), equals('le 5 mars'));
      expect(relativeDate(DateTime(2025, 3, 5, 9).toIso8601String(), now: now), equals('le 5 mars 2025'));
    });
  });

  group('statistiques', () {
    final now = DateTime(2026, 10, 23, 15); // vendredi, semaine du 19/10
    final data = AppData(sessions: [
      s('2026-10-23', 30),
      s('2026-10-20', 60),
      s('2026-10-05', 45),
      s('2026-09-30', 20),
      s('2026-10-23', 15, course: 'c2'),
      s('2026-10-23', 5, kind: SessionKind.brk),
      s('2026-10-23', 0, kind: SessionKind.note),
    ]);

    test('seul le temps de travail compte', () {
      expect(workSessions(data), hasLength(5));
      expect(workSessions(data, courseId: 'c1'), hasLength(4));
    });

    test('cartes aujourd\'hui / semaine / mois', () {
      final c = summaryCards(workSessions(data), now);
      expect(c.todaySeconds, equals(45 * 60));
      expect(c.weekSeconds, equals(105 * 60));
      expect(c.monthSeconds, equals(150 * 60));
    });

    test('filtre par cours', () {
      final c = summaryCards(workSessions(data, courseId: 'c2'), now);
      expect(c.todaySeconds, equals(15 * 60));
      expect(c.monthSeconds, equals(15 * 60));
    });

    test('minutes par jour et série continue', () {
      final m = minutesByDate(workSessions(data));
      expect(m['2026-10-23'], equals(45));
      final series = dailySeries(workSessions(data), 7, now);
      expect(series, hasLength(7));
      expect(series.last.date, equals('2026-10-23'));
      expect(series.last.minutes, equals(45));
      expect(series.first.date, equals('2026-10-17'));
      expect(series.first.minutes, equals(0));
    });

    test('détail hebdomadaire d\'un mois', () {
      final w = monthWeeks(workSessions(data), 2026, 10);
      expect(w.map((e) => e.label).toList(), equals(['S41', 'S43']));
      expect(w[0].seconds, equals(45 * 60));
      expect(w[1].seconds, equals(105 * 60));
      expect(w[1].from, equals(DateTime(2026, 10, 19)));
      expect(w[1].to, equals(DateTime(2026, 10, 25)));
      expect(monthTotalSeconds(workSessions(data), 2026, 10), equals(150 * 60));
      expect(monthTotalSeconds(workSessions(data), 2026, 9), equals(20 * 60));
    });

    test('blocus : un total indépendant par blocus, bornes incluses, filtre par cours', () {
      final blocus = [
        Blocus(id: 'b2', name: 'Blocus juin', startDate: '2026-10-20', endDate: '2026-10-23'),
        Blocus(id: 'b1', name: 'Blocus jan', startDate: '2026-09-28', endDate: '2026-10-05'),
      ];
      final all = blocusRows(workSessions(data), blocus);
      expect(all.map((r) => r.blocus.id).toList(), equals(['b1', 'b2'])); // trié par date de début
      expect(all[0].seconds, equals(65 * 60)); // 30/09 (20) + 05/10 (45)
      expect(all[1].seconds, equals(105 * 60)); // 20/10 (60) + 23/10 (30+15)
      final c1 = blocusRows(workSessions(data, courseId: 'c1'), blocus);
      expect(c1[1].seconds, equals(90 * 60));
      expect(totalSeconds(workSessions(data, courseId: 'c1')), equals(155 * 60));
    });

    test('niveaux de la carte thermique', () {
      expect([0, 1, 29, 30, 59, 60, 119, 120, 500].map(heatLevel).toList(), equals([0, 1, 1, 2, 2, 3, 3, 4, 4]));
    });

    test('grille de la carte thermique : 53 semaines, lundi→dimanche, finit cette semaine', () {
      final g = heatmapGrid(now);
      expect(g, hasLength(53));
      expect(g.every((w) => w.length == 7), isTrue);
      expect(g.last.first, equals(DateTime(2026, 10, 19)));
      expect(g.last.last, equals(DateTime(2026, 10, 25)));
      expect(g.first.first.weekday, equals(DateTime.monday));
    });
  });
}
