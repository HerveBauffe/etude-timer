import 'dart:io';

import 'package:etude_timer/core/single_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la 2ᵉ instance prévient la 1ʳᵉ et doit quitter', () async {
    final key = 'test-${DateTime.now().microsecondsSinceEpoch}';
    var shown = 0;
    final first = await SingleInstance.acquire(key, onShowRequested: () => shown++);
    expect(first, isNotNull);
    final second = await SingleInstance.acquire(key, onShowRequested: () {});
    expect(second, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(shown, equals(1));
    await first!.release();
    // une fois libéré, une nouvelle instance peut démarrer
    final third = await SingleInstance.acquire(key, onShowRequested: () {});
    expect(third, isNotNull);
    await third!.release();
  });

  test('port occupé par un autre programme : on démarre quand même', () async {
    final key = 'other-${DateTime.now().microsecondsSinceEpoch}';
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, SingleInstance.portFor(key));
    squatter.listen((c) => c.destroy());
    final inst = await SingleInstance.acquire(key, onShowRequested: () {});
    expect(inst, isNotNull);
    await inst!.release();
    await squatter.close();
  });

  test('le port dépend de la clé et reste dans la plage prévue', () {
    final p = SingleInstance.portFor('/home/x/.config/etude-timer');
    expect(p, greaterThanOrEqualTo(40000));
    expect(p, lessThan(60000));
    expect(SingleInstance.portFor('a'), isNot(equals(SingleInstance.portFor('b'))));
  });
}
