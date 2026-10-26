import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// Réglages WebDAV. Propres à la machine : jamais envoyés sur le serveur.
class WebdavConfig {
  bool enabled;
  String url;
  String username;
  String password;
  String remotePath;
  int autoSyncMinutes;

  WebdavConfig({
    this.enabled = false,
    this.url = '',
    this.username = '',
    this.password = '',
    this.remotePath = '/EtudeTimer/data.json',
    this.autoSyncMinutes = 5,
  });

  bool get isUsable => enabled && url.trim().isNotEmpty;

  factory WebdavConfig.fromJson(Map<String, Object?> j) => WebdavConfig(
        enabled: j['enabled'] == true,
        url: j['url'] is String ? j['url'] as String : '',
        username: j['username'] is String ? j['username'] as String : '',
        password: j['password'] is String ? j['password'] as String : '',
        remotePath: j['remotePath'] is String && (j['remotePath'] as String).isNotEmpty
            ? j['remotePath'] as String
            : '/EtudeTimer/data.json',
        autoSyncMinutes: j['autoSyncMinutes'] is num ? (j['autoSyncMinutes'] as num).round().clamp(0, 1440) : 5,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'url': url,
        'username': username,
        'password': password,
        'remotePath': remotePath,
        'autoSyncMinutes': autoSyncMinutes,
      };
}

/// `device.json` : configuration locale à cette machine.
///
/// ⚠ Le mot de passe WebDAV est stocké **en clair** dans ce fichier (permissions 600 sous
/// Linux). Utiliser de préférence un « mot de passe d'application » Nextcloud, révocable.
class DeviceConfig {
  final AppPaths paths;
  WebdavConfig webdav = WebdavConfig();
  String? lastSyncedAt;

  DeviceConfig(this.paths);

  bool get exists => File(paths.deviceFile).existsSync();

  void load() {
    try {
      final f = File(paths.deviceFile);
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map) {
        final m = j.cast<String, Object?>();
        if (m['webdav'] is Map) webdav = WebdavConfig.fromJson((m['webdav'] as Map).cast<String, Object?>());
        lastSyncedAt = m['lastSyncedAt'] is String ? m['lastSyncedAt'] as String : null;
      }
    } catch (_) {
      // fichier illisible : on repart d'une config vide, sans rien casser
    }
  }

  void save() {
    Directory(paths.bootstrapDir).createSync(recursive: true);
    final tmp = File('${paths.deviceFile}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'webdav': webdav.toJson(), 'lastSyncedAt': lastSyncedAt}),
    );
    tmp.renameSync(paths.deviceFile);
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        Process.runSync('chmod', ['600', paths.deviceFile]);
      } catch (_) {}
    }
  }

  /// Reprend une seule fois les réglages WebDAV d'un ancien `data.json` (v1.x).
  /// Les mots de passe chiffrés par Electron (safeStorage) ne sont pas lisibles ici.
  void migrateLegacy(Map<String, Object?>? legacy, String? legacyLastSynced) {
    if (exists || legacy == null) return;
    final encrypted = legacy['passwordEncrypted'] == true;
    final wd = WebdavConfig.fromJson(legacy);
    if (encrypted) wd.password = '';
    webdav = wd;
    lastSyncedAt = legacyLastSynced;
    save();
  }
}
