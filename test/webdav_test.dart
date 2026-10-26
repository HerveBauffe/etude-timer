import 'dart:convert';
import 'dart:io';

import 'package:etude_timer/core/device_config.dart';
import 'package:etude_timer/core/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mini serveur WebDAV local (GET / PUT / MKCOL / PROPFIND, Basic auth, ETag, If-Match).
class FakeDav {
  late HttpServer server;
  final Map<String, String> files = {};
  final Set<String> dirs = {'/dav'};
  final Map<String, int> versions = {};
  final List<String> log = [];
  String user = 'me';
  String pass = 'pw';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  int get port => server.port;

  Future<void> _handle(HttpRequest r) async {
    final path = Uri.decodeFull(r.uri.path);
    log.add('${r.method} $path');
    final auth = r.headers.value('authorization');
    final expected = 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';
    if (auth != expected) {
      r.response.statusCode = 401;
      await r.response.close();
      return;
    }
    final body = await utf8.decodeStream(r);
    final parent = path.substring(0, path.lastIndexOf('/'));
    switch (r.method) {
      case 'PROPFIND':
        r.response.statusCode = dirs.contains(path.replaceAll(RegExp(r'/$'), '')) ? 207 : 404;
      case 'MKCOL':
        if (dirs.contains(path)) {
          r.response.statusCode = 405;
        } else if (!dirs.contains(parent)) {
          r.response.statusCode = 409;
        } else {
          dirs.add(path);
          r.response.statusCode = 201;
        }
      case 'GET':
        if (files.containsKey(path)) {
          r.response.headers.set('ETag', '"${versions[path]}"');
          r.response.write(files[path]);
        } else {
          r.response.statusCode = 404;
        }
      case 'PUT':
        if (!dirs.contains(parent)) {
          r.response.statusCode = 409;
        } else if (r.headers.value('if-none-match') == '*' && files.containsKey(path)) {
          r.response.statusCode = 412;
        } else if (r.headers.value('if-match') != null && r.headers.value('if-match') != '"${versions[path]}"') {
          r.response.statusCode = 412;
        } else {
          final existed = files.containsKey(path);
          files[path] = body;
          versions[path] = (versions[path] ?? 0) + 1;
          r.response.statusCode = existed ? 204 : 201;
        }
      default:
        r.response.statusCode = 405;
    }
    await r.response.close();
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  late FakeDav dav;
  late WebdavConfig cfg;

  setUp(() async {
    dav = FakeDav();
    await dav.start();
    cfg = WebdavConfig(enabled: true, url: 'http://127.0.0.1:${dav.port}/dav', username: 'me', password: 'pw', remotePath: '/EtudeTimer/sub/data.json');
  });

  group('client WebDAV', () {
    test('lecture d\'un fichier absent = null', () async {
      expect(await WebDavClient(cfg).read(), isNull);
      await dav.stop();
    });

    test('création : crée les dossiers manquants puis envoie le fichier', () async {
      final c = WebDavClient(cfg);
      await c.write('{"a":1}');
      expect(dav.files['/dav/EtudeTimer/sub/data.json'], equals('{"a":1}'));
      expect(dav.dirs.contains('/dav/EtudeTimer'), isTrue);
      expect(dav.dirs.contains('/dav/EtudeTimer/sub'), isTrue);
      final back = await c.read();
      expect(back!.text, equals('{"a":1}'));
      expect(back.etag, isNotNull);
      await dav.stop();
    });

    test('mise à jour avec ETag ; ETag périmé = conflit', () async {
      final c = WebDavClient(cfg);
      await c.write('v1');
      final f1 = await c.read();
      await c.write('v2', basedOn: f1);
      await expectLater(c.write('v3', basedOn: f1), throwsA(isA<RemotePreconditionFailed>()));
      expect((await c.read())!.text, equals('v2'));
      await dav.stop();
    });

    test('création alors que le fichier existe déjà = conflit (jamais d\'écrasement silencieux)', () async {
      final c = WebDavClient(cfg);
      await c.write('v1');
      await expectLater(c.write('autre'), throwsA(isA<RemotePreconditionFailed>()));
      await dav.stop();
    });

    test('accents et caractères spéciaux (UTF-8) conservés', () async {
      final c = WebDavClient(cfg);
      await c.write('{"n":"Étude — chimie organique 📚"}');
      expect((await c.read())!.text, equals('{"n":"Étude — chimie organique 📚"}'));
      await dav.stop();
    });

    test('mauvais mot de passe : message clair', () async {
      cfg.password = 'mauvais';
      await expectLater(WebDavClient(cfg).read(), throwsA(isA<SyncException>()));
      try {
        await WebDavClient(cfg).read();
      } on SyncException catch (e) {
        expect(e.message, contains('Accès refusé'));
      }
      await dav.stop();
    });

    test('test de connexion : OK, URL erronée, mauvais mot de passe', () async {
      await WebDavClient(cfg).testConnection();
      final bad = WebdavConfig(enabled: true, url: 'http://127.0.0.1:${dav.port}/nope', username: 'me', password: 'pw');
      await expectLater(WebDavClient(bad).testConnection(), throwsA(isA<SyncException>()));
      cfg.password = 'x';
      await expectLater(WebDavClient(cfg).testConnection(), throwsA(isA<SyncException>()));
      await dav.stop();
    });

    test('serveur injoignable : erreur claire', () async {
      final port = dav.port;
      await dav.stop();
      final dead = WebdavConfig(enabled: true, url: 'http://127.0.0.1:$port/dav', username: 'me', password: 'pw');
      await expectLater(WebDavClient(dead, timeout: const Duration(seconds: 3)).read(), throwsA(isA<SyncException>()));
    });

    test('URL invalide ou vide', () async {
      await expectLater(WebDavClient(WebdavConfig(url: '')).read(), throwsA(isA<SyncException>()));
      await expectLater(WebDavClient(WebdavConfig(url: 'pas une url')).read(), throwsA(isA<SyncException>()));
      await dav.stop();
    });

    test('chemins avec espaces et accents correctement encodés', () async {
      cfg.remotePath = '/Études Timer/données.json';
      final c = WebDavClient(cfg);
      dav.dirs.add('/dav/Études Timer');
      await c.write('ok');
      expect(dav.files.keys.single, equals('/dav/Études Timer/données.json'));
      await dav.stop();
    });
  });
}
