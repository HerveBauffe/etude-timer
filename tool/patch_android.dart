// Adapte le projet Android généré par `flutter create` (appelé par scripts/bootstrap.*) :
//  * permission INTERNET (absente du manifeste « release » généré : sans elle, WebDAV ne marche
//    pas dans l'APK final, alors que tout marche en debug) ;
//  * nom affiché « Étude Timer » ;
//  * sauvegarde automatique Android : les données d'étude sont sauvegardées, mais PAS
//    `device.json` (il contient le mot de passe WebDAV en clair) ni `session.json` ;
//  * chrono en arrière-plan : permissions (notifications, service de premier plan, alarme exacte,
//    notification plein écran), service + récepteurs du plugin de notifications, écran réveillé par
//    l'activité principale, icône de notification, et « desugaring » Java exigé par le plugin.
//
// Usage : dart tool/patch_android.dart [dossier-du-projet] [--no-ndk]
//   --no-ndk : retire `ndkVersion = flutter.ndkVersion` du build.gradle de l'appli. Cette appli
//              n'a aucun code natif : si Gradle n'arrive pas à installer le NDK demandé par Flutter
//              (« Android sdkmanager did not install NDK »), cela évite d'en avoir besoin.
// Idempotent : peut être relancé sans risque.
import 'dart:io';

const _label = 'Étude Timer';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final root = positional.isNotEmpty ? positional.first : '.';
  final noNdk = args.contains('--no-ndk');
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

  final drawDir = Directory('$root/android/app/src/main/res/drawable')..createSync(recursive: true);
  File('${drawDir.path}/ic_stat_timer.xml').writeAsStringSync(notificationIcon);

  // Le plugin retrouve l'icône par son nom à l'exécution : sans ce fichier, le « resource shrinking »
  // des builds release la supprime (erreur invalid_icon).
  final rawDir = Directory('$root/android/app/src/main/res/raw')..createSync(recursive: true);
  File('${rawDir.path}/keep.xml').writeAsStringSync(keepResources);

  var gradleFound = false;
  for (final name in ['build.gradle.kts', 'build.gradle']) {
    final f = File('$root/android/app/$name');
    if (!f.existsSync()) continue;
    gradleFound = true;
    final before = f.readAsStringSync();
    final after = patchGradle(before, kotlin: name.endsWith('.kts'));
    if (after != before) f.writeAsStringSync(after);
  }
  if (!gradleFound) {
    stderr.writeln('android/app/build.gradle(.kts) introuvable : desugaring Java non activé (le plugin de notifications en a besoin).');
  }
  stdout.writeln('Projet Android adapté (INTERNET, nom, sauvegarde, chrono en arrière-plan).');

  if (noNdk) {
    var found = false;
    for (final name in ['build.gradle.kts', 'build.gradle']) {
      final f = File('$root/android/app/$name');
      if (!f.existsSync()) continue;
      found = true;
      final before = f.readAsStringSync();
      final after = removeNdkVersion(before);
      if (after != before) f.writeAsStringSync(after);
      stdout.writeln(after != before ? 'ndkVersion retiré de android/app/$name.' : 'Pas de ndkVersion à retirer dans android/app/$name.');
    }
    if (!found) stderr.writeln('android/app/build.gradle(.kts) introuvable : --no-ndk ignoré.');
  }
}

/// Fonction pure (testable) : neutralise la ligne `ndkVersion = flutter.ndkVersion`.
String removeNdkVersion(String gradle) => gradle.replaceAllMapped(
      RegExp(r'^([ \t]*)ndkVersion\s*=?\s*flutter\.ndkVersion[ \t]*$', multiLine: true),
      (m) => '${m[1]}// ndkVersion retiré (tool/patch_android.dart --no-ndk) : aucun code natif dans cette appli',
    );

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

  s = _addPermissions(s);
  s = _addComponents(s);
  s = _patchMainActivity(s);

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

// ───────────────────────── Chrono en arrière-plan ─────────────────────────

const _permissions = <String, String>{
  'android.permission.POST_NOTIFICATIONS': '', // Android 13+ : afficher la notification du chrono
  'android.permission.VIBRATE': '',
  'android.permission.FOREGROUND_SERVICE': '', // service qui garde le chrono vivant
  'android.permission.FOREGROUND_SERVICE_SPECIAL_USE': '',
  'android.permission.USE_FULL_SCREEN_INTENT': '', // réveiller l'écran à la fin d'une phase
  'android.permission.USE_EXACT_ALARM': '', // alarme de fin de phase à la seconde près (appli de minuterie)
  'android.permission.SCHEDULE_EXACT_ALARM': ' android:maxSdkVersion="32"', // Android 12 : à accorder par l'utilisateur
  'android.permission.RECEIVE_BOOT_COMPLETED': '', // ré-armer l'alarme après un redémarrage
};

String _addPermissions(String xml) {
  final missing = <String>[];
  for (final e in _permissions.entries) {
    if (!xml.contains('"${e.key}"')) missing.add('<uses-permission android:name="${e.key}"${e.value}/>');
  }
  if (missing.isEmpty) return xml;
  return xml.replaceFirstMapped(
    RegExp(r'(\s*)<application'),
    (m) => '${m[1]}${missing.join(m[1]!)}${m[1]}<application',
  );
}

const _components = '''
        <!-- Chrono en arrière-plan (flutter_local_notifications) : alarme de fin de phase, bouton de la notification, service de premier plan -->
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" android:exported="false"/>
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" android:exported="false"/>
        <service
            android:name="com.dexterous.flutterlocalnotifications.ForegroundService"
            android:exported="false"
            android:stopWithTask="false"
            android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="study_timer"/>
        </service>
''';

String _addComponents(String xml) {
  if (xml.contains('com.dexterous.flutterlocalnotifications.ForegroundService')) return xml;
  return xml.replaceFirstMapped(RegExp(r'[ \t]*</application>'), (_) => '$_components    </application>');
}

/// Réveille l'écran et s'affiche par-dessus l'écran de verrouillage quand la notification de fin
/// de phase se déclenche (notification plein écran).
String _patchMainActivity(String xml) {
  return xml.replaceFirstMapped(RegExp(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*?(?=/?>)'), (m) {
    var tag = m[0]!;
    for (final a in const ['android:showWhenLocked', 'android:turnScreenOn']) {
      final re = RegExp('${RegExp.escape(a)}="[^"]*"');
      if (re.hasMatch(tag)) {
        tag = tag.replaceFirst(re, '$a="true"');
      } else {
        tag = '$tag\n            $a="true"';
      }
    }
    return tag;
  });
}

/// Fonction pure (testable) : le plugin de notifications exige `compileSdk ≥ 35` et le « desugaring »
/// des bibliothèques Java (java.time sur les vieux Android).
String patchGradle(String gradle, {required bool kotlin}) {
  var s = gradle;
  const lib = 'com.android.tools:desugar_jdk_libs:2.1.5';

  // compileSdk numérique trop bas (les modèles récents utilisent flutter.compileSdkVersion, déjà ≥ 35)
  s = s.replaceAllMapped(RegExp(r'^([ \t]*compileSdk(?:Version)?\s*=?\s*)(\d+)[ \t]*$', multiLine: true),
      (m) => int.parse(m[2]!) < 35 ? '${m[1]}35' : m[0]!);

  if (!s.contains('oreLibraryDesugaring')) {
    final flag = kotlin ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
    final compileOptions = RegExp(r'^([ \t]*)compileOptions\s*\{[ \t]*$', multiLine: true);
    if (compileOptions.hasMatch(s)) {
      s = s.replaceFirstMapped(compileOptions, (m) => '${m[0]}\n${m[1]}    $flag');
    } else {
      // pas de bloc compileOptions : on en crée un juste après `android {`
      s = s.replaceFirstMapped(RegExp(r'^android\s*\{[ \t]*$', multiLine: true),
          (m) => '${m[0]}\n    compileOptions {\n        $flag\n    }');
    }
    final dep = kotlin ? 'coreLibraryDesugaring("$lib")' : "coreLibraryDesugaring '$lib'";
    final deps = RegExp(r'^dependencies\s*\{[ \t]*$', multiLine: true);
    if (deps.hasMatch(s)) {
      s = s.replaceFirstMapped(deps, (m) => '${m[0]}\n    $dep');
    } else {
      s = '${s.trimRight()}\n\ndependencies {\n    $dep\n}\n';
    }
  }
  return s;
}

/// Empêche R8 de retirer l'icône de notification (référencée uniquement par son nom).
const keepResources = '''<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_timer"
    tools:shrinkMode="strict"/>
''';

/// Icône de la notification (chronomètre Material, blanc uni : Android la teinte lui-même).
const notificationIcon = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M15,1L9,1v2h6L15,1zM11,14h2L13,8h-2v6zM19.03,7.39l1.42,-1.42c-0.43,-0.51 -0.9,-0.99 -1.41,-1.41l-1.42,1.42C16.07,4.74 14.12,4 12,4c-4.97,0 -9,4.03 -9,9s4.02,9 9,9 9,-4.03 9,-9c0,-2.12 -0.74,-4.07 -1.97,-5.61zM12,20c-3.87,0 -7,-3.13 -7,-7s3.13,-7 7,-7 7,3.13 7,7 -3.13,7 -7,7z"/>
</vector>
''';

const backupRules = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Sauvegarde Android (Android 11 et moins) : tout sauf les réglages propres à l'appareil. -->
<full-backup-content>
    <exclude domain="file" path="etude-timer/device.json"/>
    <exclude domain="file" path="etude-timer/session.json"/>
</full-backup-content>
''';

const dataExtractionRules = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Sauvegarde cloud et transfert d'appareil (Android 12+) : device.json (mot de passe WebDAV) exclu. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="file" path="etude-timer/device.json"/>
        <exclude domain="file" path="etude-timer/session.json"/>
    </cloud-backup>
    <device-transfer>
        <exclude domain="file" path="etude-timer/device.json"/>
        <exclude domain="file" path="etude-timer/session.json"/>
    </device-transfer>
</data-extraction-rules>
''';
