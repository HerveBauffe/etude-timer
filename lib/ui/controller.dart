import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/catalog.dart';
import '../core/data_store.dart';
import '../core/device_config.dart';
import '../core/flow.dart';
import '../core/models.dart';
import '../core/paths.dart';
import '../core/pomodoro.dart';
import '../core/quadri.dart';
import '../core/single_instance.dart';
import '../core/sync.dart';
import '../core/webdav_client.dart';
import '../platform/alerts.dart';
import '../platform/window_service.dart';

enum TimerMode { pomodoro, flow }

enum AppView { timer, courses, planning, stats, settings }

/// Chef d'orchestre : relie données, minuteurs, synchronisation, alertes et fenêtre.
/// L'interface n'écoute que ce contrôleur (ChangeNotifier) et le `tick` (≈ 2×/s).
class AppController extends ChangeNotifier {
  final AppPaths paths;
  final DataStore store;
  final DeviceConfig device;
  final AlertService alerts;
  final WindowService window;
  SingleInstance? _instance;

  late final PomodoroEngine pomodoro;
  late final FlowEngine flow;
  late final SyncService sync;

  /// Incrémenté à chaque tick : seuls les widgets du minuteur l'écoutent.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  final StreamController<String> _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  Timer? _ticker;
  Timer? _syncTimer;
  bool _disposed = false;

  // État de l'interface
  AppView view = AppView.timer;
  TimerMode mode = TimerMode.pomodoro;
  String? selectedCourseId;
  String? statsCourseId; // null = tous les cours

  /// Filtre Q1 / Q2 / Q1+Q2 : restreint les cours affichés partout (liste, cours, planning, stats).
  late QuadriFilter quadri = QuadriFilter.parse(device.quadriFilter);

  /// Liste des cours du minuteur : développée par défaut, réductible.
  bool sidebarOpen = true;

  // État de la synchronisation
  bool syncing = false;
  String? syncMessage;
  bool syncFailed = false;

  AppController({
    required this.paths,
    required this.store,
    required this.device,
    required this.alerts,
    required this.window,
  }) {
    pomodoro = PomodoroEngine(
      settings: () => store.data.settings,
      onWorkLogged: _logPomodoroWork,
      onEvent: _onPomodoroEvent,
    );
    flow = FlowEngine(
      settings: () => store.data.settings,
      onWorkLogged: _logFlowWork,
      onBreakEnded: _onFlowBreakEnded,
    );
    sync = SyncService(store, device, () => WebDavClient(device.webdav));
    store.addListener(_onStoreChanged);
    window.onCloseRequested = shutdown;
  }

  // ───────────── Démarrage / arrêt ─────────────

  void attachInstance(SingleInstance? i) => _instance = i;

  /// À appeler une fois l'UI affichée : première synchro + synchro périodique.
  void start() {
    _restartSyncTimer();
    if (device.webdav.isUsable) unawaited(syncNow(silent: true));
  }

  bool _shuttingDown = false;

  /// Fermeture : enregistre le travail en cours, synchronise une dernière fois (5 s max) et libère
  /// le verrou. Idempotente. La fenêtre est détruite ensuite par [WindowService].
  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    try {
      if (pomodoro.isWork) pomodoro.endSession();
      flow.flushOnClose();
    } catch (_) {
      // on continue : la fermeture ne doit jamais rester bloquée
    }
    _ticker?.cancel();
    _ticker = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    if (device.webdav.isUsable) {
      try {
        // Une synchro déjà en cours ne contient pas la séance qu'on vient d'enregistrer : on
        // l'attend (brièvement) pour relancer une vraie synchro juste après.
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (sync.isRunning && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await sync.sync().timeout(const Duration(seconds: 5));
      } catch (_) {
        // hors ligne ou trop lent : les données restent enregistrées localement
      }
    }
    try {
      await _instance?.release();
    } catch (_) {}
    _instance = null;
  }

  /// L'appli revient au premier plan (mobile : écran rallumé, retour d'une autre appli).
  /// Les minuteurs sont basés sur l'horloge : on les remet à l'heure d'un coup, puis on synchronise
  /// si la dernière synchro est ancienne.
  void onResumed() {
    if (_shuttingDown) return;
    pomodoro.tick();
    flow.tick();
    tick.value++;
    _refreshTicker();
    _notifySafe();
    if (device.webdav.isUsable && !syncing) {
      final last = DateTime.tryParse(device.lastSyncedAt ?? '');
      final every = device.webdav.autoSyncMinutes;
      final stale = last == null || DateTime.now().difference(last).inMinutes >= (every > 0 ? every : 15);
      if (stale) unawaited(syncNow(silent: true));
    }
  }

  /// L'appli passe en arrière-plan (mobile) : les données sont déjà enregistrées à chaque
  /// modification ; on tente seulement d'envoyer ce qui est nouveau.
  void onBackgrounded() {
    if (_shuttingDown || !device.webdav.isUsable || syncing) return;
    unawaited(syncNow(silent: true));
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _syncTimer?.cancel();
    store.removeListener(_onStoreChanged);
    _messages.close();
    tick.dispose();
    super.dispose();
  }

  void _notifySafe() {
    if (!_disposed) notifyListeners();
  }

  void _onStoreChanged() {
    _dropHiddenSelections();
    _notifySafe();
  }

  /// Cours de l'ensemble affiché par le filtre de quadrimestre.
  Set<String> get visibleIds => visibleCourseIds(store.data, quadri);

  bool isCourseVisible(String? id) => id != null && visibleIds.contains(id);

  /// Désélectionne un cours supprimé ou masqué par le filtre (sauf pendant une session en cours).
  void _dropHiddenSelections() {
    final vis = visibleIds;
    if (selectedCourseId != null && !busy && !vis.contains(selectedCourseId)) selectedCourseId = null;
    if (statsCourseId != null && !vis.contains(statsCourseId)) statsCourseId = null;
  }

  void setQuadri(QuadriFilter f) {
    if (f == quadri) return;
    quadri = f;
    device.quadriFilter = f.name;
    device.save();
    _dropHiddenSelections();
    _notifySafe();
  }

  void toggleSidebar() {
    sidebarOpen = !sidebarOpen;
    _notifySafe();
  }

  // ───────────── Navigation / sélection ─────────────

  void setView(AppView v) {
    view = v;
    _notifySafe();
  }

  void selectCourse(String? id) {
    if (busy) return; // pas de changement de cours pendant une session
    selectedCourseId = id;
    view = AppView.timer;
    _notifySafe();
  }

  void setMode(TimerMode m) {
    if (busy) return;
    mode = m;
    _notifySafe();
  }

  void setStatsCourse(String? id) {
    statsCourseId = id;
    _notifySafe();
  }

  /// Une session (Pomodoro ou Flow) est en cours : on ne change ni de cours ni de mode.
  bool get busy => pomodoro.inSession || flow.isBusy;

  /// Cours affiché : celui de la session en cours, sinon celui sélectionné.
  String? get activeCourseId {
    if (pomodoro.inSession && mode == TimerMode.pomodoro) return pomodoro.courseId;
    if (flow.isBusy && mode == TimerMode.flow) return flow.courseId;
    return selectedCourseId;
  }

  String courseLabel(String? courseId) {
    final c = store.courseById(courseId);
    if (c == null) return '';
    final ue = store.ueById(c.ueId);
    return ue == null ? c.name : '${ue.name} — ${c.name}';
  }

  // ───────────── Minuteur ─────────────

  void _refreshTicker() {
    final need = (pomodoro.isRunning && !pomodoro.paused) ||
        flow.phase == FlowPhase.working ||
        flow.phase == FlowPhase.breakTime;
    if (need && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        pomodoro.tick();
        flow.tick();
        tick.value++;
        if (!((pomodoro.isRunning && !pomodoro.paused) ||
            flow.phase == FlowPhase.working ||
            flow.phase == FlowPhase.breakTime)) {
          _ticker?.cancel();
          _ticker = null;
          _notifySafe();
        }
      });
    } else if (!need) {
      _ticker?.cancel();
      _ticker = null;
    }
    tick.value++;
  }

  void startPomodoro() {
    final c = selectedCourseId;
    if (c == null) return;
    pomodoro.startWork(c);
    _refreshTicker();
    _notifySafe();
  }

  void togglePomodoroPause() {
    pomodoro.togglePause();
    _refreshTicker();
    _notifySafe();
  }

  void skipPomodoroPhase() {
    pomodoro.skip();
    _refreshTicker();
    _notifySafe();
  }

  /// Termine la session d'étude. Retourne le cours (pour proposer la note de fin de session).
  String? endPomodoroSession() {
    final c = pomodoro.endSession() ?? selectedCourseId;
    _refreshTicker();
    _notifySafe();
    return c;
  }

  void newPomodoroCycle() {
    pomodoro.resetToIdle();
    _notifySafe();
  }

  void startFlow() {
    final c = selectedCourseId;
    if (c == null) return;
    flow.start(c);
    _refreshTicker();
    _notifySafe();
  }

  void stopFlow() {
    flow.stop();
    _refreshTicker();
    _notifySafe();
  }

  void confirmFlowReview({required bool withBreak, required String note}) {
    flow.confirmReview(withBreak: withBreak, note: note);
    _refreshTicker();
    _notifySafe();
  }

  void stopFlowBreak() {
    flow.stopBreak();
    _refreshTicker();
    _notifySafe();
  }

  void _logPomodoroWork(WorkLog l) {
    store.addSession(courseId: l.courseId, mode: l.mode, start: l.start, end: l.end, seconds: l.seconds);
  }

  void _logFlowWork(WorkLog l, String note) {
    if (l.seconds > 0) {
      store.addSession(courseId: l.courseId, mode: l.mode, start: l.start, end: l.end, seconds: l.seconds, note: note);
    } else if (note.trim().isNotEmpty) {
      addNote(l.courseId, note);
    }
  }

  void _onPomodoroEvent(PomoEvent e, String? courseId) {
    final label = courseLabel(courseId);
    final w = store.data.settings.workMin;
    switch (e) {
      case PomoEvent.workTargetReached:
        _alert('$w min atteintes', label.isEmpty ? 'Continue ou passe à la pause quand tu veux.' : '$label — continue ou passe à la pause quand tu veux.');
      case PomoEvent.shortBreakEnded:
        _alert('Pause terminée', label);
      case PomoEvent.longBreakEnded:
        _alert('Pause longue terminée', label);
    }
    _refreshTicker();
    _notifySafe();
  }

  void _onFlowBreakEnded(String? courseId) {
    _alert('Pause terminée', courseLabel(courseId));
    _refreshTicker();
    _notifySafe();
  }

  void _alert(String title, String body) {
    unawaited(alerts.playSound());
    unawaited(alerts.notify(title, body));
    unawaited(window.bringToFront());
    if (!_messages.isClosed) _messages.add(body.isEmpty ? title : '$title — $body');
  }

  // ───────────── Données : raccourcis ─────────────

  void addNote(String courseId, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    store.addSession(courseId: courseId, kind: SessionKind.note, start: now, end: now, seconds: 0, note: t);
  }

  void showMessage(String text) {
    if (!_messages.isClosed) _messages.add(text);
  }

  // ───────────── Réglages & synchronisation ─────────────

  void updateWebdav(WebdavConfig cfg) {
    device.webdav = cfg;
    device.save();
    _restartSyncTimer();
    _notifySafe();
  }

  void _restartSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
    final w = device.webdav;
    if (w.isUsable && w.autoSyncMinutes > 0) {
      _syncTimer = Timer.periodic(Duration(minutes: w.autoSyncMinutes), (_) => unawaited(syncNow(silent: true)));
    }
  }

  /// Teste URL + identifiants sans rien envoyer. Retourne null si OK, sinon le message d'erreur.
  Future<String?> testWebdav(WebdavConfig cfg) async {
    try {
      await WebDavClient(cfg).testConnection();
      return null;
    } on SyncException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur : $e';
    }
  }

  Future<void> syncNow({bool silent = false}) async {
    if (syncing) return;
    if (!device.webdav.isUsable) {
      if (!silent) showMessage('Configure d\'abord le serveur WebDAV dans les réglages.');
      return;
    }
    syncing = true;
    syncFailed = false;
    _notifySafe();
    try {
      final r = await sync.sync();
      syncMessage = r.message;
      if (!silent) showMessage(r.message);
    } on SyncException catch (e) {
      syncFailed = true;
      syncMessage = e.message;
      if (!silent) showMessage('Synchronisation impossible : ${e.message}');
    } catch (e) {
      syncFailed = true;
      syncMessage = 'Erreur inattendue : $e';
      if (!silent) showMessage(syncMessage!);
    } finally {
      syncing = false;
      _notifySafe();
    }
  }

  // ───────────── Emplacement des données ─────────────

  void chooseDataDir(String dir) {
    selectedCourseId = null;
    store.setDataDir(dir);
    _notifySafe();
  }

  void resetDataDir() {
    selectedCourseId = null;
    store.resetDataDir();
    _notifySafe();
  }
}
