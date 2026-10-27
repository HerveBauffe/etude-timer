import 'dart:io';

import 'package:flutter/widgets.dart';

/// Appareil mobile (téléphone / tablette) : pas de souris, pas de fenêtre redimensionnable.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// En dessous : disposition « téléphone » (barre de navigation en bas, liste des cours en feuille).
const double compactBreakpoint = 600;

/// À partir de cette largeur de fenêtre : la liste des cours reste affichée à côté du minuteur.
/// En dessous (tablette en portrait, petite fenêtre), elle s'ouvre dans une feuille modale.
const double wideBreakpoint = 900;

/// Largeur de la fenêtre entière (pas de la zone de contenu).
bool isCompactWidth(BuildContext context) => MediaQuery.sizeOf(context).width < compactBreakpoint;
