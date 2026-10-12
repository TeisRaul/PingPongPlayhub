/// Ajutoare pentru orele meciurilor salvate în Firestore.
///
/// Orele pot fi salvate ca `int` (17) sau `double` (17.5 pentru jumătăți de oră).
/// Un cast direct `as int` sau `final int x = data['startHour']` aruncă
/// TypeError pe mobil când valoarea este double, de aceea se citește prin `hourValue`.
library;

/// Citește o oră din Firestore ca double; [fallback] dacă lipsește sau nu e număr.
double hourValue(dynamic value, [double fallback = 0]) {
  return value is num ? value.toDouble() : fallback;
}

/// 17 -> "17:00", 17.5 -> "17:30". Pentru valori lipsă returnează "?".
String formatHour(dynamic value) {
  if (value is! num) return '?';
  final double h = value.toDouble();
  int hh = h.floor();
  int mm = ((h - hh) * 60).round();
  if (mm == 60) {
    hh += 1;
    mm = 0;
  }
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// Construiește un DateTime din data `yyyy-MM-dd` și o oră (posibil fracționară).
/// Aruncă [FormatException] dacă data nu e validă, ca în `DateTime.parse`.
DateTime dateAtHour(String dateStr, dynamic hour) {
  final parts = dateStr.split('-');
  if (parts.length != 3) {
    throw FormatException('Dată invalidă: $dateStr');
  }
  final double h = hourValue(hour);
  int hh = h.floor();
  int mm = ((h - hh) * 60).round();
  if (mm == 60) {
    hh += 1;
    mm = 0;
  }
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), hh, mm);
}
