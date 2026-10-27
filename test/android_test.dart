import 'package:etude_timer/core/paths.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/patch_android.dart';

const _generated = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="etude_timer"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true"/>
    </application>
</manifest>
''';

void main() {
  group('patch du projet Android', () {
    test('ajoute INTERNET, le nom et les règles de sauvegarde', () {
      final out = patchManifest(_generated);
      expect(out, contains('<uses-permission android:name="android.permission.INTERNET"/>'));
      expect(out, contains('android:label="Étude Timer"'));
      expect(out, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(out, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      // la permission est déclarée avant <application> (hors de l'élément)
      expect(out.indexOf('uses-permission'), lessThan(out.indexOf('<application')));
    });

    test('idempotent : relancer ne change plus rien', () {
      final once = patchManifest(_generated);
      expect(patchManifest(once), equals(once));
      expect('uses-permission'.allMatches(once).length, equals(1));
    });

    test('respecte une permission INTERNET déjà présente', () {
      final withPerm = _generated.replaceFirst(
        '<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
      );
      expect('android.permission.INTERNET'.allMatches(patchManifest(withPerm)).length, equals(1));
    });

    test("les règles d'exclusion visent bien le fichier device.json de l'appli", () {
      final p = AppPaths.at('/data/user/0/be.etudetimer.etude_timer/files/${AppPaths.appDirName}');
      final relative = p.deviceFile.split('/files/').last;
      expect(backupRules, contains('path="$relative"'));
      expect(dataExtractionRules, contains('path="$relative"'));
    });
  });

  group('stockage mobile', () {
    test('AppPaths.at : données et réglages locaux dans le dossier privé, sans portable', () {
      final p = AppPaths.at('/data/user/0/app/files/etude-timer');
      expect(p.isPortable, isFalse);
      expect(p.dataFileIn(p.bootstrapDir), equals('/data/user/0/app/files/etude-timer/data.json'));
      expect(p.deviceFile, equals('/data/user/0/app/files/etude-timer/device.json'));
    });
  });
}
