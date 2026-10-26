/// Quadrimestres. Un **cours** (et son examen) appartient à un seul quadrimestre (1 ou 2) ;
/// une **UE** peut donc s'étendre sur les deux (elle contient des cours des deux quadrimestres).

/// Filtre global affiché dans la barre latérale : Q1, Q2 ou Q1+Q2.
enum QuadriFilter {
  q1,
  q2,
  both;

  String get label => switch (this) {
        QuadriFilter.q1 => 'Q1',
        QuadriFilter.q2 => 'Q2',
        QuadriFilter.both => 'Q1+Q2',
      };

  bool matches(int quadri) => switch (this) {
        QuadriFilter.q1 => quadri == 1,
        QuadriFilter.q2 => quadri == 2,
        QuadriFilter.both => true,
      };

  /// Quadrimestre proposé par défaut à la création d'un cours.
  int get defaultQuadri => this == QuadriFilter.q2 ? 2 : 1;

  static QuadriFilter parse(String? s) => switch (s) {
        'q2' => QuadriFilter.q2,
        'both' => QuadriFilter.both,
        _ => QuadriFilter.q1,
      };
}

final List<RegExp> _quadriPatterns = [
  RegExp(r'\bq\s*\.?\s*([12])\b'),
  RegExp(r'\bquad(?:ri(?:mestre)?)?\s*\.?\s*([12])\b'),
  RegExp(r'\b([12])\s*(?:er|re|e|ère|ere|ème|eme|nd|nde|d)?\s*quad'),
  RegExp(r'\bsem(?:estre)?\s*\.?\s*([12])\b'),
];

/// Devine le quadrimestre d'après les noms de dossiers (du plus proche au plus lointain),
/// ex. « Quadrimestre 2 », « Q1 », « 2e quadri ». `null` si rien de reconnaissable.
/// Sert uniquement à migrer les anciennes données (où le quadrimestre était un dossier).
int? inferQuadriFromNames(Iterable<String> namesNearestFirst) {
  for (final raw in namesNearestFirst) {
    final name = raw.toLowerCase();
    for (final re in _quadriPatterns) {
      final m = re.firstMatch(name);
      if (m != null) return int.parse(m.group(1)!);
    }
  }
  return null;
}
