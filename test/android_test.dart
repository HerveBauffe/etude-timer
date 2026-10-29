import 'package:etude_timer/core/paths.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/patch_android.dart';

const _generated = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="etude_timer"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
            </intent-filter>
        </activity>
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
      expect('android.permission.INTERNET'.allMatches(once).length, equals(1));
      expect('ForegroundService'.allMatches(once).length, equals(1));
      expect('android:showWhenLocked'.allMatches(once).length, equals(1));
    });

    test('chrono en arrière-plan : permissions, service, récepteurs, écran réveillé', () {
      final out = patchManifest(_generated);
      for (final p in [
        'POST_NOTIFICATIONS',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_SPECIAL_USE',
        'USE_FULL_SCREEN_INTENT',
        'USE_EXACT_ALARM',
        'RECEIVE_BOOT_COMPLETED',
      ]) {
        expect(out, contains('<uses-permission android:name="android.permission.$p"/>'));
      }
      expect(out, contains('android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"'));
      expect(out, contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'));
      expect(out, contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'));
      expect(out, contains('com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver'));
      expect(out, contains('android:foregroundServiceType="specialUse"'));
      expect(out, contains('PROPERTY_SPECIAL_USE_FGS_SUBTYPE'));
      // composants à l'intérieur de <application>, permissions avant
      expect(out.indexOf('ForegroundService'), lessThan(out.indexOf('</application>')));
      expect(out.lastIndexOf('<uses-permission'), lessThan(out.indexOf('<application')));
      // attributs ajoutés à l'activité principale (et pas ailleurs), ses autres attributs conservés
      final activity = RegExp(r'<activity[^>]*>').firstMatch(out)!.group(0)!;
      expect(activity, contains('android:showWhenLocked="true"'));
      expect(activity, contains('android:turnScreenOn="true"'));
      expect(activity, contains('android:launchMode="singleTop"'));
    });

    test("ne duplique pas une permission déjà déclarée, corrige showWhenLocked=false", () {
      final pre = _generated
          .replaceFirst('<application', '<uses-permission android:name="android.permission.VIBRATE"/>\n    <application')
          .replaceFirst('android:exported="true"', 'android:exported="true" android:showWhenLocked="false"');
      final out = patchManifest(pre);
      expect('android.permission.VIBRATE'.allMatches(out).length, equals(1));
      expect(out, contains('android:showWhenLocked="true"'));
      expect(out, isNot(contains('showWhenLocked="false"')));
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

    test("la séance en cours (session.json) n'est jamais sauvegardée dans le cloud", () {
      final p = AppPaths.at('/data/user/0/be.etudetimer.etude_timer/files/${AppPaths.appDirName}');
      final relative = p.sessionFile.split('/files/').last;
      expect(backupRules, contains('path="$relative"'));
      expect(dataExtractionRules, contains('path="$relative"'));
    });

    test("l'icône est protégée du resource shrinking des builds release", () {
      expect(keepResources, contains('tools:keep="@drawable/ic_stat_timer"'));
    });

    test('icône de notification : vecteur valide', () {
      expect(notificationIcon, contains('<vector'));
      expect(notificationIcon, contains('android:pathData='));
    });
  });

  group('Gradle (desugaring Java, compileSdk)', () {
    const kts = '''plugins { id("com.android.application") }

android {
    namespace = "be.etudetimer.etude_timer"
    compileSdk = flutter.compileSdkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

flutter {
    source = "../.."
}
''';

    test('Kotlin DSL : active le desugaring et ajoute la dépendance, idempotent', () {
      final out = patchGradle(kts, kotlin: true);
      expect(out, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(out, contains('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:'));
      expect(out.indexOf('isCoreLibraryDesugaringEnabled'), greaterThan(out.indexOf('compileOptions')));
      expect(out, contains('sourceCompatibility = JavaVersion.VERSION_17'));
      expect(out, contains('compileSdk = flutter.compileSdkVersion'));
      expect(patchGradle(out, kotlin: true), equals(out));
    });

    test('Kotlin DSL : dépendances existantes conservées', () {
      final out = patchGradle('$kts\ndependencies {\n    implementation("a:b:1")\n}\n', kotlin: true);
      expect('dependencies {'.allMatches(out).length, equals(1));
      expect(out, contains('implementation("a:b:1")'));
      expect(out, contains('coreLibraryDesugaring('));
    });

    test('Groovy', () {
      const groovy = '''android {
    compileSdkVersion 33
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
    }
}
''';
      final out = patchGradle(groovy, kotlin: false);
      expect(out, contains('coreLibraryDesugaringEnabled true'));
      expect(out, contains("coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:"));
      expect(out, contains('compileSdkVersion 35'));
    });

    test('sans bloc compileOptions : il est créé', () {
      final out = patchGradle('android {\n    namespace = "x"\n}\n', kotlin: true);
      expect(out, contains('compileOptions {'));
      expect(out, contains('isCoreLibraryDesugaringEnabled = true'));
    });

    test('compileSdk numérique déjà suffisant : inchangé', () {
      final out = patchGradle('android {\n    compileSdk = 36\n}\n', kotlin: true);
      expect(out, contains('compileSdk = 36'));
    });
  });

  group('option --no-ndk', () {
    test('neutralise ndkVersion = flutter.ndkVersion (Kotlin DSL) et reste idempotent', () {
      const kts = '''android {
    namespace = "be.etudetimer.etude_timer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    defaultConfig { minSdk = flutter.minSdkVersion }
}
''';
      final out = removeNdkVersion(kts);
      expect(out, isNot(contains('ndkVersion = flutter.ndkVersion')));
      expect(out, contains('    // ndkVersion retiré'));
      expect(out, contains('compileSdk = flutter.compileSdkVersion'));
      expect(removeNdkVersion(out), equals(out));
    });

    test('Groovy : ndkVersion flutter.ndkVersion', () {
      const groovy = "android {\n    ndkVersion flutter.ndkVersion\n}\n";
      expect(removeNdkVersion(groovy), isNot(contains('flutter.ndkVersion')));
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
