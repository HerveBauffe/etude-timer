import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show DartPluginRegistrant, IsolateNameServer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/paths.dart';
import '../core/session.dart';

/// Android : notification persistante (service de premier plan) avec chronomètre natif et bouton
/// Pause/Reprendre, + alarme exacte de fin de phase qui réveille l'écran (notification plein écran)
/// ou s'affiche en bandeau si l'écran est allumé.
///
/// Le chronomètre de la notification est dessiné par le système : il avance même si l'appli est
/// en arrière-plan, écran éteint, ou si le processus Dart est gelé. L'alarme est une alarme
/// système : elle sonne même si l'appli a été tuée.

const _portName = 'be.etudetimer.session.toggle';
const _sessionNotifId = 1;
const _alarmNotifId = 2;
const _toggleAction = 'toggle';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

AndroidFlutterLocalNotificationsPlugin? get _android =>
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

// ───────────────────────── Notifications ─────────────────────────

AndroidNotificationDetails _persistentDetails(SessionPlan p) => AndroidNotificationDetails(
      'session',
      'Minuteur en cours',
      channelDescription: "Chrono de la séance d'étude en cours, avec le bouton Pause / Reprendre.",
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      silent: true,
      playSound: false,
      enableVibration: false,
      showWhen: p.ticking,
      when: p.ticking ? p.chronoMs : null,
      usesChronometer: p.ticking,
      chronometerCountDown: p.ticking && p.countDown,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.progress,
      actions: [
        if (p.canToggle)
          AndroidNotificationAction(
            _toggleAction,
            p.paused ? 'Reprendre' : 'Pause',
            showsUserInterface: false,
            cancelNotification: false, // sinon la notification du service disparaîtrait au clic
          ),
      ],
    );

AndroidNotificationDetails _alertDetails() => AndroidNotificationDetails(
      'alerts',
      'Fin de phase',
      channelDescription: 'Sonne à la fin d\'un bloc de travail ou d\'une pause ; réveille l\'écran s\'il est éteint.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 400]),
    );

/// Annule l'alarme seulement si elle est encore en attente : `cancel` retirerait aussi la
/// notification de fin de phase déjà affichée (par ex. quand le bloc passe en dépassement).
Future<void> _cancelPendingAlarm() async {
  final pending = await _plugin.pendingNotificationRequests();
  if (pending.any((n) => n.id == _alarmNotifId)) await _plugin.cancel(id: _alarmNotifId);
}

Future<void> _scheduleAlarm(SessionPlan p) async {
  final at = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, p.alarmAtMs!);
  if (!at.isAfter(tz.TZDateTime.now(tz.UTC))) {
    await _cancelPendingAlarm(); // déjà passée : l'événement dans l'appli s'en charge
    return;
  }
  final exact = await _android?.canScheduleExactNotifications() ?? false;
  await _plugin.zonedSchedule(
    id: _alarmNotifId,
    title: p.alarmTitle,
    body: p.alarmBody,
    scheduledDate: at,
    notificationDetails: NotificationDetails(android: _alertDetails()),
    // Sans l'autorisation d'alarme exacte, Android peut retarder l'alarme de quelques minutes.
    androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> _applyPlan(SessionPlan plan) async {
  final android = _android;
  if (android == null) return;
  if (!plan.active) {
    await android.stopForegroundService();
  } else {
    await android.startForegroundService(
      id: _sessionNotifId,
      title: plan.title,
      body: plan.body,
      notificationDetails: _persistentDetails(plan),
      foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeSpecialUse},
    );
  }
  if (plan.alarmAtMs != null) {
    await _scheduleAlarm(plan);
  } else {
    await _cancelPendingAlarm();
  }
}

// ───────────────────────── Bouton de la notification ─────────────────────────

/// Appelé par le plugin dans un isolat d'arrière-plan quand on touche « Pause » / « Reprendre »
/// (l'appli peut être au premier plan, en arrière-plan, ou n'avoir que son service en vie).
@pragma('vm:entry-point')
Future<void> sessionNotificationBackground(NotificationResponse response) async {
  if (response.actionId != _toggleAction) return;
  // Cas normal : l'appli tourne encore → on lui demande de basculer (elle met tout à jour).
  final port = IsolateNameServer.lookupPortByName(_portName);
  if (port != null) {
    port.send(_toggleAction);
    return;
  }
  // Sinon (appli retirée des récentes, seul le service survit) : on bascule la séance sauvegardée.
  try {
    DartPluginRegistrant.ensureInitialized();
    final support = await getApplicationSupportDirectory();
    final paths = AppPaths.at('${support.path}/${AppPaths.appDirName}');
    final store = SessionStore(paths.sessionFile);
    final snap = store.load();
    if (snap == null) return;
    final now = DateTime.now();
    final next = toggledSnapshot(snap, now);
    if (next == null) return;
    store.save(next);
    await _applyPlan(planSession(next, now));
  } catch (_) {
    // rien de plus à faire : le bouton n'a simplement pas agi
  }
}

// ───────────────────────── Backend ─────────────────────────

class AndroidSessionBackend implements SessionBackend, SessionPermissions {
  /// Demandé par le bouton Pause/Reprendre de la notification (appli en vie).
  final void Function() onToggleRequested;

  AndroidSessionBackend({required this.onToggleRequested});

  ReceivePort? _port;
  bool _askedPermission = false;

  /// Les notifications sont autorisées : le système se charge alors de l'alerte de fin de phase.
  @override
  bool notificationsEnabled = false;

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_timer')),
      onDidReceiveNotificationResponse: (_) {}, // toucher la notification ouvre simplement l'appli
      onDidReceiveBackgroundNotificationResponse: sessionNotificationBackground,
    );
    IsolateNameServer.removePortNameMapping(_portName);
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen((m) {
      if (m == _toggleAction) onToggleRequested();
    });
    _port = port;
    notificationsEnabled = await _android?.areNotificationsEnabled() ?? false;
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+) ; true si accordée.
  @override
  Future<bool> requestNotifications() async {
    notificationsEnabled = await _android?.requestNotificationsPermission() ?? false;
    return notificationsEnabled;
  }

  /// Ouvre l'écran système qui autorise les notifications plein écran (Android 14+),
  /// nécessaires pour réveiller l'écran à la fin d'une phase.
  @override
  Future<void> requestFullScreen() async {
    await _android?.requestFullScreenIntentPermission();
  }

  @override
  Future<void> refresh() async {
    notificationsEnabled = await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<void> apply(SessionPlan plan) async {
    // L'autorisation est demandée au premier démarrage d'une séance (contexte clair pour l'utilisateur).
    if (plan.active && !_askedPermission) {
      _askedPermission = true;
      if (!notificationsEnabled) await requestNotifications();
    }
    await _applyPlan(plan);
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping(_portName);
    _port?.close();
    _port = null;
  }
}
