import 'dart:io';

import 'package:etude_timer/core/close_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal de fermeture : lignes horodatées, remise à zéro, jamais d\'exception', () {
    final dir = Directory.systemTemp.createTempSync('closelog');
    try {
      final path = '${dir.path}/close.log';
      final log = CloseLog(path, now: () => DateTime(2026, 10, 27, 1, 2, 3, 45));
      log.add('arrêt : début');
      log.add('fenêtre : close() accepté');
      expect(File(path).readAsLinesSync(), equals(['01:02:03.045  arrêt : début', '01:02:03.045  fenêtre : close() accepté']));
      log.reset();
      expect(File(path).readAsStringSync(), isEmpty);
      // dossier inexistant : on avale l'erreur (la fermeture ne doit jamais échouer à cause du journal)
      CloseLog('${dir.path}/absent/close.log').add('x');
      CloseLog('${dir.path}/absent/close.log').reset();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
