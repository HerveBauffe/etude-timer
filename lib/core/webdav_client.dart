import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device_config.dart';

/// Contenu distant + son ETag (utilisé pour éviter d'écraser une modification concurrente).
class RemoteFile {
  final String text;
  final String? etag;
  const RemoteFile(this.text, this.etag);
}

class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

/// Quelqu'un d'autre a modifié le fichier distant entre notre lecture et notre envoi.
class RemotePreconditionFailed implements Exception {
  const RemotePreconditionFailed();
}

/// Abstraction du stockage distant (permet de tester la synchronisation sans réseau).
abstract class RemoteStorage {
  /// `null` si le fichier n'existe pas encore.
  Future<RemoteFile?> read();

  /// `basedOn == null` : le fichier ne doit pas exister ; sinon il ne doit pas avoir changé.
  /// Lance [RemotePreconditionFailed] en cas de conflit.
  Future<void> write(String text, {RemoteFile? basedOn});
}

/// Client WebDAV minimal (GET / PUT / MKCOL / PROPFIND) sur `dart:io`, sans dépendance.
/// Authentification Basic ; la validation TLS du système n'est jamais désactivée.
class WebDavClient implements RemoteStorage {
  final WebdavConfig config;
  final Duration timeout;
  final HttpClient Function()? clientFactory;

  WebDavClient(this.config, {this.timeout = const Duration(seconds: 20), this.clientFactory});

  Uri _base() {
    final raw = config.url.trim();
    if (raw.isEmpty) throw const SyncException('URL WebDAV non renseignée.');
    final u = Uri.tryParse(raw);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      throw const SyncException("URL WebDAV invalide (elle doit commencer par https://).");
    }
    return u;
  }

  List<String> _segments(String path) => path.split('/').where((s) => s.isNotEmpty).toList();

  Uri _uriFor(List<String> extra) {
    final b = _base();
    return b.replace(pathSegments: [...b.pathSegments.where((s) => s.isNotEmpty), ...extra]);
  }

  Uri get fileUri => _uriFor(_segments(config.remotePath));

  String get _auth => 'Basic ${base64.encode(utf8.encode('${config.username}:${config.password}'))}';

  Future<_Resp> _send(String method, Uri uri, {List<int>? body, Map<String, String>? headers}) async {
    final client = (clientFactory ?? HttpClient.new)();
    client.connectionTimeout = timeout;
    client.userAgent = 'EtudeTimer';
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, _auth);
      headers?.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentLength = body.length;
        req.add(body);
      }
      final resp = await req.close().timeout(timeout);
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout);
      return _Resp(resp.statusCode, bytes, resp.headers.value(HttpHeaders.etagHeader));
    } on SocketException catch (e) {
      throw SyncException('Serveur injoignable : ${e.message}');
    } on HandshakeException {
      throw const SyncException('Certificat TLS refusé (certificat invalide ou auto-signé).');
    } on TimeoutException {
      throw const SyncException('Le serveur ne répond pas (délai dépassé).');
    } on HttpException catch (e) {
      throw SyncException('Erreur HTTP : ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Never _fail(int status) {
    if (status == 401 || status == 403) {
      throw SyncException('Accès refusé ($status) : vérifie identifiant et mot de passe (mot de passe d\'application Nextcloud conseillé).');
    }
    throw SyncException('Réponse inattendue du serveur ($status).');
  }

  @override
  Future<RemoteFile?> read() async {
    final r = await _send('GET', fileUri);
    if (r.status == 404) return null;
    if (r.status < 200 || r.status >= 300) _fail(r.status);
    return RemoteFile(utf8.decode(r.body), r.etag);
  }

  @override
  Future<void> write(String text, {RemoteFile? basedOn}) async {
    final bytes = utf8.encode(text);
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      if (basedOn == null) 'If-None-Match': '*' else if (basedOn.etag != null) 'If-Match': basedOn.etag!,
    };
    var r = await _send('PUT', fileUri, body: bytes, headers: headers);
    if (r.status == 409 || r.status == 404) {
      await _ensureParents();
      r = await _send('PUT', fileUri, body: bytes, headers: headers);
    }
    if (r.status == 412) throw const RemotePreconditionFailed();
    if (r.status < 200 || r.status >= 300) _fail(r.status);
  }

  Future<void> _ensureParents() async {
    final segs = _segments(config.remotePath);
    if (segs.length <= 1) return;
    final dirs = segs.sublist(0, segs.length - 1);
    for (var i = 1; i <= dirs.length; i++) {
      final r = await _send('MKCOL', _uriFor(dirs.sublist(0, i)));
      // 201 créé ; 405 existe déjà ; 301 (dossier existant, redirection) toléré
      if (r.status != 201 && r.status != 405 && r.status != 301 && !(r.status >= 200 && r.status < 300)) {
        _fail(r.status);
      }
    }
  }

  /// Vérifie URL + identifiants (PROPFIND sur le dossier de base).
  Future<void> testConnection() async {
    final r = await _send('PROPFIND', _uriFor(const []), headers: {'Depth': '0'});
    if (r.status == 207 || (r.status >= 200 && r.status < 300)) return;
    if (r.status == 404) throw const SyncException('Dossier introuvable (404) : vérifie l\'URL WebDAV.');
    _fail(r.status);
  }
}

class _Resp {
  final int status;
  final List<int> body;
  final String? etag;
  _Resp(this.status, this.body, this.etag);
}
