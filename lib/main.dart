import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/data_store.dart';
import 'core/device_config.dart';
import 'core/paths.dart';
import 'core/single_instance.dart';
import 'platform/alerts.dart';
import 'platform/window_service.dart';
import 'ui/app.dart';
import 'ui/controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mobile = Platform.isAndroid || Platform.isIOS;

  // Bureau : dossier utilisateur (ou portable). Mobile : dossier privé de l'appli, inaccessible
  // aux autres applications (pas de HOME ni d'exécutable à côté duquel écrire).
  final AppPaths paths;
  if (mobile) {
    final support = await getApplicationSupportDirectory();
    paths = AppPaths.at('${support.path}/${AppPaths.appDirName}');
  } else {
    paths = AppPaths.detect();
  }
  final window = WindowService();

  // Bureau : une seule instance par dossier de données, la 2ᵉ ramène la 1ʳᵉ devant et quitte.
  // (Sur mobile, Android/iOS n'ouvrent de toute façon qu'une instance de l'appli.)
  SingleInstance? instance;
  if (!mobile) {
    instance = await SingleInstance.acquire(
      paths.bootstrapDir,
      onShowRequested: () => window.bringToFront(),
    );
    if (instance == null) exit(0);
  }

  final store = DataStore(paths)..load();
  final device = DeviceConfig(paths)..load();
  // Reprend une seule fois les anciens réglages WebDAV d'un data.json 1.x.
  device.migrateLegacy(store.data.legacyWebdav, store.data.legacyLastSyncedAt);

  await window.init();

  final controller = AppController(
    paths: paths,
    store: store,
    device: device,
    alerts: AlertService(),
    window: window,
  )..attachInstance(instance);

  runApp(EtudeTimerApp(controller: controller));
  controller.start();
}
