import 'package:flutter/cupertino.dart' show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Textes Material en français (sélecteur de date, boutons, info-bulles…).
///
/// On évite volontairement le paquet `flutter_localizations` : il embarque les traductions de
/// ~80 langues, ce qui alourdit l'exécutable pour rien. Ici : une seule langue.
class FrMaterialLocalizations extends DefaultMaterialLocalizations {
  const FrMaterialLocalizations();

  static const LocalizationsDelegate<MaterialLocalizations> delegate = _FrDelegate();

  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  static const _shortMonths = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  static const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _shortWeekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  String formatCompactDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
  @override
  String formatShortDate(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';
  @override
  String formatMediumDate(DateTime d) => '${_shortWeekdays[d.weekday - 1]} ${d.day} ${_shortMonths[d.month - 1]}';
  @override
  String formatFullDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';
  @override
  String formatMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
  @override
  String formatShortMonthDay(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]}';

  @override
  DateTime? parseCompactDate(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$').firstMatch(s);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    final d = DateTime(year, month, day);
    return (d.year == year && d.month == month && d.day == day) ? d : null;
  }

  @override
  List<String> get narrowWeekdays => const ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
  @override
  int get firstDayOfWeekIndex => 1; // lundi
  @override
  String get dateSeparator => '/';
  @override
  String get dateHelpText => 'jj/mm/aaaa';
  @override
  String get selectYearSemanticsLabel => "Choisir l'année";
  @override
  String get unspecifiedDate => 'Date';
  @override
  String get unspecifiedDateRange => 'Période';
  @override
  String get dateInputLabel => 'Saisir une date';
  @override
  String get dateRangeStartLabel => 'Date de début';
  @override
  String get dateRangeEndLabel => 'Date de fin';
  @override
  String dateRangeStartDateSemanticLabel(String d) => 'Date de début $d';
  @override
  String dateRangeEndDateSemanticLabel(String d) => 'Date de fin $d';
  @override
  String get invalidDateFormatLabel => 'Format invalide.';
  @override
  String get invalidDateRangeLabel => 'Période invalide.';
  @override
  String get dateOutOfRangeLabel => 'Hors période.';
  @override
  String get saveButtonLabel => 'Enregistrer';
  @override
  String get datePickerHelpText => 'Choisir une date';
  @override
  String get dateRangePickerHelpText => 'Choisir une période';
  @override
  String get calendarModeButtonLabel => 'Passer au calendrier';
  @override
  String get inputDateModeButtonLabel => 'Passer à la saisie';
  @override
  String get timePickerDialHelpText => "Choisir l'heure";
  @override
  String get timePickerInputHelpText => "Saisir l'heure";
  @override
  String get timePickerHourLabel => 'Heure';
  @override
  String get timePickerMinuteLabel => 'Minute';
  @override
  String get invalidTimeLabel => 'Saisir une heure valide';
  @override
  String get dialModeButtonLabel => 'Passer au cadran';
  @override
  String get inputTimeModeButtonLabel => 'Passer à la saisie';
  @override
  String get openAppDrawerTooltip => 'Ouvrir le menu';
  @override
  String get backButtonTooltip => 'Retour';
  @override
  String get clearButtonTooltip => 'Effacer';
  @override
  String get closeButtonTooltip => 'Fermer';
  @override
  String get deleteButtonTooltip => 'Supprimer';
  @override
  String get moreButtonTooltip => 'Plus';
  @override
  String get nextMonthTooltip => 'Mois suivant';
  @override
  String get previousMonthTooltip => 'Mois précédent';
  @override
  String get showMenuTooltip => 'Afficher le menu';
  @override
  String get drawerLabel => 'Menu de navigation';
  @override
  String get popupMenuLabel => 'Menu contextuel';
  @override
  String get dialogLabel => 'Boîte de dialogue';
  @override
  String get alertDialogLabel => 'Alerte';
  @override
  String get searchFieldLabel => 'Rechercher';
  @override
  String get currentDateLabel => "Aujourd'hui";
  @override
  String get selectedDateLabel => 'Sélectionné';
  @override
  String get cancelButtonLabel => 'Annuler';
  @override
  String get closeButtonLabel => 'Fermer';
  @override
  String get continueButtonLabel => 'Continuer';
  @override
  String get copyButtonLabel => 'Copier';
  @override
  String get cutButtonLabel => 'Couper';
  @override
  String get okButtonLabel => 'OK';
  @override
  String get pasteButtonLabel => 'Coller';
  @override
  String get selectAllButtonLabel => 'Tout sélectionner';
  @override
  String get lookUpButtonLabel => 'Rechercher';
  @override
  String get searchWebButtonLabel => 'Rechercher sur le Web';
  @override
  String get shareButtonLabel => 'Partager';
  @override
  String get modalBarrierDismissLabel => 'Fermer';
  @override
  String get menuDismissLabel => 'Fermer le menu';
  @override
  String get scrimLabel => 'Voile';
  @override
  String get bottomSheetLabel => 'Panneau inférieur';
  @override
  String get expandedIconTapHint => 'Réduire';
  @override
  String get collapsedIconTapHint => 'Développer';
  @override
  String get refreshIndicatorSemanticLabel => 'Actualiser';
  @override
  TimeOfDayFormat timeOfDayFormat({bool alwaysUse24HourFormat = false}) => TimeOfDayFormat.HH_colon_mm;
}

class _FrDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _FrDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture<MaterialLocalizations>(const FrMaterialLocalizations());

  @override
  bool shouldReload(_FrDelegate old) => false;
}

/// Les textes Cupertino ne servent qu'aux barres d'outils de sélection iOS/macOS ; on fournit
/// simplement les valeurs par défaut pour toutes les langues afin qu'aucun widget n'échoue.
class FrCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const FrCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(const DefaultCupertinoLocalizations());

  @override
  bool shouldReload(FrCupertinoDelegate old) => false;
}
