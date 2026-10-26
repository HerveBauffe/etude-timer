import 'dart:convert';
import 'dart:io';

import 'package:etude_timer/core/catalog.dart';
import 'package:etude_timer/core/data_store.dart';
import 'package:etude_timer/core/models.dart';
import 'package:etude_timer/core/planning.dart';
import 'package:etude_timer/core/quadri.dart';
import 'package:etude_timer/core/stats.dart';
import 'package:etude_timer/core/sync.dart';
import 'package:etude_timer/core/webdav_client.dart';
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

  group('quadrimestres', () {
    test('le filtre Q1 / Q2 / Q1+Q2', () {
      expect(QuadriFilter.q1.matches(1), isTrue);
      expect(QuadriFilter.q1.matches(2), isFalse);
      expect(QuadriFilter.q2.matches(2), isTrue);
      expect(QuadriFilter.q2.matches(1), isFalse);
      expect(QuadriFilter.both.matches(1) && QuadriFilter.both.matches(2), isTrue);
      expect(QuadriFilter.both.label, equals('Q1+Q2'));
      expect(QuadriFilter.q2.defaultQuadri, equals(2));
      expect(QuadriFilter.both.defaultQuadri, equals(1));
      expect(QuadriFilter.parse('q2'), equals(QuadriFilter.q2));
      expect(QuadriFilter.parse('both'), equals(QuadriFilter.both));
      expect(QuadriFilter.parse('n importe quoi'), equals(QuadriFilter.q1));
    });

    test('un cours n\'a qu\'un quadrimestre ; une UE peut en couvrir deux', () {
      final ue = store.addUE('Physique');
      final c1 = store.addCourse('Mécanique', ue.id, quadri: 1);
      final c2 = store.addCourse('Optique', ue.id, quadri: 2);
      store.addCourse('Valeur absurde', ue.id, quadri: 7); // ramené à Q1
      expect(c1.quadri, equals(1));
      expect(c2.quadri, equals(2));
      expect(store.data.courses.last.quadri, equals(1));
      expect(ueQuadris(store.data, ue.id), equals([1, 2]));
      expect(quadriBadge(ueQuadris(store.data, ue.id)), equals('Q1+Q2'));
      store.updateCourse(c1.id, quadri: 2);
      store.updateCourse(c1.id, name: 'Mécanique du point');
      expect(store.data.courses.first.quadri, equals(2));
      expect(store.data.courses.first.name, equals('Mécanique du point'));
    });

    test('cours visibles selon le filtre', () {
      final ue = store.addUE('Physique');
      final a = store.addCourse('A', ue.id, quadri: 1);
      final b = store.addCourse('B', ue.id, quadri: 2);
      expect(visibleCourseIds(store.data, QuadriFilter.q1), equals({a.id}));
      expect(visibleCourseIds(store.data, QuadriFilter.q2), equals({b.id}));
      expect(visibleCourseIds(store.data, QuadriFilter.both), equals({a.id, b.id}));
    });

    test('UE et dossiers : visibles si un cours correspond, ou s\'ils sont vides', () {
      final year = store.addFolder('2026-2027');
      final onlyQ1 = store.addUE('Chimie', folderId: year.id);
      store.addCourse('Orga', onlyQ1.id, quadri: 1);
      final both = store.addUE('Physique', folderId: year.id);
      store.addCourse('Méca', both.id, quadri: 1);
      store.addCourse('Optique', both.id, quadri: 2);
      final empty = store.addUE('Nouvelle UE');
      final emptyFolder = store.addFolder('Vide');
      final q2Folder = store.addFolder('Seulement Q2');
      final q2Ue = store.addUE('Bio', folderId: q2Folder.id);
      store.addCourse('Cellule', q2Ue.id, quadri: 2);

      final d = store.data;
      expect(ueVisible(d, onlyQ1, QuadriFilter.q1), isTrue);
      expect(ueVisible(d, onlyQ1, QuadriFilter.q2), isFalse);
      expect(ueVisible(d, both, QuadriFilter.q1), isTrue);
      expect(ueVisible(d, both, QuadriFilter.q2), isTrue);
      expect(ueVisible(d, empty, QuadriFilter.q2), isTrue);
      expect(folderVisible(d, year, QuadriFilter.q2), isTrue); // grâce à Physique
      expect(folderVisible(d, q2Folder, QuadriFilter.q1), isFalse);
      expect(folderVisible(d, q2Folder, QuadriFilter.q2), isTrue);
      expect(folderVisible(d, emptyFolder, QuadriFilter.q1), isTrue);
    });

    test('devine le quadrimestre d\'après le nom des dossiers', () {
      expect(inferQuadriFromNames(['Quadrimestre 2']), equals(2));
      expect(inferQuadriFromNames(['Quadri 1', '2026']), equals(1));
      expect(inferQuadriFromNames(['Q2']), equals(2));
      expect(inferQuadriFromNames(['q 1 - sciences']), equals(1));
      expect(inferQuadriFromNames(['2e quadrimestre']), equals(2));
      expect(inferQuadriFromNames(['1er quadri']), equals(1));
      expect(inferQuadriFromNames(['Semestre 2']), equals(2));
      expect(inferQuadriFromNames(['Quad. 2']), equals(2));
      expect(inferQuadriFromNames(['2026-2027']), isNull);
      expect(inferQuadriFromNames(['Mathématiques']), isNull);
      expect(inferQuadriFromNames(['Q3']), isNull);
      // le dossier le plus proche l'emporte
      expect(inferQuadriFromNames(['Quadrimestre 2', 'Q1']), equals(2));
    });

    test('ancien fichier : le quadrimestre est repris du nom du dossier, sinon Q1', () {
      final legacy = {
        'version': 1,
        'folders': [
          {'id': 'y', 'name': '2026-2027', 'parentId': null, 'createdAt': '2026-01-01T00:00:00.000Z'},
          {'id': 'q1', 'name': 'Quadrimestre 1', 'parentId': 'y', 'createdAt': '2026-01-01T00:00:00.000Z'},
          {'id': 'q2', 'name': 'Quadrimestre 2', 'parentId': 'y', 'createdAt': '2026-01-01T00:00:00.000Z'},
        ],
        'ues': [
          {'id': 'u1', 'name': 'A', 'folderId': 'q1', 'createdAt': '2026-01-02T00:00:00.000Z'},
          {'id': 'u2', 'name': 'B', 'folderId': 'q2', 'createdAt': '2026-01-02T00:00:00.000Z'},
          {'id': 'u3', 'name': 'C', 'folderId': 'y', 'createdAt': '2026-01-02T00:00:00.000Z'},
          {'id': 'u4', 'name': 'D', 'folderId': null, 'createdAt': '2026-01-02T00:00:00.000Z'},
        ],
        'courses': [
          for (final (id, ue) in [('c1', 'u1'), ('c2', 'u2'), ('c3', 'u3'), ('c4', 'u4')])
            {'id': id, 'name': id, 'ueId': ue, 'createdAt': '2026-01-03T00:00:00.000Z'},
        ],
      };
      final d = AppData.fromJson(legacy);
      final q = {for (final c in d.courses) c.id: c.quadri};
      expect(q, equals({'c1': 1, 'c2': 2, 'c3': 1, 'c4': 1}));
      // l'horodatage n'est pas touché : deux machines migrent de la même façon
      expect(d.courses.first.updatedAt, equals('2026-01-03T00:00:00.000Z'));
      expect(canonicalJson(AppData.fromJson(legacy)), equals(canonicalJson(d)));
    });

    test('le vrai fichier Electron de test : aucun plan, tous les cours en Q1 (dossier « Quadrimestre 1 »)', () {
      final raw = jsonDecode(File('test/fixtures/legacy_electron_v1_1_0.json').readAsStringSync()) as Map<String, Object?>;
      final d = AppData.fromJson(raw);
      expect(d.plans, isEmpty);
      expect(d.courses.every((c) => c.quadri == 1), isTrue);
    });

    test('déplacer un cours vers une autre UE garde son quadrimestre', () {
      final a = store.addUE('A');
      final b = store.addUE('B');
      final c = store.addCourse('Cours', a.id, quadri: 2);
      store.moveCourse(c.id, b.id);
      expect(store.data.courses.single.ueId, equals(b.id));
      expect(store.data.courses.single.quadri, equals(2));
      store.moveCourse(c.id, 'inconnue');
      expect(store.data.courses.single.ueId, equals(b.id));
    });
  });

  group('planning : données', () {
    late Course course;
    setUp(() {
      final ue = store.addUE('UE');
      course = store.addCourse('Cours', ue.id, quadri: 1);
    });

    test('une révision : titre, cours, durée estimée facultative ; pas d\'heure', () {
      final r = store.addPlan(kind: PlanKind.revision, title: 'Chapitres 1-3', courseId: course.id, date: '2026-12-10', time: '09:00', estimatedMinutes: 90);
      expect(r.estimatedMinutes, equals(90));
      expect(r.time, isNull);
      final r2 = store.addPlan(kind: PlanKind.revision, title: 'Sans durée', courseId: course.id, date: '2026-12-10');
      expect(r2.estimatedMinutes, isNull);
      final r3 = store.addPlan(kind: PlanKind.revision, title: 'Durée 0', courseId: course.id, date: '2026-12-10', estimatedMinutes: 0);
      expect(r3.estimatedMinutes, isNull);
    });

    test('un examen : titre, cours, heure ; pas de durée estimée', () {
      final e = store.addPlan(kind: PlanKind.exam, title: 'Examen final', courseId: course.id, date: '2027-01-12', time: '14:00', estimatedMinutes: 120);
      expect(e.time, equals('14:00'));
      expect(e.estimatedMinutes, isNull);
      expect(e.isExam, isTrue);
    });

    test('titre vide : un titre par défaut est mis', () {
      final e = store.addPlan(kind: PlanKind.exam, title: '  ', courseId: course.id, date: '2027-01-12', time: '10:00');
      final r = store.addPlan(kind: PlanKind.revision, title: '', courseId: course.id, date: '2027-01-12');
      expect(e.title, equals('Examen'));
      expect(r.title, equals('Révision'));
    });

    test('modifier, changer de type, cocher « fait » (révisions seulement)', () {
      final r = store.addPlan(kind: PlanKind.revision, title: 'A', courseId: course.id, date: '2026-12-10', estimatedMinutes: 60);
      store.setPlanDone(r.id, true);
      expect(store.data.plans.single.done, isTrue);
      store.updatePlan(r.id, kind: PlanKind.exam, title: 'Devenu examen', courseId: course.id, date: '2026-12-11', time: '08:30', done: true);
      final p = store.data.plans.single;
      expect(p.isExam, isTrue);
      expect(p.time, equals('08:30'));
      expect(p.estimatedMinutes, isNull);
      expect(p.done, isFalse); // un examen ne se « coche » pas
      store.setPlanDone(p.id, true);
      expect(store.data.plans.single.done, isFalse);
    });

    test('supprimer un élément ; supprimer un cours ou une UE supprime son planning', () {
      final r = store.addPlan(kind: PlanKind.revision, title: 'A', courseId: course.id, date: '2026-12-10');
      store.deletePlan(r.id);
      expect(store.data.plans, isEmpty);
      expect(store.data.tombstones.containsKey(r.id), isTrue);

      store.addPlan(kind: PlanKind.exam, title: 'E', courseId: course.id, date: '2027-01-12', time: '10:00');
      store.deleteCourse(course.id);
      expect(store.data.plans, isEmpty);

      final ue = store.addUE('Autre');
      final c = store.addCourse('C', ue.id);
      store.addPlan(kind: PlanKind.exam, title: 'E2', courseId: c.id, date: '2027-01-12', time: '10:00');
      store.deleteUE(ue.id);
      expect(store.data.plans, isEmpty);
    });

    test('recharge le planning depuis le disque', () {
      store.addPlan(kind: PlanKind.exam, title: 'E', courseId: course.id, date: '2027-01-12', time: '10:00');
      store.addPlan(kind: PlanKind.revision, title: 'R', courseId: course.id, date: '2027-01-05', estimatedMinutes: 45);
      final again = DataStore(dev.paths, now: clock.call)..load();
      expect(again.data.plans, hasLength(2));
      expect(canonicalJson(again.data), equals(canonicalJson(store.data)));
    });

    test('un élément dont le cours n\'existe plus est écarté à la lecture', () {
      final data = AppData.fromJson(jsonDecode(jsonEncode(store.data.toJson())) as Map<String, Object?>);
      data.plans.add(PlanItem(id: 'x', kind: PlanKind.exam, title: 'Orphelin', courseId: 'fantome', date: '2027-01-01'));
      expect(data.normalize(), isTrue);
      expect(data.plans, isEmpty);
    });
  });

  group('planning : calendrier', () {
    test('éléments d\'un jour : examens (par heure) puis révisions (par titre)', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('C', ue.id);
      store.addPlan(kind: PlanKind.revision, title: 'b révision', courseId: c.id, date: '2027-01-05');
      store.addPlan(kind: PlanKind.revision, title: 'A révision', courseId: c.id, date: '2027-01-05');
      store.addPlan(kind: PlanKind.exam, title: 'Tard', courseId: c.id, date: '2027-01-05', time: '16:00');
      store.addPlan(kind: PlanKind.exam, title: 'Tôt', courseId: c.id, date: '2027-01-05', time: '08:30');
      store.addPlan(kind: PlanKind.revision, title: 'Autre jour', courseId: c.id, date: '2027-01-06');
      final day = plansOn(store.data, '2027-01-05');
      expect(day.map((p) => p.title).toList(), equals(['Tôt', 'Tard', 'A révision', 'b révision']));
      expect(plansOn(store.data, '2027-01-06'), hasLength(1));
      expect(plansOn(store.data, '2027-01-05', courseIds: {}), isEmpty);
    });

    test('le filtre de quadrimestre masque les éléments des cours de l\'autre quadrimestre', () {
      final ue = store.addUE('UE');
      final a = store.addCourse('A', ue.id, quadri: 1);
      final b = store.addCourse('B', ue.id, quadri: 2);
      store.addPlan(kind: PlanKind.exam, title: 'Exam A', courseId: a.id, date: '2027-01-05', time: '09:00');
      store.addPlan(kind: PlanKind.exam, title: 'Exam B', courseId: b.id, date: '2027-01-05', time: '09:00');
      final q1 = visibleCourseIds(store.data, QuadriFilter.q1);
      expect(plansOn(store.data, '2027-01-05', courseIds: q1).single.title, equals('Exam A'));
      final q2 = visibleCourseIds(store.data, QuadriFilter.q2);
      expect(plansOn(store.data, '2027-01-05', courseIds: q2).single.title, equals('Exam B'));
      expect(plansOn(store.data, '2027-01-05', courseIds: visibleCourseIds(store.data, QuadriFilter.both)), hasLength(2));
    });

    test('grille d\'un mois : semaines complètes du lundi au dimanche', () {
      final oct = monthGrid(2026, 10); // 1er oct 2026 = jeudi ; 31 oct = samedi
      expect(oct, hasLength(5));
      expect(oct.first.first, equals(DateTime(2026, 9, 28)));
      expect(oct.last.last, equals(DateTime(2026, 11, 1)));
      expect(oct.every((w) => w.length == 7 && w.first.weekday == DateTime.monday), isTrue);
      final feb = monthGrid(2027, 2); // 1er fév 2027 = lundi ; 28 = dimanche → 4 semaines exactement
      expect(feb, hasLength(4));
      expect(feb.first.first, equals(DateTime(2027, 2, 1)));
      final aug = monthGrid(2026, 8); // 1er août 2026 = samedi ; 31 = lundi → 6 semaines
      expect(aug, hasLength(6));
    });

    test('semaine : du lundi au dimanche', () {
      final w = weekDays(DateTime(2026, 10, 23));
      expect(w.first, equals(DateTime(2026, 10, 19)));
      expect(w.last, equals(DateTime(2026, 10, 25)));
      expect(weekDays(DateTime(2026, 10, 25)).first, equals(DateTime(2026, 10, 19)));
      expect(weekDays(DateTime(2026, 10, 26)).first, equals(DateTime(2026, 10, 26)));
    });

    test('prochain examen et compte à rebours', () {
      final ue = store.addUE('UE');
      final c = store.addCourse('C', ue.id);
      final other = store.addCourse('Q2', ue.id, quadri: 2);
      store.addPlan(kind: PlanKind.exam, title: 'Passé', courseId: c.id, date: '2026-10-01', time: '09:00');
      store.addPlan(kind: PlanKind.exam, title: 'Plus tard', courseId: c.id, date: '2027-01-20', time: '09:00');
      store.addPlan(kind: PlanKind.exam, title: 'Bientôt PM', courseId: c.id, date: '2026-12-15', time: '14:00');
      store.addPlan(kind: PlanKind.exam, title: 'Bientôt AM', courseId: c.id, date: '2026-12-15', time: '09:00');
      store.addPlan(kind: PlanKind.exam, title: 'Q2 plus proche', courseId: other.id, date: '2026-11-01', time: '09:00');
      store.addPlan(kind: PlanKind.revision, title: 'Révision ignorée', courseId: c.id, date: '2026-10-25');
      final now = DateTime(2026, 10, 25, 22);
      expect(nextExam(store.data, now)!.title, equals('Q2 plus proche'));
      expect(nextExam(store.data, now, courseIds: visibleCourseIds(store.data, QuadriFilter.q1))!.title, equals('Bientôt AM'));
      expect(nextExam(store.data, DateTime(2030, 1, 1)), isNull);
      expect(daysUntil('2026-10-26', now), equals(1));
      expect(daysUntil('2026-10-25', now), equals(0));
      expect(daysUntil('2026-10-20', now), equals(-5));
      expect(daysUntilLabel(0), equals("aujourd'hui"));
      expect(daysUntilLabel(1), equals('demain'));
      expect(daysUntilLabel(12), equals('dans 12 j'));
      expect(daysUntilLabel(-3), equals('il y a 3 j'));
    });
  });

  group('planning : synchronisation', () {
    late MemoryRemoteLike remote;
    late Device a;
    late Device b;
    late SyncService syncA;
    late SyncService syncB;
    setUp(() {
      remote = MemoryRemoteLike();
      a = Device.create(clock);
      b = Device.create(clock);
      syncA = SyncService(a.store, a.config, () => remote, now: clock.call);
      syncB = SyncService(b.store, b.config, () => remote, now: clock.call);
    });
    void step() => clock.advance(minutes: 1);

    test('création, modification et suppression se propagent entre machines', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id, quadri: 2);
      final p = a.store.addPlan(kind: PlanKind.exam, title: 'Examen', courseId: c.id, date: '2027-06-10', time: '09:00');
      await syncA.sync();
      step();
      await syncB.sync();
      expect(b.store.data.plans.single.title, equals('Examen'));
      expect(b.store.data.courses.single.quadri, equals(2));
      step();
      b.store.updatePlan(p.id, kind: PlanKind.exam, title: 'Examen (salle B)', courseId: c.id, date: '2027-06-11', time: '10:30');
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.plans.single.title, equals('Examen (salle B)'));
      expect(a.store.data.plans.single.date, equals('2027-06-11'));
      step();
      a.store.deletePlan(p.id);
      await syncA.sync();
      step();
      await syncB.sync();
      expect(b.store.data.plans, isEmpty);
    });

    test('changer le quadrimestre d\'un cours se propage', () async {
      final ue = a.store.addUE('UE');
      final c = a.store.addCourse('Cours', ue.id, quadri: 1);
      await syncA.sync();
      step();
      await syncB.sync();
      step();
      b.store.updateCourse(c.id, quadri: 2);
      await syncB.sync();
      step();
      await syncA.sync();
      expect(a.store.data.courses.single.quadri, equals(2));
    });

    test('le filtre Q1/Q2 reste local à la machine (device.json), pas dans les données synchronisées', () async {
      a.config.quadriFilter = 'q2';
      a.config.save();
      a.store.addUE('UE');
      await syncA.sync();
      expect(remote.text!.contains('quadriFilter'), isFalse);
      expect(DeviceConfigReload.read(a), equals('q2'));
    });
  });

  group('statistiques par cours', () {
    test('temps par cours, du plus long au plus court, filtré par quadrimestre et par période', () {
      final ue = store.addUE('Physique');
      final a = store.addCourse('Mécanique', ue.id, quadri: 1);
      final b = store.addCourse('Optique', ue.id, quadri: 2);
      final c = store.addCourse('Thermo', ue.id, quadri: 1);
      store.addManualTime(courseId: a.id, seconds: 3600, date: '2026-10-20');
      store.addManualTime(courseId: a.id, seconds: 1800, date: '2026-09-01');
      store.addManualTime(courseId: b.id, seconds: 7200, date: '2026-10-21');
      store.addManualTime(courseId: c.id, seconds: 600, date: '2026-10-22');
      store.addSession(courseId: a.id, kind: SessionKind.note, start: clock.t, end: clock.t, note: 'ignorée');

      final q1 = visibleCourseIds(store.data, QuadriFilter.q1);
      final all = courseTotals(store.data, q1);
      expect(all.map((t) => (t.course.name, t.seconds)).toList(), equals([('Mécanique', 5400), ('Thermo', 600)]));

      final both = courseTotals(store.data, visibleCourseIds(store.data, QuadriFilter.both));
      expect(both.first.course.name, equals('Optique'));
      expect(both.fold<int>(0, (s, t) => s + t.seconds), equals(5400 + 7200 + 600));

      final october = courseTotals(store.data, q1, fromKey: '2026-10-01', toKey: '2026-10-31');
      expect(october.first.seconds, equals(3600));

      final none = courseTotals(store.data, q1, fromKey: '2030-01-01');
      expect(none.every((t) => t.seconds == 0), isTrue);
      expect(none, hasLength(2)); // les cours sans temps restent listés

      expect(workSessions(store.data, courseIds: q1), hasLength(3));
    });
  });
}

/// Serveur distant minimal en mémoire (copie allégée de celui de sync_test).
class MemoryRemoteLike implements RemoteStorage {
  String? text;
  int version = 0;
  @override
  Future<RemoteFile?> read() async => text == null ? null : RemoteFile(text!, 'v$version');
  @override
  Future<void> write(String t, {RemoteFile? basedOn}) async {
    if (basedOn == null && text != null) throw const RemotePreconditionFailed();
    if (basedOn != null && basedOn.etag != 'v$version') throw const RemotePreconditionFailed();
    text = t;
    version++;
  }
}

class DeviceConfigReload {
  static String read(Device d) {
    final j = jsonDecode(File(d.paths.deviceFile).readAsStringSync()) as Map<String, Object?>;
    return j['quadriFilter'] as String;
  }
}
