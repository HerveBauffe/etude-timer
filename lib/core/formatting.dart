import 'util.dart';

const List<String> monthsFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const List<String> monthsFrShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];
const List<String> weekdaysFrShort = ['dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.'];

/// `MM:SS` ou `HH:MM:SS`.
String formatHMS(num totalSeconds) {
  final s = totalSeconds.round().clamp(0, 1 << 40);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '${pad2(h)}:${pad2(m)}:${pad2(sec)}';
  return '${pad2(m)}:${pad2(sec)}';
}

/// « 45 min », « 2 h », « 1 h 05 ».
String formatMinutesLabel(num totalSeconds) {
  final totalMin = (totalSeconds / 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h ${pad2(m)}';
}

String monthLabel(int year, int monthIndex) => '${monthsFr[monthIndex]} $year';

/// Lundi de la semaine (minuit local).
DateTime startOfWeek(DateTime d) {
  final day = (d.weekday + 6) % 7; // lundi = 0
  return DateTime(d.year, d.month, d.day - day);
}

/// Numéro de semaine ISO-8601, sous la forme « S42 ».
String isoWeekLabel(DateTime d) {
  final date = DateTime.utc(d.year, d.month, d.day);
  final dayNum = (date.weekday + 6) % 7;
  final thursday = date.add(Duration(days: 3 - dayNum));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final week = 1 + ((thursday.difference(firstThursday).inDays - 3 + ((firstThursday.weekday + 6) % 7)) / 7).round();
  return 'S$week';
}

/// « aujourd'hui », « hier », « il y a 3 jours », « le 5 mars 2025 ».
String relativeDate(String iso, {DateTime? now}) {
  final d = (DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
  final n = now ?? DateTime.now();
  final a = DateTime(n.year, n.month, n.day);
  final b = DateTime(d.year, d.month, d.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return "aujourd'hui";
  if (diff == 1) return 'hier';
  if (diff > 1 && diff < 7) return 'il y a $diff jours';
  final year = d.year != n.year ? ' ${d.year}' : '';
  return 'le ${d.day} ${monthsFrShort[d.month - 1]}$year';
}

String timeOfDay(String iso) {
  final d = (DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
  return '${pad2(d.hour)}:${pad2(d.minute)}';
}

/// « 5/3 » à partir d'une date.
String shortDate(DateTime d) => '${d.day}/${d.month}';

/// « 5/3 » à partir de `AAAA-MM-JJ`.
String shortDateKey(String key) {
  final d = parseDateKey(key);
  return d == null ? key : shortDate(d);
}
