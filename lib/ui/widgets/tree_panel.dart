import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../controller.dart';
import 'dialogs.dart';

/// Panneau de gauche : Dossiers (année / quadrimestre…) › UE › Cours, plus les UE archivées.
class TreePanel extends StatefulWidget {
  final AppController controller;
  const TreePanel({super.key, required this.controller});

  @override
  State<TreePanel> createState() => _TreePanelState();
}

class _TreePanelState extends State<TreePanel> {
  final Set<String> _collapsed = {};
  bool _archivesOpen = false;

  AppController get c => widget.controller;

  int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  List<Folder> _subFolders(String? parent) =>
      c.store.data.folders.where((f) => f.parentId == parent).toList()..sort((a, b) => _byName(a.name, b.name));

  List<UE> _uesIn(String? folderId, {required bool archived}) =>
      c.store.data.ues.where((u) => u.folderId == folderId && u.archived == archived).toList()
        ..sort((a, b) => _byName(a.name, b.name));

  List<Course> _coursesOf(String ueId) =>
      c.store.data.courses.where((x) => x.ueId == ueId).toList()..sort((a, b) => _byName(a.name, b.name));

  bool _toggle(String id) => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);

  /// Refuse de supprimer/archiver ce qui est en cours d'utilisation par le minuteur.
  bool _blockedByTimer(Iterable<String> courseIds) {
    final active = c.busy ? c.activeCourseId : null;
    if (active != null && courseIds.contains(active)) {
      c.showMessage("Termine d'abord la session en cours sur ce cours.");
      return true;
    }
    return false;
  }

  Set<String> _courseIdsOfUE(String ueId) => c.store.data.courses.where((x) => x.ueId == ueId).map((x) => x.id).toSet();

  Set<String> _descendantFolders(String id) {
    final out = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in c.store.data.folders) {
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
      final p = c.store.data.folders.where((x) => x.id == cur.parentId).firstOrNull;
      if (p == null) break;
      parts.insert(0, p.name);
      cur = p;
    }
    return parts.join(' › ');
  }

  // ───────────── Actions ─────────────

  Future<void> _addFolder(String? parentId) async {
    final name = await promptText(
      context,
      title: parentId == null ? 'Nouveau dossier' : 'Nouveau sous-dossier',
      message: 'Ex. « 2026-2027 » puis « Quadrimestre 1 ».',
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
    final name = await promptText(context, title: 'Nouveau cours', label: 'Nom du cours', confirmLabel: 'Créer');
    if (name == null || name.isEmpty) return;
    final course = c.store.addCourse(name, ue.id);
    setState(() => _collapsed.remove(ue.id));
    c.selectCourse(course.id);
  }

  Future<void> _rename(String title, String current, void Function(String) apply) async {
    final name = await promptText(context, title: title, initial: current, confirmLabel: 'Renommer');
    if (name == null || name.isEmpty) return;
    apply(name);
  }

  Future<void> _deleteFolder(Folder f) async {
    final doomed = _descendantFolders(f.id);
    final courseIds = c.store.data.ues
        .where((u) => u.folderId != null && doomed.contains(u.folderId))
        .expand((u) => _courseIdsOfUE(u.id))
        .toSet();
    if (_blockedByTimer(courseIds)) return;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${f.name} » ?',
      message: 'Le dossier et ses sous-dossiers sont supprimés. Les UE qu\'ils contiennent sont conservées : elles remontent à la racine.',
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
      message: "L'UE, ses cours et tout l'historique d'étude associé seront supprimés définitivement. "
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
      message: "Le cours et son historique d'étude seront supprimés définitivement.",
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (ok) c.store.deleteCourse(x.id);
  }

  Future<void> _moveUE(UE u) async {
    final folders = [
      for (final f in c.store.data.folders) (id: f.id, label: _folderPath(f)),
    ]..sort((a, b) => _byName(a.label, b.label));
    final picked = await pickFolder(context, title: 'Déplacer « ${u.name} »', folders: folders, current: u.folderId);
    if (picked == null) return;
    c.store.moveUE(u.id, picked.isEmpty ? null : picked);
  }

  void _archive(UE u, bool archived) {
    if (archived && _blockedByTimer(_courseIdsOfUE(u.id))) return;
    c.store.archiveUE(u.id, archived);
    if (archived) c.showMessage('« ${u.name} » archivée : son historique est conservé.');
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
          PopupMenuItem<String>(
            value: id,
            child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
          ),
      ],
    );
  }

  Widget _tile({
    required int depth,
    required IconData icon,
    required String title,
    required Widget menu,
    VoidCallback? onTap,
    Widget? expandIcon,
    bool selected = false,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: 6.0 + depth * 14, right: 4, top: 1, bottom: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 0),
            child: Row(
              children: [
                if (expandIcon != null) expandIcon else const SizedBox(width: 4),
                Icon(icon, size: 18, color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? (selected ? scheme.onSecondaryContainer : scheme.onSurface) : scheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                menu,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chevron(String id) => Icon(_collapsed.contains(id) ? Icons.chevron_right : Icons.expand_more, size: 18);

  List<Widget> _courseTiles(UE u, int depth) {
    return [
      for (final x in _coursesOf(u.id))
        _tile(
          depth: depth,
          icon: Icons.menu_book_outlined,
          title: x.name,
          selected: c.selectedCourseId == x.id,
          enabled: !c.busy || c.activeCourseId == x.id,
          onTap: () => c.selectCourse(x.id),
          menu: _menu(const [('rename', 'Renommer', Icons.edit_outlined), ('delete', 'Supprimer', Icons.delete_outline)], (a) {
            if (a == 'rename') _rename('Renommer le cours', x.name, (n) => c.store.renameCourse(x.id, n));
            if (a == 'delete') _deleteCourse(x);
          }),
        ),
    ];
  }

  List<Widget> _ueTiles(UE u, int depth) {
    return [
      _tile(
        depth: depth,
        icon: Icons.school_outlined,
        title: u.name,
        expandIcon: _chevron(u.id),
        onTap: () => setState(() => _toggle(u.id)),
        menu: _menu(const [
          ('course', 'Nouveau cours', Icons.add),
          ('rename', 'Renommer', Icons.edit_outlined),
          ('move', 'Déplacer…', Icons.drive_file_move_outline),
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
  }

  List<Widget> _folderTiles(Folder f, int depth) {
    return [
      _tile(
        depth: depth,
        icon: _collapsed.contains(f.id) ? Icons.folder_outlined : Icons.folder_open_outlined,
        title: f.name,
        expandIcon: _chevron(f.id),
        onTap: () => setState(() => _toggle(f.id)),
        menu: _menu(const [
          ('sub', 'Nouveau sous-dossier', Icons.create_new_folder_outlined),
          ('ue', 'Nouvelle UE', Icons.add),
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
        for (final u in _uesIn(f.id, archived: false)) ..._ueTiles(u, depth + 1),
      ],
    ];
  }

  List<Widget> _archiveTiles() {
    final archived = c.store.data.ues.where((u) => u.archived).toList()..sort((a, b) => _byName(a.name, b.name));
    return [
      for (final u in archived) ...[
        _tile(
          depth: 1,
          icon: Icons.inventory_2_outlined,
          title: u.name,
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
              selected: c.selectedCourseId == x.id,
              enabled: !c.busy || c.activeCourseId == x.id,
              onTap: () => c.selectCourse(x.id),
              menu: const SizedBox(width: 8),
            ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rootFolders = _subFolders(null);
    final rootUEs = _uesIn(null, archived: false);
    final archivedCount = c.store.data.ues.where((u) => u.archived).length;
    final empty = rootFolders.isEmpty && rootUEs.isEmpty && archivedCount == 0;

    return Container(
      width: 300,
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text('Cours', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Nouveau dossier',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: () => _addFolder(null),
                ),
                IconButton(tooltip: 'Nouvelle UE', icon: const Icon(Icons.add), onPressed: () => _addUE(null)),
              ],
            ),
          ),
          Expanded(
            child: empty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Commence par créer un dossier (ex. « 2026-2027 › Quadrimestre 1 »), puis une UE, puis des cours.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
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
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
