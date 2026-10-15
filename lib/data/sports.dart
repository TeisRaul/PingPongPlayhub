import '../l10n/strings.dart';

/// Sporturile pentru care se pot face rezervări de jucători.
const List<String> kSportIds = ['ping_pong', 'padel', 'tenis', 'fotbal', 'handbal', 'baschet'];

/// Toate sporturile cunoscute (inclusiv cele afișate doar pe profilul sălii).
const List<String> kAllSportIds = [...kSportIds, 'mma', 'box'];

/// Numele sportului în limba curentă.
String sportLabel(String id) => tr('sport.$id');

/// Lista folosită de selectoarele/filtrele de sport: [{id, label}].
List<Map<String, String>> sportOptions() =>
    [for (final id in kSportIds) {'id': id, 'label': sportLabel(id)}];

/// Etichetă pentru câmpul „Sală de …" în funcție de sportul ales.
String venueFieldLabel(String sportId) => tr('create.venue_for_sport', {'sport': sportLabel(sportId)});
