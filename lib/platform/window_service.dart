import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Fenêtre de bureau : taille minimale, passage au premier plan, interception de la fermeture.
class WindowService with WindowListener {
  /// Appelé quand l'utilisateur ferme la fenêtre. Doit finir par appeler [destroy].
  Future<void> Function()? onCloseRequested;

  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1120, 760),
      minimumSize: Size(780, 580),
      center: true,
      title: 'Étude Timer',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() {
    final cb = onCloseRequested;
    if (cb != null) {
      cb();
    } else {
      destroy();
    }
  }

  /// Ramène la fenêtre devant les autres (fin de phase, 2ᵉ lancement de l'appli).
  Future<void> bringToFront() async {
    if (!isDesktop) return;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
      // Certains gestionnaires de fenêtres refusent le focus ; un bref « toujours au-dessus » aide.
      await windowManager.setAlwaysOnTop(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {
      // sans fenêtre (tests) : ignoré
    }
  }

  Future<void> destroy() async {
    if (!isDesktop) {
      exit(0);
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
