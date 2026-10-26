import 'quadri.dart';
import 'util.dart';

/// Modèles de données. Le format JSON reste compatible avec `data.json` de la version
/// Electron (1.x) : les champs ajoutés (`updatedAt` par entité, `tombstones`,
/// `settingsUpdatedAt`) sont optionnels à la lecture.

abstract class Entity {
  String get id;
  String updatedAt;
  Entity(this.updatedAt);
  Map<String, Object?> toJson();
}

String _str(Object? v, [String d = '']) => v is String ? v : d;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v, int d) => v is num ? v.round() : d;
bool _bool(Object? v, bool d) => v is bool ? v : d;

/// Date de dernière modification d'une ancienne entité qui n'en avait pas.
String _legacyStamp(Map<String, Object?> j, [String? alt]) =>
    _strN(j['updatedAt']) ?? _strN(j['createdAt']) ?? alt ?? epochIso;

class Folder extends Entity {
  @override
  final String id;
  String name;
  String? parentId;
  String type;
  String createdAt;

  Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.type = 'custom',
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? isoUtc(DateTime.now()),
        super(updatedAt ?? createdAt ?? isoUtc(DateTime.now()));

  factory Folder.fromJson(Map<String, Object?> j) => Folder(
        id: _str(j['id']),
        name: _str(j['name'], 'Sans nom'),
        parentId: _strN(j['parentId']),
        type: _str(j['type'], 'custom'),
        createdAt: _str(j['createdAt'], epochIso),
        updatedAt: _legacyStamp(j),
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'type': type,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class UE extends Entity {
  @override
  final String id;
  String name;
  String? folderId;
  bool archived;
  String? archivedAt;
  String createdAt;

  UE({
    required this.id,
    required this.name,
    this.folderId,
    this.archived = false,
    this.archivedAt,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? isoUtc(DateTime.now()),
        super(updatedAt ?? createdAt ?? isoUtc(DateTime.now()));

  factory UE.fromJson(Map<String, Object?> j) => UE(
        id: _str(j['id']),
        name: _str(j['name'], 'Sans nom'),
        folderId: _strN(j['folderId']),
        archived: _bool(j['archived'], false),
        archivedAt: _strN(j['archivedAt']),
        createdAt: _str(j['createdAt'], epochIso),
        updatedAt: _legacyStamp(j),
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'folderId': folderId,
        'archived': archived,
        'archivedAt': archivedAt,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class Course extends Entity {
  @override
  final String id;
  String name;
  String ueId;

  /// Quadrimestre du cours : 1 ou 2 (0 = inconnu, résolu à la lecture d'un ancien fichier).
  int quadri;
  String createdAt;

  Course({
    required this.id,
    required this.name,
    required this.ueId,
    this.quadri = 1,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? isoUtc(DateTime.now()),
        super(updatedAt ?? createdAt ?? isoUtc(DateTime.now()));

  factory Course.fromJson(Map<String, Object?> j) => Course(
        id: _str(j['id']),
        name: _str(j['name'], 'Sans nom'),
        ueId: _str(j['ueId']),
        quadri: _int(j['quadri'], 0).clamp(0, 2),
        createdAt: _str(j['createdAt'], epochIso),
        updatedAt: _legacyStamp(j),
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'ueId': ueId,
        'quadri': quadri,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

enum SessionKind { work, brk, note }

SessionKind _kindFrom(String s) => switch (s) {
      'break' => SessionKind.brk,
      'note' => SessionKind.note,
      _ => SessionKind.work,
    };

String _kindTo(SessionKind k) => switch (k) {
      SessionKind.work => 'work',
      SessionKind.brk => 'break',
      SessionKind.note => 'note',
    };

/// Une séance : bloc de travail, ou note libre (`kind: note`, 0 s).
/// Les pauses ne sont jamais enregistrées, mais l'ancien format pouvait en contenir :
/// elles sont conservées à la lecture et ignorées par les statistiques.
class Session extends Entity {
  @override
  final String id;
  String courseId;
  String? mode; // 'pomodoro' | 'flow' | null
  SessionKind kind;
  String start;
  String end;
  int seconds;
  bool completed;
  String date; // AAAA-MM-JJ (date locale)
  String note;

  Session({
    required this.id,
    required this.courseId,
    this.mode,
    this.kind = SessionKind.work,
    required this.start,
    required this.end,
    required this.seconds,
    this.completed = true,
    required this.date,
    this.note = '',
    String? updatedAt,
  }) : super(updatedAt ?? end);

  factory Session.fromJson(Map<String, Object?> j) {
    final start = _str(j['start'], epochIso);
    final end = _str(j['end'], start);
    var date = _str(j['date']);
    if (date.isEmpty) date = start.length >= 10 ? start.substring(0, 10) : '1970-01-01';
    return Session(
      id: _str(j['id']),
      courseId: _str(j['courseId']),
      mode: _strN(j['mode']),
      kind: _kindFrom(_str(j['kind'], 'work')),
      start: start,
      end: end,
      seconds: _int(j['seconds'], 0).clamp(0, 1 << 31),
      completed: _bool(j['completed'], true),
      date: date,
      note: _str(j['note']),
      updatedAt: _strN(j['updatedAt']) ?? _strN(j['end']) ?? start,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'courseId': courseId,
        'mode': mode,
        'kind': _kindTo(kind),
        'start': start,
        'end': end,
        'seconds': seconds,
        'completed': completed,
        'date': date,
        'note': note,
        'updatedAt': updatedAt,
      };
}

class Blocus extends Entity {
  @override
  final String id;
  String name;
  String startDate; // AAAA-MM-JJ
  String endDate;
  String createdAt;

  Blocus({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? isoUtc(DateTime.now()),
        super(updatedAt ?? createdAt ?? isoUtc(DateTime.now()));

  factory Blocus.fromJson(Map<String, Object?> j) => Blocus(
        id: _str(j['id']),
        name: _str(j['name'], 'Blocus'),
        startDate: _str(j['startDate']),
        endDate: _str(j['endDate']),
        createdAt: _str(j['createdAt'], epochIso),
        updatedAt: _legacyStamp(j),
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate,
        'endDate': endDate,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

enum PlanKind { revision, exam }

/// Élément du planning : une révision (titre, cours, durée estimée facultative)
/// ou un examen (titre, cours, heure). Toujours lié à un cours ; le quadrimestre est celui du cours.
class PlanItem extends Entity {
  @override
  final String id;
  PlanKind kind;
  String title;
  String courseId;
  String date; // AAAA-MM-JJ
  String? time; // HH:mm — examens
  int? estimatedMinutes; // révisions, facultatif
  bool done;
  String createdAt;

  PlanItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.courseId,
    required this.date,
    this.time,
    this.estimatedMinutes,
    this.done = false,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? isoUtc(DateTime.now()),
        super(updatedAt ?? createdAt ?? isoUtc(DateTime.now()));

  bool get isExam => kind == PlanKind.exam;

  factory PlanItem.fromJson(Map<String, Object?> j) {
    final est = j['estimatedMinutes'];
    return PlanItem(
      id: _str(j['id']),
      kind: _str(j['kind']) == 'exam' ? PlanKind.exam : PlanKind.revision,
      title: _str(j['title'], 'Sans titre'),
      courseId: _str(j['courseId']),
      date: _str(j['date']),
      time: _strN(j['time']),
      estimatedMinutes: est is num && est > 0 ? est.round() : null,
      done: _bool(j['done'], false),
      createdAt: _str(j['createdAt'], epochIso),
      updatedAt: _legacyStamp(j),
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': isExam ? 'exam' : 'revision',
        'title': title,
        'courseId': courseId,
        'date': date,
        'time': time,
        'estimatedMinutes': estimatedMinutes,
        'done': done,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

/// Réglages synchronisés (les identifiants WebDAV, eux, restent locaux : voir device_config).
class Settings {
  int workMin;
  int shortBreakMin;
  int longBreakMin;
  int blocksBeforeLongBreak;
  int flowBreakPercent;

  /// 'dark' (défaut) | 'light' | 'system'
  String themeMode;

  /// 'mono' (noir et blanc, défaut) | 'teal' | 'indigo' | 'rose' | 'amber'
  String palette;

  Settings({
    this.workMin = 25,
    this.shortBreakMin = 5,
    this.longBreakMin = 15,
    this.blocksBeforeLongBreak = 4,
    this.flowBreakPercent = 20,
    this.themeMode = 'dark',
    this.palette = 'mono',
  });

  /// `legacy` : réglages d'un fichier 1.x (Electron). L'ancien thème par défaut était « système » ;
  /// la nouvelle appli est sombre par défaut, donc on ne reprend pas l'ancien choix de thème.
  factory Settings.fromJson(Map<String, Object?> j, {bool legacy = false}) {
    final p = (j['pomodoro'] as Map?)?.cast<String, Object?>() ?? const {};
    final f = (j['flow'] as Map?)?.cast<String, Object?>() ?? const {};
    final mode = _str(j['theme'], 'dark');
    return Settings(
      workMin: _int(p['workMin'], 25).clamp(1, 240),
      shortBreakMin: _int(p['shortBreakMin'], 5).clamp(1, 120),
      longBreakMin: _int(p['longBreakMin'], 15).clamp(1, 240),
      blocksBeforeLongBreak: _int(p['blocksBeforeLongBreak'], 4).clamp(1, 20),
      flowBreakPercent: _int(f['breakPercent'], 20).clamp(1, 100),
      themeMode: !legacy && const ['dark', 'light', 'system'].contains(mode) ? mode : 'dark',
      palette: _str(j['palette'], 'mono'),
    );
  }

  Map<String, Object?> toJson() => {
        'pomodoro': {
          'workMin': workMin,
          'shortBreakMin': shortBreakMin,
          'longBreakMin': longBreakMin,
          'blocksBeforeLongBreak': blocksBeforeLongBreak,
        },
        'flow': {'breakPercent': flowBreakPercent},
        'theme': themeMode,
        'palette': palette,
      };

  Settings copy() => Settings.fromJson(toJson());
}

/// Le document complet, tel qu'écrit dans `data.json` et échangé par WebDAV.
class AppData {
  static const int currentVersion = 3;

  int version;
  String updatedAt;
  final List<Folder> folders;
  final List<UE> ues;
  final List<Course> courses;
  final List<Session> sessions;
  final List<Blocus> blocus;
  final List<PlanItem> plans;

  /// id → date de suppression : permet de propager les suppressions entre machines.
  final Map<String, String> tombstones;
  Settings settings;
  String settingsUpdatedAt;

  /// Réglages WebDAV hérités d'un `data.json` 1.x, lus une fois pour migration vers device.json.
  Map<String, Object?>? legacyWebdav;
  String? legacyLastSyncedAt;

  AppData({
    this.version = currentVersion,
    String? updatedAt,
    List<Folder>? folders,
    List<UE>? ues,
    List<Course>? courses,
    List<Session>? sessions,
    List<Blocus>? blocus,
    List<PlanItem>? plans,
    Map<String, String>? tombstones,
    Settings? settings,
    String? settingsUpdatedAt,
  })  : updatedAt = updatedAt ?? isoUtc(DateTime.now()),
        folders = folders ?? [],
        ues = ues ?? [],
        courses = courses ?? [],
        sessions = sessions ?? [],
        blocus = blocus ?? [],
        plans = plans ?? [],
        tombstones = tombstones ?? {},
        settings = settings ?? Settings(),
        settingsUpdatedAt = settingsUpdatedAt ?? epochIso;

  factory AppData.empty() => AppData();

  static List<T> _list<T>(Object? v, T Function(Map<String, Object?>) f) {
    if (v is! List) return [];
    final out = <T>[];
    for (final e in v) {
      if (e is Map) {
        final item = f(e.cast<String, Object?>());
        out.add(item);
      }
    }
    return out;
  }

  factory AppData.fromJson(Map<String, Object?> j) {
    final rawSettings = (j['settings'] as Map?)?.cast<String, Object?>() ?? const {};
    final tomb = <String, String>{};
    final t = j['tombstones'];
    if (t is Map) {
      t.forEach((k, v) {
        if (k is String && v is String) tomb[k] = v;
      });
    }
    final fileVersion = _int(j['version'], 1);
    final data = AppData(
      version: fileVersion,
      updatedAt: _strN(j['updatedAt']) ?? epochIso,
      folders: _list(j['folders'], Folder.fromJson).where((e) => e.id.isNotEmpty).toList(),
      ues: _list(j['ues'], UE.fromJson).where((e) => e.id.isNotEmpty).toList(),
      courses: _list(j['courses'], Course.fromJson).where((e) => e.id.isNotEmpty).toList(),
      sessions: _list(j['sessions'], Session.fromJson).where((e) => e.id.isNotEmpty).toList(),
      blocus: _list(j['blocus'], Blocus.fromJson).where((e) => e.id.isNotEmpty).toList(),
      plans: _list(j['plans'], PlanItem.fromJson).where((e) => e.id.isNotEmpty).toList(),
      tombstones: tomb,
      settings: Settings.fromJson(rawSettings, legacy: fileVersion < 2),
      settingsUpdatedAt: _strN(j['settingsUpdatedAt']) ?? _strN(j['updatedAt']) ?? epochIso,
    );
    final wd = rawSettings['webdav'];
    if (wd is Map) data.legacyWebdav = wd.cast<String, Object?>();
    data.legacyLastSyncedAt = _strN(j['lastSyncedAt']);
    data.resolveQuadris();
    return data;
  }

  /// Cours sans quadrimestre (anciennes données) : on le devine d'après les noms des dossiers
  /// parents (« Quadrimestre 2 »…), sinon Q1. Déterministe et sans toucher `updatedAt`,
  /// pour que deux machines qui migrent le même fichier obtiennent exactement le même résultat.
  void resolveQuadris() {
    if (!courses.any((c) => c.quadri == 0)) return;
    final ueById = {for (final u in ues) u.id: u};
    final folderById = {for (final f in folders) f.id: f};
    for (final c in courses) {
      if (c.quadri != 0) continue;
      final names = <String>[];
      var fid = ueById[c.ueId]?.folderId;
      var guard = 0;
      while (fid != null && guard++ < 50) {
        final f = folderById[fid];
        if (f == null) break;
        names.add(f.name);
        fid = f.parentId;
      }
      c.quadri = inferQuadriFromNames(names) ?? 1;
    }
  }

  /// JSON "canonique" : tri stable par id pour que deux jeux identiques produisent
  /// exactement le même texte (sert à éviter des envois WebDAV inutiles).
  Map<String, Object?> toJson() {
    List<Map<String, Object?>> sorted(Iterable<Entity> it) {
      final l = it.toList()..sort((a, b) => a.id.compareTo(b.id));
      return l.map((e) => e.toJson()).toList();
    }

    final tomb = Map.fromEntries(
      tombstones.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return {
      'version': currentVersion,
      'updatedAt': updatedAt,
      'folders': sorted(folders),
      'ues': sorted(ues),
      'courses': sorted(courses),
      'sessions': sorted(sessions),
      'blocus': sorted(blocus),
      'plans': sorted(plans),
      'tombstones': tomb,
      'settings': settings.toJson(),
      'settingsUpdatedAt': settingsUpdatedAt,
    };
  }

  /// Retire toute donnée orpheline (séance sans cours, cours sans UE…).
  /// Les UE dont le dossier a disparu remontent à la racine. Retourne true si modifié.
  bool normalize() {
    var changed = false;
    final folderIds = folders.map((e) => e.id).toSet();
    for (final f in folders) {
      if (f.parentId != null && !folderIds.contains(f.parentId)) {
        f.parentId = null;
        changed = true;
      }
    }
    for (final u in ues) {
      if (u.folderId != null && !folderIds.contains(u.folderId)) {
        u.folderId = null;
        changed = true;
      }
    }
    final ueIds = ues.map((e) => e.id).toSet();
    final before = courses.length;
    courses.removeWhere((c) => !ueIds.contains(c.ueId));
    if (courses.length != before) changed = true;
    final courseIds = courses.map((e) => e.id).toSet();
    final beforeS = sessions.length;
    sessions.removeWhere((s) => !courseIds.contains(s.courseId));
    if (sessions.length != beforeS) changed = true;
    final beforeP = plans.length;
    plans.removeWhere((p) => !courseIds.contains(p.courseId));
    if (plans.length != beforeP) changed = true;
    return changed;
  }
}
