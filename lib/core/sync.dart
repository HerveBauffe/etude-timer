import 'dart:convert';

import 'data_store.dart';
import 'device_config.dart';
import 'models.dart';
import 'util.dart';
import 'webdav_client.dart';

/// Fusionne deux jeux de données. Fonction pure, symétrique (merge(a,b) == merge(b,a)) :
/// deux machines qui fusionnent dans des ordres différents convergent vers le même résultat.
///
/// * Chaque entité : la plus récente (`updatedAt`) gagne.
/// * Suppressions : une « pierre tombale » plus récente que l'entité l'emporte ;
///   une entité modifiée APRÈS sa suppression est conservée (la pierre est alors retirée).
/// * Réglages : le plus récent (`settingsUpdatedAt`) gagne.
/// * Données orphelines (séance sans cours, etc.) nettoyées.
AppData mergeData(AppData a, AppData b, {DateTime? now}) {
  final tomb = <String, String>{};
  for (final src in [a.tombstones, b.tombstones]) {
    src.forEach((id, at) {
      final cur = tomb[id];
      if (cur == null || compareIso(at, cur) > 0) tomb[id] = at;
    });
  }

  List<T> mergeList<T extends Entity>(List<T> la, List<T> lb) {
    final byId = <String, T>{};
    for (final e in [...la, ...lb]) {
      final cur = byId[e.id];
      if (cur == null) {
        byId[e.id] = e;
        continue;
      }
      final c = compareIso(e.updatedAt, cur.updatedAt);
      if (c > 0 || (c == 0 && jsonEncode(e.toJson()).compareTo(jsonEncode(cur.toJson())) > 0)) {
        byId[e.id] = e;
      }
    }
    final out = <T>[];
    for (final e in byId.values) {
      final t = tomb[e.id];
      if (t != null) {
        if (compareIso(t, e.updatedAt) >= 0) continue; // supprimé après la dernière modif
        tomb.remove(e.id); // modifié après la suppression : on garde
      }
      out.add(e);
    }
    return out;
  }

  // Copies profondes : on ne modifie jamais les arguments.
  AppData copy(AppData d) => AppData.fromJson(d.toJson());
  final ca = copy(a);
  final cb = copy(b);

  final sa = compareIso(ca.settingsUpdatedAt, cb.settingsUpdatedAt);
  final pickA = sa > 0 ||
      (sa == 0 && jsonEncode(ca.settings.toJson()).compareTo(jsonEncode(cb.settings.toJson())) >= 0);

  final merged = AppData(
    updatedAt: compareIso(ca.updatedAt, cb.updatedAt) >= 0 ? ca.updatedAt : cb.updatedAt,
    folders: mergeList(ca.folders, cb.folders),
    ues: mergeList(ca.ues, cb.ues),
    courses: mergeList(ca.courses, cb.courses),
    sessions: mergeList(ca.sessions, cb.sessions),
    blocus: mergeList(ca.blocus, cb.blocus),
    tombstones: tomb,
    settings: pickA ? ca.settings : cb.settings,
    settingsUpdatedAt: pickA ? ca.settingsUpdatedAt : cb.settingsUpdatedAt,
  );
  merged.normalize();

  final limit = (now ?? DateTime.now()).subtract(const Duration(days: 365)).millisecondsSinceEpoch;
  merged.tombstones.removeWhere((_, v) => (DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0) < limit);
  return merged;
}

/// Texte exact envoyé au serveur (JSON canonique, trié, sans espaces superflus).
String canonicalJson(AppData d) => jsonEncode(d.toJson());

class SyncOutcome {
  final bool localChanged;
  final bool uploaded;
  final String message;
  const SyncOutcome({required this.localChanged, required this.uploaded, required this.message});
}

/// Synchronise le magasin local avec le stockage distant.
class SyncService {
  final DataStore store;
  final DeviceConfig device;
  final RemoteStorage Function() remoteFactory;
  final DateTime Function() now;
  bool _running = false;

  SyncService(this.store, this.device, this.remoteFactory, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  bool get isRunning => _running;

  /// Lance une synchronisation. Ignorée si une autre est déjà en cours.
  Future<SyncOutcome> sync() async {
    if (_running) return const SyncOutcome(localChanged: false, uploaded: false, message: 'Synchronisation déjà en cours.');
    _running = true;
    try {
      return await _syncWithRetry();
    } finally {
      _running = false;
    }
  }

  Future<SyncOutcome> _syncWithRetry() async {
    final remote = remoteFactory();
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _once(remote);
      } on RemotePreconditionFailed {
        continue; // quelqu'un a écrit entre-temps : on relit et on refusionne
      }
    }
    throw const SyncException('Le fichier distant change sans arrêt ; réessaie dans un instant.');
  }

  Future<SyncOutcome> _once(RemoteStorage remote) async {
    final file = await remote.read();
    final local = store.data;
    var localChanged = false;
    var uploaded = false;

    AppData result;
    if (file == null) {
      result = mergeData(local, AppData.empty(), now: now());
    } else {
      AppData remoteData;
      try {
        final j = jsonDecode(file.text);
        if (j is! Map) throw const FormatException('racine JSON invalide');
        remoteData = AppData.fromJson(j.cast<String, Object?>());
      } on FormatException {
        // Ne JAMAIS écraser un fichier distant illisible.
        throw const SyncException('Le fichier distant est illisible (JSON invalide) : synchronisation annulée.');
      }
      result = mergeData(local, remoteData, now: now());
    }

    final resultJson = canonicalJson(result);
    if (resultJson != canonicalJson(local)) {
      store.replaceAll(result);
      localChanged = true;
    }
    if (file == null || resultJson != _canonicalOfText(file.text)) {
      await remote.write(resultJson, basedOn: file);
      uploaded = true;
    }

    device.lastSyncedAt = isoUtc(now());
    device.save();
    store.dirty = false;

    final msg = switch ((localChanged, uploaded)) {
      (true, true) => 'Fusionné : données locales et distantes mises à jour.',
      (true, false) => 'Données distantes récupérées.',
      (false, true) => 'Données locales envoyées.',
      (false, false) => 'Déjà à jour.',
    };
    return SyncOutcome(localChanged: localChanged, uploaded: uploaded, message: msg);
  }

  String _canonicalOfText(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map) return canonicalJson(AppData.fromJson(j.cast<String, Object?>()));
    } catch (_) {}
    return '';
  }
}
