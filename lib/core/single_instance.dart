import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Verrou « une seule instance » par dossier de données, via un port local (loopback).
///
/// * 1ʳᵉ instance : ouvre le port et attend les demandes « montre-toi ».
/// * 2ᵉ instance : le port est pris → elle se connecte, demande à la 1ʳᵉ de passer au premier
///   plan, puis doit quitter. Une poignée de main évite de confondre avec un autre programme
///   qui occuperait par hasard le même port (dans ce cas on démarre normalement).
class SingleInstance {
  static const String _hello = 'etude-timer:show';
  static const String _ack = 'etude-timer:ok';

  final ServerSocket? _server;
  final StreamSubscription<Socket>? _sub;

  SingleInstance._(this._server, this._sub);

  /// Port déterministe (40000–59999) dérivé d'une clé (ex. le dossier de données).
  static int portFor(String key) {
    var h = 5381;
    for (final c in key.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return 40000 + h % 20000;
  }

  /// Retourne l'instance verrouillée, ou `null` si une autre instance a été prévenue
  /// (l'appelant doit alors quitter).
  static Future<SingleInstance?> acquire(String key, {required void Function() onShowRequested}) async {
    final port = portFor(key);
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      // ignore: cancel_subscriptions
      final sub = server.listen((client) async {
        try {
          final line = await utf8.decodeStream(client.timeout(const Duration(seconds: 2), onTimeout: (s) => s.close()))
              .timeout(const Duration(seconds: 2));
          if (line.trim() == _hello) {
            client.write(_ack);
            await client.flush();
            onShowRequested();
          }
        } catch (_) {
          // client illisible : ignoré
        } finally {
          client.destroy();
        }
      });
      return SingleInstance._(server, sub);
    } on SocketException {
      // Port occupé : y a-t-il une autre instance de l'appli ?
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
        s.write(_hello);
        await s.flush();
        await s.close(); // demi-fermeture : le serveur lit jusqu'à la fin du flux
        final reply = await utf8.decodeStream(s).timeout(const Duration(seconds: 2));
        s.destroy();
        if (reply.trim() == _ack) return null;
      } catch (_) {}
      return _unlocked();
    }
  }

  /// Port occupé par un autre programme : on démarre sans verrou.
  static SingleInstance _unlocked() => SingleInstance._(null, null);

  Future<void> release() async {
    await _sub?.cancel();
    await _server?.close();
  }
}
