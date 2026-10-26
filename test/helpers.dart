import 'dart:io';

import 'package:etude_timer/core/data_store.dart';
import 'package:etude_timer/core/device_config.dart';
import 'package:etude_timer/core/paths.dart';

/// Horloge de test contrôlable.
class FakeClock {
  DateTime t;
  FakeClock([DateTime? start]) : t = start ?? DateTime(2026, 10, 23, 10, 0);
  DateTime call() => t;
  void advance({int seconds = 0, int minutes = 0, int hours = 0, int days = 0}) {
    t = t.add(Duration(seconds: seconds, minutes: minutes, hours: hours, days: days));
  }
}

Directory tempDir([String prefix = 'etude']) => Directory.systemTemp.createTempSync('$prefix-');

class Device {
  final Directory dir;
  final AppPaths paths;
  final DataStore store;
  final DeviceConfig config;
  Device._(this.dir, this.paths, this.store, this.config);

  factory Device.create(FakeClock clock) {
    final dir = tempDir('dev');
    final paths = AppPaths.at(dir.path);
    final store = DataStore(paths, now: clock.call)..load();
    final config = DeviceConfig(paths)..load();
    return Device._(dir, paths, store, config);
  }
}
