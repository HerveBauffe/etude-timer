import 'dart:convert';
import 'dart:io';

import 'package:etude_timer/core/data_store.dart';
import 'package:etude_timer/core/device_config.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Le fichier de test `fixtures/legacy_electron_v1_1_0.json` a été produit par le VRAI code de
/// stockage de la version Electron 1.1.0 (store.js), pas écrit à la main. Valeurs de référence
/// relevées avec l'ancienne appli : 15 600 s de travail au total, dont 9 900 s pendant le
/// « Blocus janvier 2027 ».
void main() {
  late FakeClock clock;
  late Device dev;

  setUp(() {
    clock = FakeClock();
    dev = Device.create(clock);
    File('${dev.dir.path}/data.json').writeAsStringSync(File('test/fixtures/legacy_electron_v1_1_0.json').readAsStringSync());
  });

  test('toutes les données de l\'ancienne appli sont reprises, mêmes totaux', () {
    final s = DataStore(dev.paths, now: clock.call)..load();
    final d = s.data;
    expect([d.folders.length, d.ues.length, d.courses.length, d.sessions.length, d.blocus.length], equals([2, 3, 4, 8, 2]));
    expect(d.ues.where((u) => u.archived), hasLength(1));
    final work = workSessions(d);
    expect(totalSeconds(work), equals(15600));
    final rows = blocusRows(work, d.blocus);
    expect(rows.first.blocus.name, equals('Blocus janvier 2027'));
    expect(rows.first.seconds, equals(9900));
    expect(rows.last.seconds, equals(0));
    expect(d.sessions.any((x) => x.note == 'repartir de la page 88'), isTrue);
    expect(d.settings.workMin, equals(45));
    expect(d.settings.blocksBeforeLongBreak, equals(3));
    expect(d.settings.flowBreakPercent, equals(30));
  });

  test('l\'ancien thème « système » n\'est pas repris : la nouvelle appli est sombre', () {
    final raw = jsonDecode(File('test/fixtures/legacy_electron_v1_1_0.json').readAsStringSync()) as Map<String, Object?>;
    expect((raw['settings'] as Map)['theme'], equals('system'));
    final s = DataStore(dev.paths, now: clock.call)..load();
    expect(s.data.settings.themeMode, equals('dark'));
    expect(s.data.settings.palette, equals('mono'));
  });

  test('un fichier 2.x garde le thème choisi (clair / système)', () {
    final s = DataStore(dev.paths, now: clock.call)..load();
    s.updateSettings((x) => x.themeMode = 'light');
    final again = DataStore(dev.paths, now: clock.call)..load();
    expect(again.data.settings.themeMode, equals('light'));
    s.updateSettings((x) => x.themeMode = 'system');
    expect((DataStore(dev.paths, now: clock.call)..load()).data.settings.themeMode, equals('system'));
  });

  test('réglages WebDAV repris une seule fois dans device.json, absents du nouveau data.json', () {
    final s = DataStore(dev.paths, now: clock.call)..load();
    final cfg = DeviceConfig(dev.paths)..load();
    cfg.migrateLegacy(s.data.legacyWebdav, s.data.legacyLastSyncedAt);
    expect(cfg.webdav.enabled, isTrue);
    expect(cfg.webdav.username, equals('hervé'));
    expect(cfg.webdav.autoSyncMinutes, equals(7));
    s.addUE('Déclenche une réécriture');
    final written = File(s.filePath).readAsStringSync();
    expect(written.contains('mdp-appli'), isFalse);
    expect(written.contains('cloud.exemple.be'), isFalse);
    expect(jsonDecode(written)['version'], equals(AppData.currentVersion));
  });

  test('le fichier réécrit garde la structure 1.x (relisible par l\'ancienne appli)', () {
    final s = DataStore(dev.paths, now: clock.call)..load();
    s.addUE('Réécriture');
    final j = jsonDecode(File(s.filePath).readAsStringSync()) as Map<String, Object?>;
    for (final k in ['folders', 'ues', 'courses', 'sessions', 'blocus']) {
      expect(j[k], isA<List<Object?>>());
    }
    final session = (j['sessions'] as List).first as Map;
    for (final k in ['id', 'courseId', 'mode', 'kind', 'start', 'end', 'seconds', 'completed', 'date', 'note']) {
      expect(session.containsKey(k), isTrue);
    }
    final settings = j['settings'] as Map;
    expect((settings['pomodoro'] as Map).keys, containsAll2(['workMin', 'shortBreakMin', 'longBreakMin', 'blocksBeforeLongBreak']));
    expect((settings['flow'] as Map)['breakPercent'], equals(30));
  });
}

/// Petit utilitaire : vérifie que toutes les clés attendues sont présentes.
Matcher containsAll2(List<String> keys) => predicate((dynamic it) => keys.every((k) => (it as Iterable).contains(k)), 'contains all $keys');
