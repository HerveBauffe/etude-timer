import 'dart:async';

import 'package:flutter/material.dart';

import '../core/quadri.dart';
import 'controller.dart';
import 'fr_localizations.dart';
import 'layout.dart';
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

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  StreamSubscription<String>? _sub;
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey<ScaffoldMessengerState>();

  AppController get c => widget.controller;

  static const _titles = {
    AppView.timer: 'Minuteur',
    AppView.courses: 'Cours',
    AppView.planning: 'Planning',
    AppView.stats: 'Statistiques',
    AppView.settings: 'Réglages',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = c.messages.listen((m) {
      final state = _messenger.currentState;
      if (state == null) return;
      state.hideCurrentSnackBar();
      state.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 5)));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isMobilePlatform) return; // sur bureau, perdre le focus ne veut pas dire « en arrière-plan »
    if (state == AppLifecycleState.resumed) c.onResumed();
    if (state == AppLifecycleState.paused) c.onBackgrounded();
  }

  /// Bouton « retour » du système (Android) : revient au minuteur ; ne quitte jamais en pleine séance.
  void _onBack() {
    if (c.view != AppView.timer) {
      c.setView(AppView.timer);
    } else if (c.busy) {
      c.showMessage("Une séance est en cours : utilise le bouton Accueil pour laisser l'appli en arrière-plan.");
    }
  }

  Widget _content(ColorScheme scheme, {required bool sidebar}) {
    return switch (c.view) {
      AppView.timer => sidebar
          ? Row(
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
            )
          : TimerScreen(c: c, sidebarVisible: false),
      AppView.courses => CoursesScreen(c: c),
      AppView.planning => PlanningScreen(c: c),
      AppView.stats => StatsScreen(c: c),
      AppView.settings => SettingsScreen(c: c),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < compactBreakpoint;
        final wide = !isMobilePlatform || box.maxWidth >= wideBreakpoint;
        return ScaffoldMessenger(
          key: _messenger,
          child: Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final Widget scaffold;
              if (compact) {
                scaffold = Scaffold(
                  appBar: AppBar(
                    title: Text(_titles[c.view]!),
                    actions: [
                      _QuadriToggle(c: c, horizontal: true),
                      _SyncButton(c: c),
                      const SizedBox(width: 4),
                    ],
                  ),
                  body: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                    child: _content(scheme, sidebar: false),
                  ),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: AppView.values.indexOf(c.view),
                    onDestinationSelected: (i) => c.setView(AppView.values[i]),
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: [
                      for (final (_, icon, selectedIcon, label) in _SideNav.items)
                        NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: label),
                    ],
                  ),
                );
              } else {
                scaffold = Scaffold(
                  body: SafeArea(
                    child: Row(
                      children: [
                        _SideNav(c: c),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                            child: _content(scheme, sidebar: wide),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return PopScope(
                canPop: c.view == AppView.timer && !c.busy,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _onBack();
                },
                child: scaffold,
              );
            },
          ),
        );
      },
    );
  }
}

/// Barre latérale gauche : navigation, sélecteur de quadrimestre, bouton de synchronisation.
/// Faite à la main (et non avec NavigationRail) pour rester utilisable sur une fenêtre peu haute :
/// la navigation défile, le sélecteur et la synchro restent collés en bas.
class _SideNav extends StatelessWidget {
  final AppController c;
  const _SideNav({required this.c});

  static const items = [
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
                for (final (view, icon, selectedIcon, label) in items)
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

  /// En ligne (barre du haut sur téléphone) ou en colonne (barre latérale).
  final bool horizontal;
  const _QuadriToggle({required this.c, this.horizontal = false});

  static const _tips = {
    QuadriFilter.q1: 'Afficher les cours du 1er quadrimestre',
    QuadriFilter.q2: 'Afficher les cours du 2e quadrimestre',
    QuadriFilter.both: 'Afficher les cours des deux quadrimestres',
  };

  Widget _pill(BuildContext context, QuadriFilter f) {
    final scheme = Theme.of(context).colorScheme;
    final selected = c.quadri == f;
    return Tooltip(
      message: _tips[f]!,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => c.setQuadri(f),
            child: SizedBox(
              height: horizontal ? 32 : 30,
              width: horizontal ? (f == QuadriFilter.both ? 56 : 38) : null,
              child: Center(
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pills = [for (final f in QuadriFilter.values) _pill(context, f)];
    return Container(
      width: horizontal ? null : 68,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: horizontal
          ? Row(mainAxisSize: MainAxisSize.min, children: pills)
          : Column(mainAxisSize: MainAxisSize.min, children: pills),
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
