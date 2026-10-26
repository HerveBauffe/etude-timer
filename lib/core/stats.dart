import 'formatting.dart';
import 'models.dart';
import 'util.dart';

/// Calculs de statistiques (fonctions pures). Seul le temps `work` compte.

List<Session> workSessions(AppData data, {String? courseId}) => data.sessions
    .where((s) => s.kind == SessionKind.work && (courseId == null || s.courseId == courseId))
    .toList();

int sumSeconds(Iterable<Session> sessions, String fromKey, String toKey) {
  var total = 0;
  for (final s in sessions) {
    if (s.date.compareTo(fromKey) >= 0 && s.date.compareTo(toKey) <= 0) total += s.seconds;
  }
  return total;
}

class SummaryCards {
  final int todaySeconds;
  final int weekSeconds;
  final int monthSeconds;
  const SummaryCards(this.todaySeconds, this.weekSeconds, this.monthSeconds);
}

SummaryCards summaryCards(Iterable<Session> sessions, DateTime now) {
  final today = dateKey(now);
  final weekStart = dateKey(startOfWeek(now));
  final monthStart = '${now.year.toString().padLeft(4, '0')}-${pad2(now.month)}-01';
  return SummaryCards(
    sumSeconds(sessions, today, today),
    sumSeconds(sessions, weekStart, today),
    sumSeconds(sessions, monthStart, today),
  );
}

/// date (AAAA-MM-JJ) → minutes arrondies.
Map<String, int> minutesByDate(Iterable<Session> sessions) {
  final secs = <String, int>{};
  for (final s in sessions) {
    secs[s.date] = (secs[s.date] ?? 0) + s.seconds;
  }
  return secs.map((k, v) => MapEntry(k, (v / 60).round()));
}

class DayPoint {
  final String date;
  final int minutes;
  const DayPoint(this.date, this.minutes);
}

/// Série continue des `days` derniers jours (jours sans étude = 0).
List<DayPoint> dailySeries(Iterable<Session> sessions, int days, DateTime now) {
  final map = minutesByDate(sessions);
  final out = <DayPoint>[];
  for (var i = days - 1; i >= 0; i--) {
    final d = DateTime(now.year, now.month, now.day - i);
    final k = dateKey(d);
    out.add(DayPoint(k, map[k] ?? 0));
  }
  return out;
}

class WeekRow {
  final String label;
  final DateTime from;
  final DateTime to;
  final int seconds;
  const WeekRow(this.label, this.from, this.to, this.seconds);
}

/// Répartition hebdomadaire d'un mois (semaines du lundi au dimanche).
List<WeekRow> monthWeeks(Iterable<Session> sessions, int year, int month) {
  final first = DateTime(year, month, 1);
  final last = DateTime(year, month + 1, 0);
  final map = <DateTime, int>{};
  for (final s in sessions) {
    final d = parseDateKey(s.date);
    if (d == null || d.isBefore(first) || d.isAfter(last)) continue;
    final ws = startOfWeek(d);
    map[ws] = (map[ws] ?? 0) + s.seconds;
  }
  final starts = map.keys.toList()..sort();
  return [
    for (final ws in starts)
      WeekRow(isoWeekLabel(ws), ws, DateTime(ws.year, ws.month, ws.day + 6), map[ws]!),
  ];
}

int monthTotalSeconds(Iterable<Session> sessions, int year, int month) {
  final first = '${year.toString().padLeft(4, '0')}-${pad2(month)}-01';
  final last = dateKey(DateTime(year, month + 1, 0));
  return sumSeconds(sessions, first, last);
}

class BlocusRow {
  final Blocus blocus;
  final int seconds;
  const BlocusRow(this.blocus, this.seconds);
}

/// Un total indépendant par blocus, calculé sur les séances (déjà filtrées par cours si besoin).
List<BlocusRow> blocusRows(Iterable<Session> sessions, Iterable<Blocus> blocus) {
  final list = blocus.toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
  return [for (final b in list) BlocusRow(b, sumSeconds(sessions, b.startDate, b.endDate))];
}

int totalSeconds(Iterable<Session> sessions) => sessions.fold(0, (a, s) => a + s.seconds);

/// Niveau de la carte thermique (0 à 4).
int heatLevel(int minutes) {
  if (minutes <= 0) return 0;
  if (minutes < 30) return 1;
  if (minutes < 60) return 2;
  if (minutes < 120) return 3;
  return 4;
}

/// Jours de la carte thermique : `weeks` colonnes de 7 jours, lundi→dimanche,
/// la dernière colonne étant la semaine courante.
List<List<DateTime>> heatmapGrid(DateTime now, {int weeks = 53}) {
  final today = DateTime(now.year, now.month, now.day);
  final sunday = DateTime(today.year, today.month, today.day + (6 - ((today.weekday + 6) % 7)));
  final start = DateTime(sunday.year, sunday.month, sunday.day - weeks * 7 + 1);
  return [
    for (var w = 0; w < weeks; w++)
      [for (var d = 0; d < 7; d++) DateTime(start.year, start.month, start.day + w * 7 + d)],
  ];
}
