import 'dart:io';

import 'util.dart';

/// Petit journal de la fermeture (`close.log` dans le dossier d'amorçage, local à l'appareil).
///
/// Sert à diagnostiquer un plantage au moment de quitter : la dernière ligne écrite dit jusqu'où
/// la fermeture est allée. Le fichier est tronqué au démarrage ; il ne contient aucune donnée
/// d'étude. Ne lève jamais d'exception.
class CloseLog {
  final String path;
  final DateTime Function() now;
  CloseLog(this.path, {DateTime Function()? now}) : now = now ?? DateTime.now;

  /// Repart d'un fichier vide (appelé au démarrage de l'appli).
  void reset() {
    try {
      File(path).writeAsStringSync('');
    } catch (_) {}
  }

  void add(String message) {
    try {
      final t = now();
      final stamp = '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
      File(path).writeAsStringSync('$stamp  $message\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
