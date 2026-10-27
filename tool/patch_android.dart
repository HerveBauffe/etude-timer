// Adapte le projet Android généré par `flutter create` (appelé par scripts/bootstrap.*) :
//  * permission INTERNET (absente du manifeste « release » généré : sans elle, WebDAV ne marche
//    pas dans l'APK final, alors que tout marche en debug) ;
//  * nom affiché « Étude Timer » ;
//  * sauvegarde automatique Android : les données d'étude sont sauvegardées, mais PAS
//    `device.json` (il contient le mot de passe WebDAV en clair).
//
// Usage : dart tool/patch_android.dart [dossier-du-projet]
// Idempotent : peut être relancé sans risque.
import 'dart:io';

const _label = 'Étude Timer';

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : '.';
  final manifest = File('$root/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('AndroidManifest.xml introuvable dans $root/android — lance d\'abord `flutter create --platforms=android .`');
    exit(1);
  }
  final out = patchManifest(manifest.readAsStringSync());
  manifest.writeAsStringSync(out);

  final xmlDir = Directory('$root/android/app/src/main/res/xml')..createSync(recursive: true);
  File('${xmlDir.path}/backup_rules.xml').writeAsStringSync(backupRules);
  File('${xmlDir.path}/data_extraction_rules.xml').writeAsStringSync(dataExtractionRules);
  stdout.writeln('Projet Android adapté (INTERNET, nom, règles de sauvegarde).');
}

/// Fonction pure (testable) : applique les modifications au texte du manifeste.
String patchManifest(String xml) {
  var s = xml;

  if (!s.contains('android.permission.INTERNET')) {
    s = s.replaceFirstMapped(
      RegExp(r'(\s*)<application'),
      (m) => '${m[1]}<uses-permission android:name="android.permission.INTERNET"/>${m[1]}<application',
    );
  }

  s = s.replaceFirstMapped(RegExp(r'android:label="[^"]*"'), (_) => 'android:label="$_label"');

  final attrs = <String, String>{
    'android:allowBackup': 'true',
    'android:fullBackupContent': '@xml/backup_rules',
    'android:dataExtractionRules': '@xml/data_extraction_rules',
  };
  for (final e in attrs.entries) {
    final has = RegExp('${RegExp.escape(e.key)}="[^"]*"');
    if (has.hasMatch(s)) {
      s = s.replaceFirst(has, '${e.key}="${e.value}"');
    } else {
      s = s.replaceFirstMapped(RegExp(r'(<application\b)'), (m) => '${m[1]}\n        ${e.key}="${e.value}"');
    }
  }
  return s;
}

const backupRules = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Sauvegarde Android (Android 11 et moins) : tout sauf les réglages propres à l'appareil. -->
<full-backup-content>
    <exclude domain="file" path="etude-timer/device.json"/>
</full-backup-content>
''';

const dataExtractionRules = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Sauvegarde cloud et transfert d'appareil (Android 12+) : device.json (mot de passe WebDAV) exclu. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="file" path="etude-timer/device.json"/>
    </cloud-backup>
    <device-transfer>
        <exclude domain="file" path="etude-timer/device.json"/>
    </device-transfer>
</data-extraction-rules>
''';
