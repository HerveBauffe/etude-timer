import 'dart:convert';

import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/sync.dart';
import 'package:etude_timer/core/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Serveur WebDAV factice en mémoire, avec ETag.
class MemoryRemote implements RemoteStorage {
  String? text;
  int version = 0;
  int writes = 0;
  int failNextWithConflict = 0;
  void Function()? beforeWrite;

  @override
  Future<RemoteFile?> read() async => text == null ? null : RemoteFile(text!, 'v$version');

  @override
  Future<void> write(String t, {RemoteFile? basedOn}) async {
    beforeWrite?.call();
    if (failNextWithConflict > 0) {
      failNextWithConflict--;
      throw const RemotePreconditionFailed();
    }
    if (basedOn == null && text != null) throw const RemotePreconditionFailed();
    if (basedOn != null && basedOn.etag != 'v$version') throw const RemotePreconditionFailed();
    text = t;
    version++;
    writes++;
  }
}

void main() {
  late FakeClock clock;
  late MemoryRemote remote;
  late Device a;
  late Device b;
  late SyncService syncA;
  late SyncService syncB;

  setUp(() {
    clock = FakeClock();
    remote = MemoryRemote();
    a = Device.create(clock);
    b = Device.create(clock);
    syncA = SyncService(a.store, a.config, () => remote, now: clock.call);
    syncB = SyncService(b.store, b.config, () => remote, now: clock.call);
  });

  void step() => clock.advance(minutes: 1);

  group('synchronisation entre deux machines', () {
    test('première synchro : envoie tout ; la seconde machine récupère tout', () async {
      final ue = a.store.addUE('Physique');
      final c = a.store.addCourse('Méca', ue.id);
      a.store.addManualTime(courseId: c.id, seconds: 600, date: '2026-10-01', note: 'p. 4');
      final r = await syncA.sync();
      expect(r.uploaded, isTrue);
      expect(remote.writes, equals(1));
      step();
      final r2 = await syncB.sync();
      expect(r2.localChanged, isTrue);
      expect(r2.uploaded, isFalse);
      expect(b.store.data.courses.single.name, equals('Méca'));
      expect(b.store.data.sessions.single.note, equals('p. 4'));
    });

    test('rien à faire : aucun envoi inutile', () async {
      a.store.addUE('UE');
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      final writes = remote.writes;
      final r = await syncA.sync();
      final r2 = await syncB.sync();
      expect(remote.writes, equals(writes));
      expect(r.uploaded || r2.uploaded, isFalse);
      expect(r.message, equals('Déjà à jour.'));
    });

    test('une suppression se propage à l\'autre machine', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id);
      await syncA.sync();
      step();
      await syncB.sync();
      expect(b.store.data.courses, hasLength(1));
      step();
      b.store.deleteCourse(c.id);
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.courses, isEmpty);
      expect(a.store.data.ues, hasLength(1));
    });

    test('la suppression d\'une UE emporte ses cours et séances des deux côtés', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id);
      a.store.addManualTime(courseId: c.id, seconds: 60, date: '2026-10-01');
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      // B ajoute encore une séance sur ce cours pendant que A supprime l'UE
      b.store.addManualTime(courseId: c.id, seconds: 120, date: '2026-10-02');
      step();
      a.store.deleteUE(ue.id);
      await syncA.sync();
      step();
      await syncB.sync();
      expect(b.store.data.ues, isEmpty);
      expect(b.store.data.courses, isEmpty);
      expect(b.store.data.sessions, isEmpty);
    });

    test('modifications concurrentes sur des éléments différents : tout est conservé', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id);
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      a.store.renameCourse(c.id, 'Cours renommé');
      step();
      b.store.addManualTime(courseId: c.id, seconds: 900, date: '2026-10-03');
      step();
      await syncB.sync();
      step();
      await syncA.sync();
      step();
      await syncB.sync();
      for (final d in [a, b]) {
        expect(d.store.data.courses.single.name, equals('Cours renommé'));
        expect(d.store.data.sessions, hasLength(1));
      }
      expect(canonicalJson(a.store.data), equals(canonicalJson(b.store.data)));
    });

    test('même élément modifié des deux côtés : la modification la plus récente gagne', () async {
      final ue = a.store.addUE('UE');
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      a.store.renameUE(ue.id, 'Version A');
      step();
      b.store.renameUE(ue.id, 'Version B');
      step();
      await syncA.sync();
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.ues.single.name, equals('Version B'));
      expect(b.store.data.ues.single.name, equals('Version B'));
    });

    test('un élément modifié APRÈS sa suppression sur l\'autre machine est conservé', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id);
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      a.store.deleteCourse(c.id);
      step();
      b.store.renameCourse(c.id, 'Toujours là');
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.courses.single.name, equals('Toujours là'));
      expect(b.store.data.courses.single.name, equals('Toujours là'));
      expect(a.store.data.tombstones.containsKey(c.id), isFalse);
    });

    test('réglages : le plus récent gagne, et se propage', () async {
      a.store.updateSettings((s) => s.workMin = 50);
      await syncA.sync();
      step();
      await syncB.sync();
      expect(b.store.data.settings.workMin, equals(50));
      step();
      b.store.updateSettings((s) => s.workMin = 35);
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.settings.workMin, equals(35));
    });

    test('les identifiants WebDAV et la date de synchro ne quittent jamais la machine', () async {
      a.config.webdav.password = 'tres-secret';
      a.config.webdav.url = 'https://cloud/dav';
      a.config.save();
      a.store.addUE('UE');
      await syncA.sync();
      expect(remote.text!.contains('tres-secret'), isFalse);
      expect(remote.text!.contains('cloud/dav'), isFalse);
      expect(remote.text!.contains('lastSyncedAt'), isFalse);
      expect(a.config.lastSyncedAt, isNotNull);
      expect(b.config.lastSyncedAt, isNull);
    });

    test('fichier distant illisible : erreur, jamais écrasé', () async {
      remote.text = '<html>erreur proxy</html>';
      remote.version = 3;
      a.store.addUE('UE');
      await expectLater(syncA.sync(), throwsA(isA<SyncException>()));
      expect(remote.text, equals('<html>erreur proxy</html>'));
      expect(remote.writes, equals(0));
    });

    test('conflit d\'écriture (ETag) : relit, refusionne et réessaie', () async {
      a.store.addUE('UE A');
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      a.store.addUE('Encore A');
      step();
      b.store.addUE('UE B');
      step();
      // Pendant que B s'apprête à écrire, A écrit avant lui
      var first = true;
      remote.beforeWrite = () {
        if (first) {
          first = false;
          // écriture concurrente simulée par A (contourne la vérification)
          final other = jsonDecode(remote.text!) as Map<String, Object?>;
          final merged = AppData.fromJson(other)..ues.add(UE(id: 'zz-concurrent', name: 'Concurrent', updatedAt: '2030-01-01T00:00:00.000Z'));
          remote.text = canonicalJson(merged);
          remote.version++;
        }
      };
      await syncB.sync();
      remote.beforeWrite = null;
      final names = b.store.data.ues.map((u) => u.name).toSet();
      expect(names, equals({'UE A', 'UE B', 'Concurrent'}));
      expect(remote.text!.contains('UE B'), isTrue);
    });

    test('lit un fichier distant au format 1.x (sans updatedAt par entité)', () async {
      remote.text = jsonEncode({
        'version': 1,
        'updatedAt': '2026-05-01T10:00:00.000Z',
        'lastSyncedAt': '2026-05-01T09:00:00.000Z',
        'folders': [],
        'ues': [
          {'id': 'u1', 'name': 'Chimie', 'folderId': null, 'archived': false, 'archivedAt': null, 'createdAt': '2026-01-02T00:00:00.000Z'}
        ],
        'courses': [
          {'id': 'c1', 'name': 'Orga', 'ueId': 'u1', 'createdAt': '2026-01-03T00:00:00.000Z'}
        ],
        'sessions': [],
        'blocus': [],
        'settings': {'pomodoro': {'workMin': 30}, 'webdav': {'url': 'https://x', 'password': 'pw'}, 'theme': 'dark'}
      });
      remote.version = 1;
      await syncA.sync();
      expect(a.store.data.courses.single.name, equals('Orga'));
    });
  });

  group('mergeData', () {
    test('est symétrique : merge(a,b) == merge(b,a)', () {
      final x = AppData(
        updatedAt: '2026-10-01T00:00:00.000Z',
        ues: [UE(id: 'u1', name: 'X', updatedAt: '2026-10-01T00:00:00.000Z'), UE(id: 'u2', name: 'deux', updatedAt: '2026-10-02T00:00:00.000Z')],
        tombstones: {'u9': '2026-10-03T00:00:00.000Z'},
      );
      final y = AppData(
        updatedAt: '2026-10-05T00:00:00.000Z',
        ues: [UE(id: 'u1', name: 'Y', updatedAt: '2026-10-04T00:00:00.000Z'), UE(id: 'u9', name: 'mort', updatedAt: '2026-10-01T00:00:00.000Z')],
      );
      final now = DateTime(2026, 10, 10);
      expect(canonicalJson(mergeData(x, y, now: now)), equals(canonicalJson(mergeData(y, x, now: now))));
      final m = mergeData(x, y, now: now);
      expect(m.ues.map((u) => u.name).toSet(), equals({'Y', 'deux'}));
    });

    test('égalité d\'horodatage : résultat identique quel que soit l\'ordre', () {
      const t = '2026-10-01T00:00:00.000Z';
      final x = AppData(ues: [UE(id: 'u1', name: 'A', updatedAt: t)]);
      final y = AppData(ues: [UE(id: 'u1', name: 'B', updatedAt: t)]);
      final now = DateTime(2026, 10, 10);
      expect(mergeData(x, y, now: now).ues.single.name, equals(mergeData(y, x, now: now).ues.single.name));
    });

    test('ne modifie pas ses arguments', () {
      final x = AppData(ues: [UE(id: 'u1', name: 'A', updatedAt: '2026-10-01T00:00:00.000Z')]);
      final before = canonicalJson(x);
      mergeData(x, AppData(), now: DateTime(2026, 10, 10));
      expect(canonicalJson(x), equals(before));
    });

    test('les pierres tombales de plus d\'un an sont purgées', () {
      final x = AppData(tombstones: {'vieux': '2024-01-01T00:00:00.000Z', 'recent': '2026-10-01T00:00:00.000Z'});
      final m = mergeData(x, AppData(), now: DateTime(2026, 10, 23));
      expect(m.tombstones.keys.toList(), equals(['recent']));
    });

    test('nettoie les orphelins (séance sans cours, cours sans UE)', () {
      final x = AppData(
        ues: [UE(id: 'u1', name: 'U')],
        courses: [Course(id: 'c1', name: 'C', ueId: 'u1'), Course(id: 'c2', name: 'Orphelin', ueId: 'u404')],
        sessions: [Session(id: 's1', courseId: 'c2', start: '2026-01-01T00:00:00.000Z', end: '2026-01-01T00:10:00.000Z', seconds: 600, date: '2026-01-01')],
      );
      final m = mergeData(x, AppData(), now: DateTime(2026, 10, 23));
      expect(m.courses.map((c) => c.id).toList(), equals(['c1']));
      expect(m.sessions, isEmpty);
    });
  });
}
