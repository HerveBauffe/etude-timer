import 'dart:io';

import 'package:flutter/services.dart';

/// Alertes de fin de phase : son + notification du bureau (Linux).
///
/// * Son : Linux → `canberra-gtk-play` ou `paplay` s'ils existent, sinon le bip système ;
///   Windows → bip système (MessageBeep).
/// * Notification du bureau : Linux uniquement, via `notify-send` s'il est installé.
///   Sous Windows, pas de notification système : l'appli passe au premier plan
///   (voir WindowService) et affiche un message dans la fenêtre.
class AlertService {
  bool _soundBusy = false;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<void> playSound() async {
    if (_soundBusy) return;
    _soundBusy = true;
    try {
      if (_mobile) {
        // Android n'a pas de « bip système » utilisable depuis Flutter : on vibre (3 impulsions).
        // Le son et la notification quand l'écran est éteint demanderont un service d'arrière-plan.
        for (var i = 0; i < 3; i++) {
          await HapticFeedback.vibrate();
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        return;
      }
      if (Platform.isLinux) {
        for (final cmd in const [
          ['canberra-gtk-play', '-i', 'complete'],
          ['paplay', '/usr/share/sounds/freedesktop/stereo/complete.oga'],
        ]) {
          try {
            final r = await Process.run(cmd.first, cmd.sublist(1)).timeout(const Duration(seconds: 5));
            if (r.exitCode == 0) return;
          } catch (_) {
            // commande absente : on essaie la suivante
          }
        }
      }
      await SystemSound.play(SystemSoundType.alert);
    } finally {
      _soundBusy = false;
    }
  }

  Future<void> notify(String title, String body) async {
    if (!Platform.isLinux) return; // Windows/mobile : message affiché dans l'appli
    try {
      await Process.run('notify-send', ['--app-name=Étude Timer', '--urgency=normal', title, body])
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // notify-send absent : l'alerte reste visible dans la fenêtre
    }
  }
}
