import 'dart:convert';
import 'dart:io';

/// Emplacements des fichiers.
///
/// * **Dossier d'amorçage** (`bootstrapDir`) : toujours prévisible. Il contient
///   `location.json` (le pointeur vers un dossier de données personnalisé) et
///   `device.json` (réglages propres à cette machine : identifiants WebDAV, dernière synchro).
///   - Windows : `%APPDATA%\etude-timer`
///   - Linux : `$XDG_CONFIG_HOME/etude-timer` ou `~/.config/etude-timer`
///   - Mode portable : dossier `EtudeTimerData` à côté de l'exécutable.
/// * **Dossier de données** (`dataDir`) : contient `data.json`. Par défaut = dossier d'amorçage ;
///   modifiable par l'utilisateur (pointeur `location.json`).
///
/// Ces chemins sont identiques à ceux de l'ancienne version Electron : un `data.json`
/// existant est donc repris tel quel.
class AppPaths {
  static const String appDirName = 'etude-timer';
  static const String portableDirName = 'EtudeTimerData';
  static const String dataFileName = 'data.json';
  static const String locationFileName = 'location.json';
  static const String deviceFileName = 'device.json';

  final String bootstrapDir;
  final bool isPortable;

  AppPaths._(this.bootstrapDir, this.isPortable);

  /// Construit les chemins à partir de l'environnement. Tous les paramètres sont
  /// injectables pour les tests.
  factory AppPaths.detect({
    Map<String, String>? env,
    String? executablePath,
    bool? isWindows,
    bool? isLinux,
  }) {
    final e = env ?? Platform.environment;
    final win = isWindows ?? Platform.isWindows;
    final linux = isLinux ?? Platform.isLinux;

    final override = e['ETUDE_TIMER_DIR'];
    if (override != null && override.isNotEmpty) return AppPaths._(override, false);

    final exe = executablePath ?? Platform.resolvedExecutable;
    final sep = win ? r'\' : '/';
    final exeDir = _dirname(exe, sep);
    final portable = '$exeDir$sep$portableDirName';
    if (Directory(portable).existsSync()) return AppPaths._(portable, true);

    final home = e['HOME'] ?? e['USERPROFILE'] ?? '.';
    if (win) {
      final appData = e['APPDATA'] ?? '$home\\AppData\\Roaming';
      return AppPaths._('$appData\\$appDirName', false);
    }
    if (linux) {
      final xdg = e['XDG_CONFIG_HOME'];
      final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.config';
      return AppPaths._('$base/$appDirName', false);
    }
    return AppPaths._('$home/Library/Application Support/$appDirName', false);
  }

  /// Chemins explicites (tests).
  factory AppPaths.at(String dir, {bool portable = false}) => AppPaths._(dir, portable);

  static String _dirname(String p, String sep) {
    final i = p.lastIndexOf(sep);
    return i <= 0 ? '.' : p.substring(0, i);
  }

  String get _sep => Platform.isWindows ? r'\' : '/';
  String join(String dir, String name) => dir.endsWith('/') || dir.endsWith(r'\') ? '$dir$name' : '$dir$_sep$name';

  String get locationFile => join(bootstrapDir, locationFileName);
  String get deviceFile => join(bootstrapDir, deviceFileName);
  String dataFileIn(String dir) => join(dir, dataFileName);

  /// Dossier de données effectif : celui du pointeur s'il existe, sinon le dossier d'amorçage.
  String resolveDataDir() {
    try {
      final f = File(locationFile);
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync());
        if (j is Map && j['dataDir'] is String) {
          final d = j['dataDir'] as String;
          if (d.isNotEmpty && Directory(d).existsSync()) return d;
        }
      }
    } catch (_) {
      // pointeur illisible : retour au dossier par défaut
    }
    return bootstrapDir;
  }

  bool isCustom(String dataDir) => _norm(dataDir) != _norm(bootstrapDir);

  static String _norm(String p) {
    var s = p.replaceAll(r'\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return Platform.isWindows ? s.toLowerCase() : s;
  }

  void writeLocation(String dataDir) {
    Directory(bootstrapDir).createSync(recursive: true);
    File(locationFile).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'dataDir': dataDir}));
  }

  void clearLocation() {
    try {
      File(locationFile).deleteSync();
    } catch (_) {}
  }
}
