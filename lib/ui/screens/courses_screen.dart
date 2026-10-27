import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/models.dart';
import '../controller.dart';
import '../layout.dart';
import '../widgets/dialogs.dart';

/// Onglet « Cours » : créer, renommer, déplacer, archiver et supprimer dossiers, UE et cours,
/// et choisir le quadrimestre de chaque cours. Respecte le filtre Q1 / Q2 / Q1+Q2 de la barre latérale.
class CoursesScreen extends StatefulWidget {
  final AppController c;
  const CoursesScreen({super.key, required this.c});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final Set<String> _collapsed = {};
  bool _archivesOpen = false;

  AppController get c => widget.c;
  AppData get d => c.store.data;

  int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  List<Folder> _subFolders(String? parent) =>
      d.folders.where((f) => f.parentId == parent && folderVisible(d, f, c.quadri)).toList()
        ..sort((a, b) => _byName(a.name, b.name));

  List<UE> _uesIn(String? folderId) =>
      d.ues.where((u) => u.folderId == folderId && !u.archived && ueVisible(d, u, c.quadri)).toList()
        ..sort((a, b) => _byName(a.name, b.name));

  List<Course> _coursesOf(String ueId) =>
      d.courses.where((x) => x.ueId == ueId && c.quadri.matches(x.quadri)).toList()..sort((a, b) => _byName(a.name, b.name));

  bool _toggle(String id) => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);

  bool _blockedByTimer(Iterable<String> courseIds) {
    final active = c.busy ? c.activeCourseId : null;
    if (active != null && courseIds.contains(active)) {
      c.showMessage("Termine d'abord la session en cours sur ce cours.");
      return true;
    }
    return false;
  }

  Set<String> _courseIdsOfUE(String ueId) => d.courses.where((x) => x.ueId == ueId).map((x) => x.id).toSet();

  Set<String> _descendantFolders(String id) {
    final out = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in d.folders) {
        if (f.parentId != null && out.contains(f.parentId) && out.add(f.id)) grew = true;
      }
    }
    return out;
  }

  String _folderPath(Folder f) {
    final parts = <String>[f.name];
    var cur = f;
    var guard = 0;
    while (cur.parentId != null && guard++ < 50) {
      final p = d.folders.where((x) => x.id == cur.parentId).firstOrNull;
      if (p == null) break;
      parts.insert(0, p.name);
      cur = p;
    }
    return parts.join(' › ');
  }

  String _uePath(UE u) {
    final f = d.folders.where((x) => x.id == u.folderId).firstOrNull;
    return f == null ? u.name : '${_folderPath(f)} › ${u.name}';
  }

  // ───────────── Actions ─────────────

  Future<void> _addFolder(String? parentId) async {
    final name = await promptText(
      context,
      title: parentId == null ? 'Nouveau dossier' : 'Nouveau sous-dossier',
      message: 'Ex. « 2026-2027 ». Les quadrimestres se choisissent cours par cours.',
      confirmLabel: 'Créer',
    );
    if (name == null || name.isEmpty) return;
    c.store.addFolder(name, parentId: parentId);
    if (parentId != null) setState(() => _collapsed.remove(parentId));
  }

  Future<void> _addUE(String? folderId) async {
    final name = await promptText(context, title: 'Nouvelle UE', label: "Nom de l'UE", confirmLabel: 'Créer');
    if (name == null || name.isEmpty) return;
    c.store.addUE(name, folderId: folderId);
    if (folderId != null) setState(() => _collapsed.remove(folderId));
  }

  Future<void> _addCourse(UE ue) async {
    final r = await promptCourse(
      context,
      title: 'Nouveau cours dans « ${ue.name} »',
      initialQuadri: c.quadri.defaultQuadri,
    );
    if (r == null) return;
    c.store.addCourse(r.name, ue.id, quadri: r.quadri);
    setState(() => _collapsed.remove(ue.id));
    if (!c.quadri.matches(r.quadri)) {
      c.showMessage('Cours créé en Q${r.quadri} : il est masqué par le filtre ${c.quadri.label} (change-le dans la barre latérale).');
    }
  }

  Future<void> _editCourse(Course x) async {
    final r = await promptCourse(
      context,
      title: 'Modifier le cours',
      initialName: x.name,
      initialQuadri: x.quadri,
      confirmLabel: 'Enregistrer',
    );
    if (r == null) return;
    c.store.updateCourse(x.id, name: r.name, quadri: r.quadri);
    if (!c.quadri.matches(r.quadri)) {
      c.showMessage('« ${r.name} » est passé en Q${r.quadri} : masqué par le filtre ${c.quadri.label}.');
    }
  }

  Future<void> _rename(String title, String current, void Function(String) apply) async {
    final name = await promptText(context, title: title, initial: current, confirmLabel: 'Renommer');
    if (name == null || name.isEmpty) return;
    apply(name);
  }

  Future<void> _deleteFolder(Folder f) async {
    final doomed = _descendantFolders(f.id);
    final courseIds = d.ues
        .where((u) => u.folderId != null && doomed.contains(u.folderId))
        .expand((u) => _courseIdsOfUE(u.id))
        .toSet();
    if (_blockedByTimer(courseIds)) return;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${f.name} » ?',
      message: "Le dossier et ses sous-dossiers sont supprimés. Les UE qu'ils contiennent sont conservées : elles remontent à la racine.",
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteFolder(f.id);
  }

  Future<void> _deleteUE(UE u) async {
    if (_blockedByTimer(_courseIdsOfUE(u.id))) return;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${u.name} » ?',
      message: "L'UE, ses cours (Q1 et Q2), leur planning et tout l'historique d'étude associé seront supprimés définitivement. "
          "Pour garder l'historique, archive-la plutôt.",
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteUE(u.id);
  }

  Future<void> _deleteCourse(Course x) async {
    if (_blockedByTimer({x.id})) return;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${x.name} » ?',
      message: "Le cours, son planning (révisions, examen) et son historique d'étude seront supprimés définitivement.",
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteCourse(x.id);
  }

  Future<void> _moveUE(UE u) async {
    final folders = [for (final f in d.folders) (id: f.id, label: _folderPath(f))]..sort((a, b) => _byName(a.label, b.label));
    final picked = await pickFolder(context, title: 'Déplacer « ${u.name} » dans…', folders: folders, current: u.folderId);
    if (picked == null) return;
    c.store.moveUE(u.id, picked.isEmpty ? null : picked);
  }

  Future<void> _moveCourse(Course x) async {
    final ues = [
      for (final u in d.ues)
        if (u.id != x.ueId) (id: u.id, label: _uePath(u)),
    ]..sort((a, b) => _byName(a.label, b.label));
    if (ues.isEmpty) {
      c.showMessage("Il n'y a pas d'autre UE où déplacer ce cours.");
      return;
    }
    final picked = await pickFolder(context, title: 'Déplacer « ${x.name} » vers l\'UE…', folders: ues, rootLabel: null);
    if (picked == null || picked.isEmpty) return;
    c.store.moveCourse(x.id, picked);
  }

  void _archive(UE u, bool archived) {
    if (archived && _blockedByTimer(_courseIdsOfUE(u.id))) return;
    c.store.archiveUE(u.id, archived);
    if (archived) c.showMessage('« ${u.name} » archivée : son historique est conservé.');
  }

  void _study(Course x) {
    if (c.busy && c.activeCourseId != x.id) {
      c.showMessage("Termine d'abord la session en cours.");
      return;
    }
    c.selectCourse(x.id);
  }

  // ───────────── Rendu ─────────────

  Widget _menu(List<(String, String, IconData)> items, void Function(String) onSelected) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (id, label, icon) in items)
          PopupMenuItem<String>(value: id, child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)])),
      ],
    );
  }

  Widget _badge(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _tile({
    required int depth,
    required IconData icon,
    required String title,
    required Widget menu,
    VoidCallback? onTap,
    Widget? expandIcon,
    String? badge,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: 6.0 + depth * 22, right: 4, top: 1, bottom: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              if (expandIcon != null) expandIcon else const SizedBox(width: 4),
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (badge != null && badge.isNotEmpty) _badge(badge),
              menu,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _chevron(String id) => Icon(_collapsed.contains(id) ? Icons.chevron_right : Icons.expand_more, size: 18);

  List<Widget> _courseTiles(UE u, int depth) => [
        for (final x in _coursesOf(u.id))
          _tile(
            depth: depth,
            icon: Icons.menu_book_outlined,
            title: x.name,
            badge: 'Q${x.quadri}',
            onTap: () => _study(x),
            menu: _menu(const [
              ('study', 'Étudier ce cours', Icons.play_arrow_outlined),
              ('edit', 'Modifier (nom, quadrimestre)…', Icons.edit_outlined),
              ('move', 'Déplacer vers une autre UE…', Icons.drive_file_move_outline),
              ('delete', 'Supprimer', Icons.delete_outline),
            ], (a) {
              switch (a) {
                case 'study':
                  _study(x);
                case 'edit':
                  _editCourse(x);
                case 'move':
                  _moveCourse(x);
                case 'delete':
                  _deleteCourse(x);
              }
            }),
          ),
      ];

  List<Widget> _ueTiles(UE u, int depth) => [
        _tile(
          depth: depth,
          icon: Icons.school_outlined,
          title: u.name,
          badge: quadriBadge(ueQuadris(d, u.id)),
          expandIcon: _chevron(u.id),
          onTap: () => setState(() => _toggle(u.id)),
          menu: _menu(const [
            ('course', 'Nouveau cours…', Icons.add),
            ('rename', 'Renommer', Icons.edit_outlined),
            ('move', 'Déplacer dans un dossier…', Icons.drive_file_move_outline),
            ('archive', 'Archiver', Icons.archive_outlined),
            ('delete', 'Supprimer', Icons.delete_outline),
          ], (a) {
            switch (a) {
              case 'course':
                _addCourse(u);
              case 'rename':
                _rename("Renommer l'UE", u.name, (n) => c.store.renameUE(u.id, n));
              case 'move':
                _moveUE(u);
              case 'archive':
                _archive(u, true);
              case 'delete':
                _deleteUE(u);
            }
          }),
        ),
        if (!_collapsed.contains(u.id)) ..._courseTiles(u, depth + 1),
      ];

  List<Widget> _folderTiles(Folder f, int depth) => [
        _tile(
          depth: depth,
          icon: _collapsed.contains(f.id) ? Icons.folder_outlined : Icons.folder_open_outlined,
          title: f.name,
          expandIcon: _chevron(f.id),
          onTap: () => setState(() => _toggle(f.id)),
          menu: _menu(const [
            ('sub', 'Nouveau sous-dossier…', Icons.create_new_folder_outlined),
            ('ue', 'Nouvelle UE…', Icons.add),
            ('rename', 'Renommer', Icons.edit_outlined),
            ('delete', 'Supprimer', Icons.delete_outline),
          ], (a) {
            switch (a) {
              case 'sub':
                _addFolder(f.id);
              case 'ue':
                _addUE(f.id);
              case 'rename':
                _rename('Renommer le dossier', f.name, (n) => c.store.renameFolder(f.id, n));
              case 'delete':
                _deleteFolder(f);
            }
          }),
        ),
        if (!_collapsed.contains(f.id)) ...[
          for (final sub in _subFolders(f.id)) ..._folderTiles(sub, depth + 1),
          for (final u in _uesIn(f.id)) ..._ueTiles(u, depth + 1),
        ],
      ];

  List<Widget> _archiveTiles() {
    final archived = d.ues.where((u) => u.archived && ueVisible(d, u, c.quadri)).toList()..sort((a, b) => _byName(a.name, b.name));
    return [
      for (final u in archived) ...[
        _tile(
          depth: 1,
          icon: Icons.inventory_2_outlined,
          title: u.name,
          badge: quadriBadge(ueQuadris(d, u.id)),
          expandIcon: _chevron(u.id),
          onTap: () => setState(() => _toggle(u.id)),
          menu: _menu(const [('unarchive', 'Désarchiver', Icons.unarchive_outlined), ('delete', 'Supprimer', Icons.delete_outline)], (a) {
            if (a == 'unarchive') _archive(u, false);
            if (a == 'delete') _deleteUE(u);
          }),
        ),
        if (!_collapsed.contains(u.id))
          for (final x in _coursesOf(u.id))
            _tile(
              depth: 2,
              icon: Icons.menu_book_outlined,
              title: x.name,
              badge: 'Q${x.quadri}',
              onTap: () => _study(x),
              menu: const SizedBox(width: 8),
            ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rootFolders = _subFolders(null);
    final rootUEs = _uesIn(null);
    final archivedCount = d.ues.where((u) => u.archived && ueVisible(d, u, c.quadri)).length;
    final hiddenCourses = d.courses.length - d.courses.where((x) => c.quadri.matches(x.quadri)).length;
    final empty = rootFolders.isEmpty && rootUEs.isEmpty && archivedCount == 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: EdgeInsets.fromLTRB(isCompactWidth(context) ? 12 : 24, 8, isCompactWidth(context) ? 12 : 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(builder: (context) {
                final compact = isCompactWidth(context);
                final intro = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!compact) Text('Cours', style: text.headlineSmall),
                  if (!compact) const SizedBox(height: 4),
                  Text(
                    compact
                        ? 'Affichage : ${c.quadri.label}. Un cours = un seul quadrimestre ; une UE peut en couvrir deux.'
                        : 'Affichage : ${c.quadri.label} (filtre dans la barre latérale). Chaque cours appartient à un seul quadrimestre ; une UE peut en couvrir deux.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]);
                final addFolder = FilledButton.tonalIcon(
                  onPressed: () => _addFolder(null),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Dossier'),
                );
                final addUe = FilledButton.icon(onPressed: () => _addUE(null), icon: const Icon(Icons.add, size: 18), label: const Text('UE'));
                if (compact) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    intro,
                    const SizedBox(height: 8),
                    Row(children: [Expanded(child: addFolder), const SizedBox(width: 8), Expanded(child: addUe)]),
                  ]);
                }
                return Row(children: [
                  Expanded(child: intro),
                  const SizedBox(width: 12),
                  addFolder,
                  const SizedBox(width: 8),
                  addUe,
                ]);
              }),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
                  child: empty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            hiddenCourses > 0
                                ? 'Aucun cours en ${c.quadri.label}. $hiddenCourses cours d\'un autre quadrimestre sont masqués par le filtre.'
                                : 'Commence par créer un dossier (ex. « 2026-2027 »), puis une UE, puis des cours en choisissant leur quadrimestre.',
                            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          children: [
                            for (final f in rootFolders) ..._folderTiles(f, 0),
                            for (final u in rootUEs) ..._ueTiles(u, 0),
                            if (archivedCount > 0) ...[
                              const Padding(padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16), child: Divider()),
                              _tile(
                                depth: 0,
                                icon: Icons.inventory_2_outlined,
                                title: 'Archives ($archivedCount)',
                                expandIcon: Icon(_archivesOpen ? Icons.expand_more : Icons.chevron_right, size: 18),
                                onTap: () => setState(() => _archivesOpen = !_archivesOpen),
                                menu: const SizedBox(width: 8),
                              ),
                              if (_archivesOpen) ..._archiveTiles(),
                            ],
                            if (hiddenCourses > 0)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                                child: Text(
                                  '$hiddenCourses cours d\'un autre quadrimestre masqué${hiddenCourses > 1 ? 's' : ''} par le filtre ${c.quadri.label}.',
                                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
