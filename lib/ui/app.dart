import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'fr_localizations.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/timer_screen.dart';
import 'theme.dart';
import 'widgets/tree_panel.dart';

class EtudeTimerApp extends StatelessWidget {
  final AppController controller;
  const EtudeTimerApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.store.data.settings;
        return MaterialApp(
          title: 'Étude Timer',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s.palette, Brightness.light),
          darkTheme: buildTheme(s.palette, Brightness.dark),
          themeMode: themeModeFrom(s.themeMode),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [
            FrMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            FrCupertinoDelegate(),
          ],
          home: Shell(controller: controller),
        );
      },
    );
  }
}

/// Coque de l'application : rail de navigation à gauche, contenu à droite.
class Shell extends StatefulWidget {
  final AppController controller;
  const Shell({super.key, required this.controller});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  StreamSubscription<String>? _sub;
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey<ScaffoldMessengerState>();

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sub = c.messages.listen((m) {
      final state = _messenger.currentState;
      if (state == null) return;
      state.hideCurrentSnackBar();
      state.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 5)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static const _views = [AppView.timer, AppView.stats, AppView.settings];

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messenger,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _views.indexOf(c.view),
                    onDestinationSelected: (i) => c.setView(_views[i]),
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.timer_outlined),
                        selectedIcon: Icon(Icons.timer),
                        label: Text('Minuteur'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.bar_chart_outlined),
                        selectedIcon: Icon(Icons.bar_chart),
                        label: Text('Stats'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Réglages'),
                      ),
                    ],
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _SyncButton(c: c),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      child: switch (c.view) {
                        AppView.timer => Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TreePanel(controller: c),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(24)),
                                  child: TimerScreen(c: c),
                                ),
                              ),
                            ],
                          ),
                        AppView.stats => StatsScreen(c: c),
                        AppView.settings => SettingsScreen(c: c),
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final AppController c;
  const _SyncButton({required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usable = c.device.webdav.isUsable;
    final Widget icon = c.syncing
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Icon(
            c.syncFailed ? Icons.sync_problem : (usable ? Icons.sync : Icons.sync_disabled),
            color: c.syncFailed ? scheme.error : null,
          );
    return IconButton(
      tooltip: !usable
          ? 'Synchronisation désactivée (voir Réglages)'
          : (c.syncFailed ? 'Échec de la synchro : ${c.syncMessage ?? ''}' : 'Synchroniser maintenant'),
      onPressed: c.syncing ? null : () => c.syncNow(),
      icon: icon,
    );
  }
}
