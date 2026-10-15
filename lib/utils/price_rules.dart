/// Reguli de preț pe interval pentru o sală (salvate în `venues/{id}.priceRules`).
///
/// O regulă se aplică pe zile ale săptămânii și pe un interval de ore (opțional și pe perioadă).
/// - `fixed`: tarif fix pe oră (RON/oră) pentru intervalul respectiv;
/// - `percent`: reducere în procente față de tariful obișnuit al sălii.
/// Dacă mai multe reguli se potrivesc, se aplică prima din listă (cele noi se adaugă la început).
class VenuePriceRule {
  final String id;
  final String name;
  final String mode; // 'fixed' | 'percent'
  final List<int> days; // 1 = luni ... 7 = duminică; gol = toate zilele
  final double startHour;
  final double endHour;
  final double value; // fixed: RON/oră, percent: 0-100
  final String? validFrom; // yyyy-MM-dd
  final String? validTo; // yyyy-MM-dd
  final bool active;

  const VenuePriceRule({
    required this.id,
    required this.name,
    required this.mode,
    required this.days,
    required this.startHour,
    required this.endHour,
    required this.value,
    this.validFrom,
    this.validTo,
    this.active = true,
  });

  bool get isFixed => mode == 'fixed';

  factory VenuePriceRule.fromMap(Map<String, dynamic> m) => VenuePriceRule(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        mode: (m['mode'] ?? 'percent').toString() == 'fixed' ? 'fixed' : 'percent',
        days: List<dynamic>.from(m['days'] ?? const []).map((e) => (e as num).toInt()).toList(),
        startHour: (m['startHour'] as num?)?.toDouble() ?? 0,
        endHour: (m['endHour'] as num?)?.toDouble() ?? 24,
        value: (m['value'] as num?)?.toDouble() ?? 0,
        validFrom: (m['validFrom'] as String?)?.isEmpty == true ? null : m['validFrom'] as String?,
        validTo: (m['validTo'] as String?)?.isEmpty == true ? null : m['validTo'] as String?,
        active: m['active'] != false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'mode': mode,
        'days': days,
        'startHour': startHour,
        'endHour': endHour,
        'value': value,
        'validFrom': validFrom,
        'validTo': validTo,
        'active': active,
      };

  VenuePriceRule copyWith({bool? active}) => VenuePriceRule(
        id: id,
        name: name,
        mode: mode,
        days: days,
        startHour: startHour,
        endHour: endHour,
        value: value,
        validFrom: validFrom,
        validTo: validTo,
        active: active ?? this.active,
      );

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Regula se aplică pe jumătatea de oră care începe la [slotStart] în ziua [date]?
  bool matches(DateTime date, double slotStart) {
    if (!active) return false;
    if (days.isNotEmpty && !days.contains(date.weekday)) return false;
    if (slotStart < startHour || slotStart >= endHour) return false;
    final ds = _ymd(date);
    if (validFrom != null && ds.compareTo(validFrom!) < 0) return false;
    if (validTo != null && ds.compareTo(validTo!) > 0) return false;
    return true;
  }

  /// Prețul unei jumătăți de oră după aplicarea regulii.
  double applyToHalfHour(double baseHalf) {
    if (isFixed) return value / 2;
    final p = value.clamp(0, 100).toDouble();
    return baseHalf * (1 - p / 100);
  }

  static List<VenuePriceRule> parseList(dynamic raw) {
    if (raw is! List) return [];
    final out = <VenuePriceRule>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          out.add(VenuePriceRule.fromMap(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    return out;
  }

  /// Prețul final al unei jumătăți de oră: prima regulă potrivită, altfel [baseHalf].
  static double slotPrice(List<VenuePriceRule> rules, DateTime? date, double slotStart, double baseHalf) {
    if (date == null || rules.isEmpty) return baseHalf;
    for (final r in rules) {
      if (r.matches(date, slotStart)) return r.applyToHalfHour(baseHalf);
    }
    return baseHalf;
  }
}
