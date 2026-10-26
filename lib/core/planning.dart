import 'formatting.dart';
import 'models.dart';
import 'util.dart';

/// Logique du planning (révisions et examens), indépendante de l'interface.

/// Éléments d'un jour, filtrés par cours : examens d'abord (par heure), puis révisions (par titre).
List<PlanItem> plansOn(AppData d, String date, {Set<String>? courseIds}) {
  final l = d.plans.where((p) => p.date == date && (courseIds == null || courseIds.contains(p.courseId))).toList();
  l.sort(comparePlans);
  return l;
}

int comparePlans(PlanItem a, PlanItem b) {
  if (a.isExam != b.isExam) return a.isExam ? -1 : 1;
  if (a.isExam) {
    final c = (a.time ?? '99:99').compareTo(b.time ?? '99:99');
    if (c != 0) return c;
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Les 7 jours (lundi → dimanche) de la semaine contenant `anchor`.
List<DateTime> weekDays(DateTime anchor) {
  final monday = startOfWeek(anchor);
  return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
}

/// Grille d'un mois : lignes de 7 jours (lundi → dimanche) couvrant tout le mois (4 à 6 lignes).
List<List<DateTime>> monthGrid(int year, int month) {
  final first = DateTime(year, month, 1);
  final last = DateTime(year, month + 1, 0);
  var cur = startOfWeek(first);
  final weeks = <List<DateTime>>[];
  while (!cur.isAfter(last)) {
    weeks.add([for (var i = 0; i < 7; i++) DateTime(cur.year, cur.month, cur.day + i)]);
    cur = DateTime(cur.year, cur.month, cur.day + 7);
  }
  return weeks;
}

/// Prochain examen à partir d'aujourd'hui (inclus), parmi les cours donnés.
PlanItem? nextExam(AppData d, DateTime now, {Set<String>? courseIds}) {
  final today = dateKey(now);
  PlanItem? best;
  for (final p in d.plans) {
    if (!p.isExam || p.date.compareTo(today) < 0) continue;
    if (courseIds != null && !courseIds.contains(p.courseId)) continue;
    if (best == null) {
      best = p;
    } else {
      final c = p.date.compareTo(best.date);
      if (c < 0 || (c == 0 && (p.time ?? '99:99').compareTo(best.time ?? '99:99') < 0)) best = p;
    }
  }
  return best;
}

/// Nombre de jours entre aujourd'hui et la date (négatif si passée).
int daysUntil(String date, DateTime now) {
  final d = parseDateKey(date);
  if (d == null) return 0;
  final a = DateTime(now.year, now.month, now.day);
  return DateTime(d.year, d.month, d.day).difference(a).inDays;
}

String daysUntilLabel(int days) => switch (days) {
      0 => "aujourd'hui",
      1 => 'demain',
      -1 => 'hier',
      > 1 => 'dans $days j',
      _ => 'il y a ${-days} j',
    };

/// « 1 h 30 », « 45 min » pour une durée estimée en minutes.
String estimateLabel(int minutes) => formatMinutesLabel(minutes * 60);
