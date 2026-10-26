import 'dart:async';

import 'package:flutter/material.dart';

import '../core/quadri.dart';
import 'controller.dart';
import 'fr_localizations.dart';
import 'screens/courses_screen.dart';
import 'screens/planning_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/timer_screen.dart';
import 'theme.dart';
import 'widgets/course_sidebar.dart';

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
                  _SideNav(c: c),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      child: switch (c.view) {
                        AppView.timer => Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CourseSidebar(c: c),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(24)),
                                  child: TimerScreen(c: c),
                                ),
                              ),
                            ],
                          ),
                        AppView.courses => CoursesScreen(c: c),
                        AppView.planning => PlanningScreen(c: c),
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

/// Barre latérale gauche : navigation, sélecteur de quadrimestre, bouton de synchronisation.
/// Faite à la main (et non avec NavigationRail) pour rester utilisable sur une fenêtre peu haute :
/// la navigation défile, le sélecteur et la synchro restent collés en bas.
class _SideNav extends StatelessWidget {
  final AppController c;
  const _SideNav({required this.c});

  static const _items = [
    (AppView.timer, Icons.timer_outlined, Icons.timer, 'Minuteur'),
    (AppView.courses, Icons.school_outlined, Icons.school, 'Cours'),
    (AppView.planning, Icons.calendar_month_outlined, Icons.calendar_month, 'Planning'),
    (AppView.stats, Icons.bar_chart_outlined, Icons.bar_chart, 'Stats'),
    (AppView.settings, Icons.settings_outlined, Icons.settings, 'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              children: [
                for (final (view, icon, selectedIcon, label) in _items)
                  _NavItem(
                    icon: c.view == view ? selectedIcon : icon,
                    label: label,
                    selected: c.view == view,
                    onTap: () => c.setView(view),
                  ),
              ],
            ),
          ),
          _QuadriToggle(c: c),
          const SizedBox(height: 4),
          _SyncButton(c: c),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 22, color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Q1 / Q2 / Q1+Q2 : n'affiche que les cours du quadrimestre choisi dans tous les écrans.
class _QuadriToggle extends StatelessWidget {
  final AppController c;
  const _QuadriToggle({required this.c});

  static const _tips = {
    QuadriFilter.q1: 'Afficher les cours du 1er quadrimestre',
    QuadriFilter.q2: 'Afficher les cours du 2e quadrimestre',
    QuadriFilter.both: 'Afficher les cours des deux quadrimestres',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final f in QuadriFilter.values)
          Tooltip(
            message: _tips[f]!,
            child: Semantics(
              button: true,
              selected: c.quadri == f,
              child: Material(
                color: c.quadri == f ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => c.setQuadri(f),
                  child: SizedBox(
                    height: 30,
                    child: Center(
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: c.quadri == f ? FontWeight.w700 : FontWeight.w500,
                          color: c.quadri == f ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
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
