import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'paths.dart';
import 'util.dart';

/// Stockage JSON local + opérations de modification.
///
/// Chaque modification : met à jour `updatedAt` de l'entité, inscrit une « pierre tombale »
/// pour les suppressions (pour que la synchronisation propage aussi les suppressions),
/// écrit le fichier de manière atomique et prévient les écouteurs.
class DataStore {
  final AppPaths paths;
  final DateTime Function() now;

  late String dataDir;
  late AppData data;
  final List<void Function()> _listeners = [];

  /// Indique qu'il y a des changements locaux pas encore synchronisés.
  bool dirty = false;

  DataStore(this.paths, {DateTime Function()? now}) : now = now ?? DateTime.now {
    dataDir = paths.resolveDataDir();
    data = AppData.empty();
  }

  String get filePath => paths.dataFileIn(dataDir);

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  String _stamp() => isoUtc(now());

  // ───────────── Chargement / écriture ─────────────

  /// Charge `data.json`. Un fichier illisible est copié en `.corrupt-<horodatage>`
  /// (jamais perdu), puis on repart d'un jeu vide.
  void load() {
    final f = File(filePath);
    try {
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync());
        if (j is! Map) throw const FormatException('racine JSON invalide');
        data = AppData.fromJson(j.cast<String, Object?>());
        if (data.normalize()) _writeToDisk();
      } else {
        data = AppData.empty();
        _writeToDisk();
      }
    } catch (_) {
      try {
        if (f.existsSync()) f.copySync('${f.path}.corrupt-${now().millisecondsSinceEpoch}');
      } catch (_) {}
      data = AppData.empty();
      _writeToDisk();
    }
  }

  void _writeToDisk() {
    try {
      final f = File(filePath);
      f.parent.createSync(recursive: true);
      final tmp = File('$filePath.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data.toJson()));
      tmp.renameSync(filePath);
    } catch (_) {
      // Écriture impossible (disque plein, droits) : les données restent en mémoire.
    }
  }

  void _touch() {
    data.updatedAt = _stamp();
    dirty = true;
    _writeToDisk();
    _notify();
  }

  /// Remplace tout le jeu de données (résultat d'une fusion de synchronisation).
  void replaceAll(AppData merged, {bool markDirty = false}) {
    data = merged;
    data.normalize();
    dirty = markDirty;
    _writeToDisk();
    _notify();
  }

  // ───────────── Emplacement des données ─────────────

  /// Change le dossier de données : copie `data.json` (sans supprimer l'ancien) puis mémorise le choix.
  void setDataDir(String newDir) {
    Directory(newDir).createSync(recursive: true);
    final target = File(paths.dataFileIn(newDir));
    if (!target.existsSync() && File(filePath).existsSync()) {
      File(filePath).copySync(target.path);
    }
    paths.writeLocation(newDir);
    dataDir = newDir;
    load();
    _notify();
  }

  void resetDataDir() {
    paths.clearLocation();
    dataDir = paths.bootstrapDir;
    load();
    _notify();
  }

  // ───────────── Suppressions ─────────────

  void _tomb(String id) => data.tombstones[id] = _stamp();

  /// Supprime les pierres tombales de plus d'un an.
  void pruneTombstones({int days = 365}) {
    final limit = now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    data.tombstones.removeWhere((_, v) => (DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0) < limit);
  }

  // ───────────── Dossiers ─────────────

  Folder addFolder(String name, {String? parentId, String type = 'custom'}) {
    final t = _stamp();
    final f = Folder(id: newId(), name: name.trim(), parentId: parentId, type: type, createdAt: t, updatedAt: t);
    data.folders.add(f);
    _touch();
    return f;
  }

  void renameFolder(String id, String name) {
    for (final f in data.folders) {
      if (f.id == id) {
        f.name = name.trim();
        f.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  /// Supprime le dossier et ses sous-dossiers ; les UE contenues remontent à la racine.
  void deleteFolder(String id) {
    final doomed = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in data.folders) {
        if (f.parentId != null && doomed.contains(f.parentId) && doomed.add(f.id)) grew = true;
      }
    }
    final t = _stamp();
    for (final u in data.ues) {
      if (u.folderId != null && doomed.contains(u.folderId)) {
        u.folderId = null;
        u.updatedAt = t;
      }
    }
    data.folders.removeWhere((f) => doomed.contains(f.id));
    for (final d in doomed) {
      data.tombstones[d] = t;
    }
    _touch();
  }

  // ───────────── UE ─────────────

  UE addUE(String name, {String? folderId}) {
    final t = _stamp();
    final u = UE(id: newId(), name: name.trim(), folderId: folderId, createdAt: t, updatedAt: t);
    data.ues.add(u);
    _touch();
    return u;
  }

  void renameUE(String id, String name) {
    for (final u in data.ues) {
      if (u.id == id) {
        u.name = name.trim();
        u.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  void moveUE(String id, String? folderId) {
    for (final u in data.ues) {
      if (u.id == id) {
        u.folderId = folderId;
        u.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  void archiveUE(String id, bool archived) {
    for (final u in data.ues) {
      if (u.id == id) {
        final t = _stamp();
        u.archived = archived;
        u.archivedAt = archived ? t : null;
        u.updatedAt = t;
        _touch();
        return;
      }
    }
  }

  /// Supprime l'UE, ses cours et (via orphelins) leurs séances.
  void deleteUE(String id) {
    final courseIds = data.courses.where((c) => c.ueId == id).map((c) => c.id).toSet();
    data.sessions.removeWhere((s) => courseIds.contains(s.courseId));
    data.plans.removeWhere((p) => courseIds.contains(p.courseId));
    data.courses.removeWhere((c) => c.ueId == id);
    data.ues.removeWhere((u) => u.id == id);
    _tomb(id);
    for (final c in courseIds) {
      _tomb(c);
    }
    _touch();
  }

  // ───────────── Cours ─────────────

  /// `quadri` : 1 ou 2 — le cours (et son examen) ne porte que sur un quadrimestre.
  Course addCourse(String name, String ueId, {int quadri = 1}) {
    final t = _stamp();
    final c = Course(
      id: newId(),
      name: name.trim(),
      ueId: ueId,
      quadri: quadri == 2 ? 2 : 1,
      createdAt: t,
      updatedAt: t,
    );
    data.courses.add(c);
    _touch();
    return c;
  }

  void renameCourse(String id, String name) {
    for (final c in data.courses) {
      if (c.id == id) {
        c.name = name.trim();
        c.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  /// Modifie le nom et/ou le quadrimestre d'un cours.
  void updateCourse(String id, {String? name, int? quadri}) {
    for (final c in data.courses) {
      if (c.id != id) continue;
      if (name != null && name.trim().isNotEmpty) c.name = name.trim();
      if (quadri != null) c.quadri = quadri == 2 ? 2 : 1;
      c.updatedAt = _stamp();
      _touch();
      return;
    }
  }

  /// Change de UE (ex. réorganisation) ; le quadrimestre du cours est conservé.
  void moveCourse(String id, String ueId) {
    if (ueById(ueId) == null) return;
    for (final c in data.courses) {
      if (c.id == id) {
        c.ueId = ueId;
        c.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  void deleteCourse(String id) {
    data.sessions.removeWhere((s) => s.courseId == id);
    data.plans.removeWhere((p) => p.courseId == id);
    data.courses.removeWhere((c) => c.id == id);
    _tomb(id);
    _touch();
  }

  // ───────────── Séances ─────────────

  /// Enregistre un bloc de travail (ou une note libre avec `kind: note`).
  Session addSession({
    required String courseId,
    String? mode,
    SessionKind kind = SessionKind.work,
    required DateTime start,
    required DateTime end,
    int? seconds,
    bool completed = true,
    String note = '',
  }) {
    final secs = kind == SessionKind.note
        ? 0
        : (seconds ?? end.difference(start).inSeconds).clamp(0, 1 << 31);
    final s = Session(
      id: newId(),
      courseId: courseId,
      mode: mode,
      kind: kind,
      start: isoUtc(start),
      end: isoUtc(end),
      seconds: secs,
      completed: completed,
      date: dateKey(start),
      note: note.trim(),
      updatedAt: _stamp(),
    );
    data.sessions.add(s);
    _touch();
    return s;
  }

  /// Temps ajouté à la main (oubli de lancer le minuteur) : durée + date (AAAA-MM-JJ).
  Session addManualTime({
    required String courseId,
    required int seconds,
    required String date,
    String note = '',
  }) {
    final d = parseDateKey(date) ?? now();
    final start = DateTime(d.year, d.month, d.day, 12);
    return addSession(
      courseId: courseId,
      mode: null,
      kind: SessionKind.work,
      start: start,
      end: start.add(Duration(seconds: seconds)),
      seconds: seconds,
      note: note,
    );
  }

  void deleteSession(String id) {
    data.sessions.removeWhere((s) => s.id == id);
    _tomb(id);
    _touch();
  }

  void updateSessionNote(String id, String note) {
    for (final s in data.sessions) {
      if (s.id == id) {
        s.note = note.trim();
        s.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  /// Corrige la durée et/ou la date d'une séance existante.
  void updateSessionTime(String id, {int? seconds, String? date}) {
    for (final s in data.sessions) {
      if (s.id != id) continue;
      if (seconds != null && seconds >= 0) s.seconds = seconds;
      DateTime anchor;
      if (date != null && parseDateKey(date) != null) {
        final d = parseDateKey(date)!;
        s.date = date;
        anchor = DateTime(d.year, d.month, d.day, 12);
      } else {
        anchor = DateTime.tryParse(s.start)?.toLocal() ?? now();
      }
      s.start = isoUtc(anchor);
      s.end = isoUtc(anchor.add(Duration(seconds: s.seconds)));
      s.updatedAt = _stamp();
      _touch();
      return;
    }
  }

  // ───────────── Blocus ─────────────

  Blocus addBlocus(String name, String startDate, String endDate) {
    final t = _stamp();
    final inv = startDate.compareTo(endDate) > 0;
    final b = Blocus(
      id: newId(),
      name: name.trim().isEmpty ? 'Blocus' : name.trim(),
      startDate: inv ? endDate : startDate,
      endDate: inv ? startDate : endDate,
      createdAt: t,
      updatedAt: t,
    );
    data.blocus.add(b);
    _touch();
    return b;
  }

  void updateBlocus(String id, {String? name, String? startDate, String? endDate}) {
    for (final b in data.blocus) {
      if (b.id != id) continue;
      if (name != null && name.trim().isNotEmpty) b.name = name.trim();
      final s = startDate ?? b.startDate;
      final e = endDate ?? b.endDate;
      b.startDate = s.compareTo(e) <= 0 ? s : e;
      b.endDate = s.compareTo(e) <= 0 ? e : s;
      b.updatedAt = _stamp();
      _touch();
      return;
    }
  }

  /// Supprime la période ; les séances enregistrées ne sont jamais touchées.
  void deleteBlocus(String id) {
    data.blocus.removeWhere((b) => b.id == id);
    _tomb(id);
    _touch();
  }

  // ───────────── Planning ─────────────

  /// Ajoute une révision ou un examen. `date` = AAAA-MM-JJ ; `time` = HH:mm (examens).
  PlanItem addPlan({
    required PlanKind kind,
    required String title,
    required String courseId,
    required String date,
    String? time,
    int? estimatedMinutes,
  }) {
    final t = _stamp();
    final p = PlanItem(
      id: newId(),
      kind: kind,
      title: title.trim().isEmpty ? (kind == PlanKind.exam ? 'Examen' : 'Révision') : title.trim(),
      courseId: courseId,
      date: date,
      time: kind == PlanKind.exam ? time : null,
      estimatedMinutes: kind == PlanKind.revision && (estimatedMinutes ?? 0) > 0 ? estimatedMinutes : null,
      createdAt: t,
      updatedAt: t,
    );
    data.plans.add(p);
    _touch();
    return p;
  }

  /// Remplace le contenu d'un élément du planning (les champs inutiles pour son type sont effacés).
  void updatePlan(
    String id, {
    required PlanKind kind,
    required String title,
    required String courseId,
    required String date,
    String? time,
    int? estimatedMinutes,
    bool done = false,
  }) {
    for (final p in data.plans) {
      if (p.id != id) continue;
      p.kind = kind;
      p.title = title.trim().isEmpty ? (kind == PlanKind.exam ? 'Examen' : 'Révision') : title.trim();
      p.courseId = courseId;
      p.date = date;
      p.time = kind == PlanKind.exam ? time : null;
      p.estimatedMinutes = kind == PlanKind.revision && (estimatedMinutes ?? 0) > 0 ? estimatedMinutes : null;
      p.done = kind == PlanKind.revision ? done : false;
      p.updatedAt = _stamp();
      _touch();
      return;
    }
  }

  void setPlanDone(String id, bool done) {
    for (final p in data.plans) {
      if (p.id == id && p.kind == PlanKind.revision) {
        p.done = done;
        p.updatedAt = _stamp();
        _touch();
        return;
      }
    }
  }

  void deletePlan(String id) {
    data.plans.removeWhere((p) => p.id == id);
    _tomb(id);
    _touch();
  }

  // ───────────── Réglages ─────────────

  void updateSettings(void Function(Settings s) change) {
    change(data.settings);
    data.settingsUpdatedAt = _stamp();
    _touch();
  }

  // ───────────── Requêtes utiles ─────────────

  Course? courseById(String? id) {
    if (id == null) return null;
    for (final c in data.courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  UE? ueById(String? id) {
    if (id == null) return null;
    for (final u in data.ues) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Séances d'un cours (travail + notes), de la plus récente à la plus ancienne.
  List<Session> sessionsForCourse(String courseId) {
    final l = data.sessions.where((s) => s.courseId == courseId && s.kind != SessionKind.brk).toList();
    l.sort((a, b) => compareIso(b.end, a.end));
    return l;
  }

  /// Dernière note non vide d'un cours : sert à la bannière « Reprise ».
  Session? lastNoteFor(String courseId) {
    for (final s in sessionsForCourse(courseId)) {
      if (s.note.isNotEmpty) return s;
    }
    return null;
  }
}
