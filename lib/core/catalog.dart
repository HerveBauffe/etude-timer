import 'models.dart';
import 'quadri.dart';

/// Requêtes sur l'arborescence (dossiers › UE › cours) en tenant compte du filtre de quadrimestre.

/// Identifiants des cours affichés pour ce filtre (hors UE archivées : inclus, l'archivage ne masque pas
/// l'historique dans les statistiques).
Set<String> visibleCourseIds(AppData d, QuadriFilter f) => {
      for (final c in d.courses)
        if (f.matches(c.quadri)) c.id,
    };

/// Quadrimestres couverts par une UE (déduits de ses cours) : [1], [2] ou [1, 2]. Vide si aucun cours.
List<int> ueQuadris(AppData d, String ueId) {
  final s = <int>{for (final c in d.courses) if (c.ueId == ueId) c.quadri};
  return s.toList()..sort();
}

/// Une UE est affichée si l'un de ses cours correspond au filtre, ou si elle n'a encore aucun cours
/// (sinon impossible de lui en ajouter).
bool ueVisible(AppData d, UE u, QuadriFilter f) {
  final qs = ueQuadris(d, u.id);
  return qs.isEmpty || qs.any(f.matches);
}

/// Un dossier est affiché s'il contient (même indirectement) une UE affichée, ou s'il ne contient
/// aucune UE active (dossier vide).
bool folderVisible(AppData d, Folder folder, QuadriFilter f) {
  final ids = <String>{folder.id};
  var grew = true;
  while (grew) {
    grew = false;
    for (final x in d.folders) {
      if (x.parentId != null && ids.contains(x.parentId) && ids.add(x.id)) grew = true;
    }
  }
  final inside = d.ues.where((u) => u.folderId != null && ids.contains(u.folderId) && !u.archived).toList();
  if (inside.isEmpty) return true;
  return inside.any((u) => ueVisible(d, u, f));
}

/// « Q1 », « Q2 » ou « Q1+Q2 » (chaîne vide si vide).
String quadriBadge(Iterable<int> quadris) {
  final s = quadris.toSet().toList()..sort();
  return s.map((q) => 'Q$q').join('+');
}
