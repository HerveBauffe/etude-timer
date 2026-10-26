import 'dart:convert';
import 'dart:io';

import 'package:etude_timer/core/data_store.dart';
import 'package:etude_timer/core/device_config.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/paths.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late FakeClock clock;
  late Device dev;
  late DataStore store;

  setUp(() {
    clock = FakeClock();
    dev = Device.create(clock);
    store = dev.store;
  });

  group('arborescence', () {
    test('dossier > dossier > UE > cours, renommer', () {
      final year = store.addFolder('2026-2027');
      final q1 = store.addFolder('Quadri 1', parentId: year.id);
      final ue = store.addUE('Physique', folderId: q1.id);
      final c = store.addCourse('Mécanique', ue.id);
      store.renameCourse(c.id, 'Mécanique du point');
      store.renameUE(ue.id, 'Physique générale');
      store.renameFolder(q1.id, 'Q1');
      expect(store.data.courses.single.name, equals('Mécanique du point'));
      expect(store.data.ues.single.name, equals('Physique générale'));
      expect(store.data.folders.last.name, equals('Q1'));
    });

    test('supprimer un dossier : sous-dossiers supprimés, UE remontées à la racine', () {
      final a = store.addFolder('A');
      final b = store.addFolder('B', parentId: a.id);
      final ue = store.addUE('UE', folderId: b.id);
      store.deleteFolder(a.id);
      expect(store.data.folders, isEmpty);
      expect(store.data.ues.single.folderId, isNull);
      expect(store.data.ues.single.id, equals(ue.id));
      expect(store.data.tombstones.containsKey(a.id), isTrue);
      expect(store.data.tombstones.containsKey(b.id), isTrue);
    });

    test('supprimer une UE : ses cours et leurs séances disparaissent', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('Cours', ue.id);
      store.addManualTime(courseId: c.id, seconds: 600, date: '2026-10-01');
      final other = store.addUE('Autre');
      final oc = store.addCourse('Autre cours', other.id);
      store.addManualTime(courseId: oc.id, seconds: 60, date: '2026-10-01');
      store.deleteUE(ue.id);
      expect(store.data.ues, hasLength(1));
      expect(store.data.courses, hasLength(1));
      expect(store.data.sessions, hasLength(1));
    });

    test('archiver / désarchiver une UE conserve l\'historique', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('Cours', ue.id);
      store.addManualTime(courseId: c.id, seconds: 600, date: '2026-10-01');
      store.archiveUE(ue.id, true);
      expect(store.data.ues.single.archived, isTrue);
      expect(store.data.ues.single.archivedAt, isNotNull);
      expect(store.data.sessions, hasLength(1));
      store.archiveUE(ue.id, false);
      expect(store.data.ues.single.archived, isFalse);
      expect(store.data.ues.single.archivedAt, isNull);
    });
  });

  group('séances', () {
    late Course course;
    setUp(() {
      final ue = store.addUE('UE');
      course = store.addCourse('Cours', ue.id);
    });

    test('la date d\'une séance est la date LOCALE de début', () {
      final start = DateTime(2026, 10, 23, 23, 30);
      final s = store.addSession(courseId: course.id, mode: 'pomodoro', start: start, end: start.add(const Duration(minutes: 25)));
      expect(s.date, equals('2026-10-23'));
      expect(s.seconds, equals(1500));
    });

    test('temps manuel, correction de durée et de date', () {
      final s = store.addManualTime(courseId: course.id, seconds: 1800, date: '2026-10-10');
      expect(s.date, equals('2026-10-10'));
      expect(s.mode, isNull);
      store.updateSessionTime(s.id, seconds: 3600, date: '2026-10-11');
      final u = store.data.sessions.single;
      expect(u.seconds, equals(3600));
      expect(u.date, equals('2026-10-11'));
      expect(DateTime.parse(u.end).difference(DateTime.parse(u.start)).inSeconds, equals(3600));
    });

    test('note libre : durée nulle, retrouvée par la bannière « Reprise »', () {
      store.addSession(courseId: course.id, kind: SessionKind.note, start: clock.t, end: clock.t, note: '  page 12  ');
      expect(store.data.sessions.single.seconds, equals(0));
      expect(store.lastNoteFor(course.id)!.note, equals('page 12'));
      clock.advance(hours: 1);
      store.addSession(courseId: course.id, kind: SessionKind.note, start: clock.t, end: clock.t, note: 'page 20');
      expect(store.lastNoteFor(course.id)!.note, equals('page 20'));
    });

    test('supprimer une séance', () {
      final s = store.addManualTime(courseId: course.id, seconds: 60, date: '2026-10-10');
      store.deleteSession(s.id);
      expect(store.data.sessions, isEmpty);
      expect(store.data.tombstones.containsKey(s.id), isTrue);
    });
  });

  group('blocus', () {
    test('plusieurs blocus indépendants, dates inversées corrigées', () {
      final b = store.addBlocus('Janvier', '2027-01-20', '2027-01-05');
      expect(b.startDate, equals('2027-01-05'));
      expect(b.endDate, equals('2027-01-20'));
      store.addBlocus('Juin', '2027-06-01', '2027-06-20');
      expect(store.data.blocus, hasLength(2));
      store.updateBlocus(b.id, name: 'Blocus de janvier', endDate: '2027-01-01');
      final u = store.data.blocus.first;
      expect(u.name, equals('Blocus de janvier'));
      expect(u.startDate, equals('2027-01-01'));
      expect(u.endDate, equals('2027-01-05'));
    });

    test('supprimer un blocus ne touche pas aux séances', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('C', ue.id);
      store.addManualTime(courseId: c.id, seconds: 600, date: '2027-01-10');
      final b = store.addBlocus('Janvier', '2027-01-05', '2027-01-20');
      store.deleteBlocus(b.id);
      expect(store.data.blocus, isEmpty);
      expect(store.data.sessions, hasLength(1));
    });
  });

  group('persistance', () {
    test('recharge exactement ce qui a été écrit', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('Cours', ue.id);
      store.addManualTime(courseId: c.id, seconds: 90, date: '2026-10-10', note: 'ok');
      store.addBlocus('B', '2026-10-01', '2026-10-31');
      store.updateSettings((s) {
        s.workMin = 40;
        s.palette = 'teal';
      });
      final again = DataStore(dev.paths, now: clock.call)..load();
      expect(jsonEncode(again.data.toJson()), equals(jsonEncode(store.data.toJson())));
      expect(again.data.settings.workMin, equals(40));
    });

    test('fichier corrompu : copie .corrupt conservée, repart à vide', () {
      File(store.filePath).writeAsStringSync('{ pas du json');
      final again = DataStore(dev.paths, now: clock.call)..load();
      expect(again.data.courses, isEmpty);
      final kept = dev.dir.listSync().whereType<File>().where((f) => f.path.contains('.corrupt-'));
      expect(kept, hasLength(1));
      expect(kept.single.readAsStringSync(), equals('{ pas du json'));
    });

    test('lit un data.json de l\'ancienne version Electron (v1.1.0)', () {
      final legacy = {
        'version': 1,
        'updatedAt': '2026-05-01T10:00:00.000Z',
        'lastSyncedAt': '2026-05-01T09:00:00.000Z',
        'folders': [
          {'id': 'f1', 'name': 'Année 1', 'parentId': null, 'type': 'year', 'createdAt': '2026-01-01T00:00:00.000Z'}
        ],
        'ues': [
          {'id': 'u1', 'name': 'Chimie', 'folderId': 'f1', 'archived': false, 'archivedAt': null, 'createdAt': '2026-01-02T00:00:00.000Z'}
        ],
        'courses': [
          {'id': 'c1', 'name': 'Orga', 'ueId': 'u1', 'createdAt': '2026-01-03T00:00:00.000Z'}
        ],
        'sessions': [
          {
            'id': 's1', 'courseId': 'c1', 'mode': 'pomodoro', 'kind': 'work',
            'start': '2026-02-01T09:00:00.000Z', 'end': '2026-02-01T09:25:00.000Z',
            'seconds': 1500, 'completed': true, 'date': '2026-02-01', 'note': 'ch. 3'
          },
          {
            'id': 's2', 'courseId': 'c1', 'mode': 'flow', 'kind': 'break',
            'start': '2026-02-01T10:00:00.000Z', 'end': '2026-02-01T10:05:00.000Z',
            'seconds': 300, 'completed': true, 'date': '2026-02-01', 'note': ''
          },
          {
            'id': 's3', 'courseId': 'ghost', 'mode': null, 'kind': 'note',
            'start': '2026-02-02T09:00:00.000Z', 'end': '2026-02-02T09:00:00.000Z',
            'seconds': 0, 'completed': true, 'date': '2026-02-02', 'note': 'orpheline'
          },
        ],
        'blocus': [
          {'id': 'b1', 'name': 'Blocus', 'startDate': '2026-01-05', 'endDate': '2026-01-20', 'createdAt': '2026-01-04T00:00:00.000Z'}
        ],
        'settings': {
          'pomodoro': {'workMin': 30, 'shortBreakMin': 5, 'longBreakMin': 20, 'blocksBeforeLongBreak': 3},
          'flow': {'breakPercent': 25},
          'webdav': {
            'enabled': true, 'url': 'https://cloud.example/dav', 'username': 'me', 'password': 'secret',
            'passwordEncrypted': false, 'remotePath': '/EtudeTimer/data.json', 'autoSyncMinutes': 10
          },
          'theme': 'light'
        }
      };
      File(store.filePath).writeAsStringSync(jsonEncode(legacy));
      final s = DataStore(dev.paths, now: clock.call)..load();
      expect(s.data.folders.single.name, equals('Année 1'));
      expect(s.data.courses.single.name, equals('Orga'));
      expect(s.data.sessions, hasLength(2)); // la note orpheline est écartée
      expect(s.data.sessions.first.note, equals('ch. 3'));
      expect(s.data.blocus.single.endDate, equals('2026-01-20'));
      expect(s.data.settings.workMin, equals(30));
      expect(s.data.settings.blocksBeforeLongBreak, equals(3));
      expect(s.data.settings.flowBreakPercent, equals(25));
      // l'ancien choix de thème (ici « light ») n'est volontairement pas repris : sombre par défaut
      expect(s.data.settings.themeMode, equals('dark'));
      // anciennes entités sans updatedAt : repli sur createdAt
      expect(s.data.courses.single.updatedAt, equals('2026-01-03T00:00:00.000Z'));
      // les réglages WebDAV sont repris UNE fois dans device.json, puis n'apparaissent plus dans data.json
      expect(s.data.legacyWebdav, isNotNull);
      final cfg = DeviceConfig(dev.paths);
      cfg.migrateLegacy(s.data.legacyWebdav, s.data.legacyLastSyncedAt);
      expect(cfg.webdav.url, equals('https://cloud.example/dav'));
      expect(cfg.webdav.password, equals('secret'));
      expect(cfg.webdav.autoSyncMinutes, equals(10));
      expect(cfg.lastSyncedAt, equals('2026-05-01T09:00:00.000Z'));
      final written = jsonDecode(File(s.filePath).readAsStringSync()) as Map<String, Object?>;
      expect(jsonEncode(written).contains('secret'), isFalse);
    });

    test('mot de passe chiffré par Electron : non repris', () {
      final cfg = DeviceConfig(dev.paths);
      cfg.migrateLegacy({'enabled': true, 'url': 'https://x/dav', 'password': 'AAAA', 'passwordEncrypted': true}, null);
      expect(cfg.webdav.url, equals('https://x/dav'));
      expect(cfg.webdav.password, equals(''));
    });

    test('device.json n\'est pas écrasé par une seconde migration', () {
      final cfg = DeviceConfig(dev.paths);
      cfg.webdav = WebdavConfig(enabled: true, url: 'https://a/dav');
      cfg.save();
      final again = DeviceConfig(dev.paths)..load();
      again.migrateLegacy({'url': 'https://autre/dav'}, null);
      expect(again.webdav.url, equals('https://a/dav'));
    });
  });

  group('emplacement des données', () {
    test('dossier personnalisé : copie, pointeur, retour au défaut', () {
      final ue = store.addUE('UE');
      store.addCourse('Cours', ue.id);
      final custom = tempDir('custom');
      store.setDataDir(custom.path);
      expect(store.dataDir, equals(custom.path));
      expect(File('${custom.path}/data.json').existsSync(), isTrue);
      expect(store.data.courses, hasLength(1));
      // l'original n'est pas supprimé
      expect(File('${dev.dir.path}/data.json').existsSync(), isTrue);
      // un redémarrage retrouve le dossier personnalisé
      expect(dev.paths.resolveDataDir(), equals(custom.path));
      expect(dev.paths.isCustom(custom.path), isTrue);
      store.resetDataDir();
      expect(store.dataDir, equals(dev.dir.path));
      expect(File(dev.paths.locationFile).existsSync(), isFalse);
    });

    test('pointeur vers un dossier disparu : retour au défaut', () {
      final gone = tempDir('gone');
      dev.paths.writeLocation(gone.path);
      gone.deleteSync(recursive: true);
      expect(dev.paths.resolveDataDir(), equals(dev.dir.path));
    });
  });

  group('chemins par défaut', () {
    test('Windows : %APPDATA%\\etude-timer', () {
      final p = AppPaths.detect(env: {'APPDATA': r'C:\Users\me\AppData\Roaming'}, executablePath: r'C:\Apps\etude\etude_timer.exe', isWindows: true, isLinux: false);
      expect(p.bootstrapDir, equals(r'C:\Users\me\AppData\Roaming\etude-timer'));
      expect(p.isPortable, isFalse);
    });
    test('Linux : XDG_CONFIG_HOME puis ~/.config', () {
      final a = AppPaths.detect(env: {'XDG_CONFIG_HOME': '/xdg', 'HOME': '/home/me'}, executablePath: '/opt/etude/etude_timer', isWindows: false, isLinux: true);
      expect(a.bootstrapDir, equals('/xdg/etude-timer'));
      final b = AppPaths.detect(env: {'HOME': '/home/me'}, executablePath: '/opt/etude/etude_timer', isWindows: false, isLinux: true);
      expect(b.bootstrapDir, equals('/home/me/.config/etude-timer'));
    });
    test('portable : dossier EtudeTimerData à côté de l\'exécutable', () {
      final root = tempDir('portable');
      Directory('${root.path}/EtudeTimerData').createSync();
      final p = AppPaths.detect(env: {'HOME': '/home/me'}, executablePath: '${root.path}/etude_timer', isWindows: false, isLinux: true);
      expect(p.isPortable, isTrue);
      expect(p.bootstrapDir, equals('${root.path}/EtudeTimerData'));
    });
  });
}
