import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/quadri.dart';
import '../controller.dart';

/// Contenu de la liste des cours (groupés par UE, archives repliables, état vide).
/// Utilisé dans le panneau latéral du minuteur et dans la feuille modale des petits écrans.
class CourseListBody extends StatefulWidget {
  final AppController c;

  /// Appelé après le choix d'un cours (ex. pour fermer la feuille modale).
  final VoidCallback? onSelected;
  const CourseListBody({super.key, required this.c, this.onSelected});

  @override
  State<CourseListBody> createState() => _CourseListBodyState();
}

class _CourseListBodyState extends State<CourseListBody> {
  bool _archivesOpen = false;

  AppController get c => widget.c;

  int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  /// UE (actives ou archivées) avec leurs cours visibles, triées par nom.
  List<(UE, List<Course>)> _groups({required bool archived}) {
    final d = c.store.data;
    final out = <(UE, List<Course>)>[];
    for (final u in d.ues.where((u) => u.archived == archived)) {
      final cs = d.courses.where((x) => x.ueId == u.id && c.quadri.matches(x.quadri)).toList()
        ..sort((a, b) => _byName(a.name, b.name));
      if (cs.isNotEmpty) out.add((u, cs));
    }
    out.sort((a, b) => _byName(a.$1.name, b.$1.name));
    return out;
  }

  Widget _courseTile(Course x, ColorScheme scheme) {
    final selected = c.selectedCourseId == x.id;
    final enabled = !c.busy || c.activeCourseId == x.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled
              ? () {
                  c.selectCourse(x.id);
                  widget.onSelected?.call();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(Icons.menu_book_outlined, size: 18, color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  x.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: !enabled
                        ? scheme.onSurface.withValues(alpha: 0.5)
                        : (selected ? scheme.onSecondaryContainer : scheme.onSurface),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (c.quadri == QuadriFilter.both)
                Text('Q${x.quadri}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _groupWidgets(List<(UE, List<Course>)> groups, ColorScheme scheme) {
    return [
      for (final (u, cs) in groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 4),
          child: Text(u.name, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        for (final x in cs) _courseTile(x, scheme),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _groups(archived: false);
    final archived = _groups(archived: true);
    return active.isEmpty && archived.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        'Aucun cours en ${c.quadri.label} pour le moment.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          c.setView(AppView.courses);
                          widget.onSelected?.call();
                        },
                        icon: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('Gérer les cours'),
                      ),
                    ]),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ..._groupWidgets(active, scheme),
                      if (archived.isNotEmpty) ...[
                        const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 2), child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => setState(() => _archivesOpen = !_archivesOpen),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Icon(_archivesOpen ? Icons.expand_more : Icons.chevron_right, size: 18),
                                const SizedBox(width: 6),
                                Icon(Icons.inventory_2_outlined, size: 18, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Text('Archives (${archived.fold<int>(0, (n, g) => n + g.$2.length)})'),
                              ]),
                            ),
                          ),
                        ),
                        if (_archivesOpen) ..._groupWidgets(archived, scheme),
                      ],
                    ],
                  );
  }
}

/// Liste des cours du quadrimestre choisi, à gauche du minuteur : réductible, développée par défaut.
/// (La gestion — création, renommage, déplacement, archivage — se fait dans l'onglet « Cours ».)
class CourseSidebar extends StatelessWidget {
  final AppController c;
  const CourseSidebar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24));

    if (!c.sidebarOpen) {
      return Container(
        width: 56,
        decoration: decoration,
        child: Column(children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Afficher la liste des cours',
            icon: const Icon(Icons.chevron_right),
            onPressed: c.toggleSidebar,
          ),
          const SizedBox(height: 4),
          RotatedBox(
            quarterTurns: 3,
            child: Text('Cours · ${c.quadri.label}', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
      );
    }

    return Container(
      width: 280,
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 4, 0),
            child: Row(children: [
              Expanded(child: Text('Cours · ${c.quadri.label}', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(tooltip: 'Réduire la liste', icon: const Icon(Icons.chevron_left), onPressed: c.toggleSidebar),
            ]),
          ),
          Expanded(child: CourseListBody(c: c)),
        ],
      ),
    );
  }
}

/// Feuille modale « Choisir un cours » pour les petits écrans (téléphone, tablette en portrait).
Future<void> showCoursePicker(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.75,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Cours · ${c.quadri.label}', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(child: CourseListBody(c: c, onSelected: () => Navigator.of(sheetContext).pop())),
          ],
        ),
      ),
    ),
  );
}
