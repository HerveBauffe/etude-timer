import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Fenêtre de bureau : taille minimale, passage au premier plan, interception de la fermeture.
class WindowService with WindowListener {
  /// Appelé quand l'utilisateur ferme la fenêtre. Doit finir par appeler [destroy].
  Future<void> Function()? onCloseRequested;

  /// Journal de fermeture (diagnostic) ; branché par le contrôleur.
  void Function(String message)? log;

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

  bool _closing = false;

  /// Demande de fermeture (croix, Alt+F4…). Réentrance impossible : sous Linux, `destroy()`
  /// referme la fenêtre GTK et le plugin renvoie alors un nouvel événement « close » ; sans
  /// garde, la routine d'arrêt (synchro, libération du verrou, destruction) tournait deux fois
  /// et la seconde passe agissait sur une fenêtre déjà détruite → plantage à la fermeture.
  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    final cb = onCloseRequested;
    () async {
      try {
        if (cb != null) await cb();
      } catch (_) {
        // quoi qu'il arrive à l'enregistrement/synchro, la fenêtre doit pouvoir se fermer
      } finally {
        await destroy();
      }
    }();
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

  bool _destroyed = false;

  /// Ferme la fenêtre. Sur bureau on suit le chemin de fermeture **normal** de la fenêtre
  /// (désactivation du blocage, puis `close`) plutôt que `destroy()` : l'arrêt du moteur Flutter
  /// se fait alors exactement comme pour n'importe quelle application Flutter, sans court-circuiter
  /// la boucle de messages de Windows (c'est là que le plantage à la fermeture se produisait).
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    log?.call('fenêtre : fermeture demandée');
    if (!isDesktop) {
      exit(0);
    }
    try {
      // Laisse se terminer les opérations réseau/sockets fermées juste avant (sous Windows leur
      // achèvement est asynchrone) avant d'arrêter le moteur : fermer la fenêtre pendant qu'elles
      // se terminent est une cause classique de plantage à la sortie.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      windowManager.removeListener(this); // plus d'événements : la fenêtre va disparaître
      await windowManager.setPreventClose(false);
      log?.call('fenêtre : blocage levé, appel de close()');
      await windowManager.close();
      log?.call('fenêtre : close() accepté');
    } catch (e) {
      log?.call('fenêtre : erreur $e');
    }
    // Filet de sécurité : si le processus est toujours là 4 s après, on le termine.
    Future<void>.delayed(const Duration(seconds: 4), () {
      log?.call('fenêtre : toujours en vie après 4 s, exit(0)');
      exit(0);
    });
  }
}
