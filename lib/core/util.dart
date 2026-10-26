import 'dart:math';

/// Utilitaires sans dépendance : identifiants, dates ISO, clés de date locales.

String pad2(int n) => n.toString().padLeft(2, '0');

/// Clé de date locale `AAAA-MM-JJ` (celle utilisée par les statistiques).
String dateKey(DateTime d) {
  final l = d.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${pad2(l.month)}-${pad2(l.day)}';
}

/// Date ISO-8601 en UTC, précision milliseconde (même format que l'ancienne appli).
String isoUtc(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
      d.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();

/// Convertit `AAAA-MM-JJ` en date locale à minuit ; `null` si invalide.
DateTime? parseDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

final Random _rng = Random.secure();

/// UUID v4 (sans paquet externe).
String newId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

/// Date ISO la plus ancienne possible, pour les anciennes données sans horodatage.
const String epochIso = '1970-01-01T00:00:00.000Z';

/// Compare deux dates ISO ; une valeur illisible vaut « très ancienne ».
int compareIso(String a, String b) {
  final da = DateTime.tryParse(a)?.millisecondsSinceEpoch ?? 0;
  final db = DateTime.tryParse(b)?.millisecondsSinceEpoch ?? 0;
  return da.compareTo(db);
}
