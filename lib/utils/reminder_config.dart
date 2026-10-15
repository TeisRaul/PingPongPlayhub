import '../l10n/strings.dart';

/// Setările de reminder ale unui jucător (generale sau pentru un meci anume).
///
/// Aceeași logică există și în functions/reminders.js (`normalize` / `fireTimes`):
/// dacă schimbi una, schimbă-o și pe cealaltă.
class ReminderConfig {
  final bool enabled;

  /// Cu câte minute înainte de meci vine prima notificare.
  final int firstMin;

  /// La câte minute se repetă notificarea; 0 = nu se repetă.
  final int repeatEveryMin;

  /// 'count' = de [repeatCount] ori în plus; 'until_start' = până începe meciul.
  final String repeatMode;
  final int repeatCount;

  const ReminderConfig({
    this.enabled = true,
    this.firstMin = 60,
    this.repeatEveryMin = 0,
    this.repeatMode = 'count',
    this.repeatCount = 1,
  });

  static const ReminderConfig defaults = ReminderConfig();

  static const List<int> firstOptions = [60, 120, 180, 1440, 2880, 4320, 10080];
  static const List<int> repeatOptions = [0, 30, 60, 120, 360, 1440];
  static const int maxRepeatCount = 10;
  static const int _maxTimes = 20;
  static const int _minBeforeStartMin = 10;

  bool get repeats => repeatEveryMin > 0;
  bool get untilStart => repeatMode == 'until_start';

  ReminderConfig copyWith({
    bool? enabled,
    int? firstMin,
    int? repeatEveryMin,
    String? repeatMode,
    int? repeatCount,
  }) =>
      ReminderConfig(
        enabled: enabled ?? this.enabled,
        firstMin: firstMin ?? this.firstMin,
        repeatEveryMin: repeatEveryMin ?? this.repeatEveryMin,
        repeatMode: repeatMode ?? this.repeatMode,
        repeatCount: repeatCount ?? this.repeatCount,
      );

  factory ReminderConfig.fromMap(Object? raw) {
    if (raw is! Map) return defaults;
    int intOf(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final first = intOf(raw['firstMin'], defaults.firstMin);
    final every = intOf(raw['repeatEveryMin'], 0);
    final count = intOf(raw['repeatCount'], defaults.repeatCount);
    return ReminderConfig(
      enabled: raw['enabled'] != false,
      firstMin: firstOptions.contains(first) ? first : defaults.firstMin,
      repeatEveryMin: repeatOptions.contains(every) ? every : 0,
      repeatMode: raw['repeatMode'] == 'until_start' ? 'until_start' : 'count',
      repeatCount: count.clamp(0, maxRepeatCount).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'firstMin': firstMin,
        'repeatEveryMin': repeatEveryMin,
        'repeatMode': repeatMode,
        'repeatCount': repeatCount,
      };

  /// Momentele la care jucătorul primește notificarea pentru un meci care începe la [start].
  List<DateTime> fireTimes(DateTime start) {
    if (!enabled) return const [];
    final first = start.subtract(Duration(minutes: firstMin));
    final times = <DateTime>[first];
    if (repeats) {
      final limit = start.subtract(const Duration(minutes: _minBeforeStartMin));
      final extra = untilStart ? _maxTimes : repeatCount;
      for (int k = 1; k <= extra && times.length < _maxTimes; k++) {
        final next = first.add(Duration(minutes: repeatEveryMin * k));
        if (next.isAfter(limit)) break;
        times.add(next);
      }
    }
    return times;
  }

  static String firstLabel(int min) => tr('rem.f_$min');
  static String repeatLabel(int min) => tr('rem.r_$min');

  /// Un rând scurt care descrie setările (pentru listă / card).
  String summary() {
    if (!enabled) return tr('rem.sum_off');
    final first = firstLabel(firstMin);
    if (!repeats) return first;
    final every = repeatLabel(repeatEveryMin).toLowerCase();
    if (untilStart) return tr('rem.sum_until', {'first': first, 'every': every});
    return tr('rem.sum_count', {'first': first, 'every': every, 'n': '$repeatCount'});
  }
}
