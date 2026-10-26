import 'package:flutter/material.dart';

/// Material You (Material 3) : schémas de couleurs générés avec `ColorScheme.fromSeed`.
///
/// Par défaut : noir et blanc (variante *monochrome* du moteur de couleurs Material You) en
/// thème sombre. Sur bureau, la couleur dynamique du fond d'écran n'existe pas ; on propose
/// donc quelques palettes « graine » à la place.
class AppPalette {
  final String id;
  final String label;
  final Color seed;
  final bool monochrome;
  const AppPalette(this.id, this.label, this.seed, {this.monochrome = false});
}

const List<AppPalette> appPalettes = [
  AppPalette('mono', 'Noir et blanc', Color(0xFF888888), monochrome: true),
  AppPalette('teal', 'Sarcelle', Color(0xFF3F6659)),
  AppPalette('indigo', 'Indigo', Color(0xFF4F5BD5)),
  AppPalette('rose', 'Rose', Color(0xFFC2185B)),
  AppPalette('amber', 'Ambre', Color(0xFF8A6E4B)),
];

AppPalette paletteById(String id) => appPalettes.firstWhere((p) => p.id == id, orElse: () => appPalettes.first);

ThemeMode themeModeFrom(String s) => switch (s) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

/// Chiffres de même largeur pour que le minuteur ne « tremble » pas.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

final Map<String, ThemeData> _themeCache = {};

/// Thème Material 3 pour une palette et une luminosité (mis en cache : la génération du schéma
/// de couleurs n'est pas gratuite et l'interface se reconstruit à chaque modification de données).
ThemeData buildTheme(String paletteId, Brightness brightness) =>
    _themeCache.putIfAbsent('$paletteId/${brightness.name}', () => _buildTheme(paletteId, brightness));

ThemeData _buildTheme(String paletteId, Brightness brightness) {
  final p = paletteById(paletteId);
  final scheme = ColorScheme.fromSeed(
    seedColor: p.seed,
    brightness: brightness,
    dynamicSchemeVariant: p.monochrome ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontFeatures: tabularFigures),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
