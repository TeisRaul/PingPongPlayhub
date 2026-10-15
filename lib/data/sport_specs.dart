import '../l10n/strings.dart';

/// Tipul unui câmp de detaliu pe sport.
enum SpecType { toggle, number, choice, multi }

/// Un câmp completat de sală pentru un sport (ex. „Se poate juca la dublu").
class SpecField {
  final String id;
  final SpecType type;
  final List<String> options; // pentru choice / multi
  final Object? def; // valoarea implicită

  const SpecField(this.id, this.type, {this.options = const [], this.def});

  String get label => tr('spec.f.$id');
}

/// Câmpurile specifice fiecărui sport. Se salvează în `venues/{id}.sportSpecs.{sport}`.
const Map<String, List<SpecField>> kSportSpecFields = {
  'ping_pong': [
    SpecField('doubles', SpecType.toggle, def: true),
    SpecField('equipment', SpecType.toggle, def: true),
  ],
  'padel': [
    SpecField('singles', SpecType.toggle, def: false),
    SpecField('rental', SpecType.toggle, def: true),
  ],
  'tenis': [
    SpecField('doubles', SpecType.toggle, def: true),
    SpecField('surface', SpecType.choice, options: ['clay', 'hard', 'grass', 'carpet'], def: 'clay'),
    SpecField('balls', SpecType.toggle, def: false),
    SpecField('rental', SpecType.toggle, def: true),
  ],
  'fotbal': [
    SpecField('formats', SpecType.multi, options: ['5x5', '6x6', '7x7', '8x8', '11x11'], def: ['5x5']),
    SpecField('surface', SpecType.choice, options: ['artificial', 'natural', 'parquet'], def: 'artificial'),
    SpecField('balls', SpecType.toggle, def: true),
  ],
  'handbal': [
    SpecField('maxPlayers', SpecType.number, def: 14),
    SpecField('balls', SpecType.toggle, def: true),
  ],
  'baschet': [
    SpecField('formats', SpecType.multi, options: ['3x3', '5x5'], def: ['5x5']),
    SpecField('balls', SpecType.toggle, def: true),
  ],
  'mma': [
    SpecField('maxPlayers', SpecType.number, def: 10),
    SpecField('bags', SpecType.toggle, def: true),
    SpecField('ring', SpecType.toggle, def: false),
    SpecField('mats', SpecType.toggle, def: true),
    SpecField('gloves', SpecType.toggle, def: false),
    SpecField('sparring', SpecType.toggle, def: true),
  ],
  'box': [
    SpecField('maxPlayers', SpecType.number, def: 10),
    SpecField('bags', SpecType.toggle, def: true),
    SpecField('ring', SpecType.toggle, def: false),
    SpecField('gloves', SpecType.toggle, def: false),
    SpecField('sparring', SpecType.toggle, def: true),
  ],
};

/// Sporturile de rachetă: 2 jucători = 1v1, 4 = 2v2.
const Set<String> _racketSports = {'ping_pong', 'padel', 'tenis'};

class SportSpecs {
  SportSpecs._();

  static List<SpecField> fieldsFor(String sport) => kSportSpecFields[sport] ?? const [];

  /// Valoarea unui câmp, cu valoarea implicită când sala nu a completat-o.
  static dynamic valueOf(String sport, SpecField f, Map<String, dynamic>? specs) {
    final dynamic v = specs?[f.id];
    return v ?? f.def;
  }

  /// Specificațiile complete (cu valori implicite) pentru salvare.
  static Map<String, dynamic> normalize(String sport, Map<String, dynamic>? raw) {
    final out = <String, dynamic>{};
    for (final f in fieldsFor(sport)) {
      final dynamic v = valueOf(sport, f, raw);
      if (f.type == SpecType.multi) {
        out[f.id] = List<String>.from((v as List?) ?? const []);
      } else if (f.type == SpecType.number) {
        out[f.id] = (v is num) ? v.toInt() : (int.tryParse('$v') ?? (f.def as int? ?? 0));
      } else {
        out[f.id] = v;
      }
    }
    final bool combat = sport == 'mma' || sport == 'box';
    out['supervised'] = raw?['supervised'] ?? combat;
    final dynamic age = raw?['minAge'];
    out['minAge'] = age is num ? age.toInt() : (int.tryParse('${age ?? 0}') ?? 0);
    out['rules'] = (raw?['rules'] ?? '').toString().trim();
    return out;
  }

  static int _teamSize(String format) => int.tryParse(format.split('x').first) ?? 0;

  /// Numărul total de jucători permis la o rezervare, după regulile sălii.
  static List<int> playerOptions(String sport, Map<String, dynamic>? specs) {
    final Set<int> out = {};
    switch (sport) {
      case 'ping_pong':
      case 'tenis':
        out.add(2);
        if (specs?['doubles'] != false) out.add(4);
        break;
      case 'padel':
        out.add(4);
        if (specs?['singles'] == true) out.add(2);
        break;
      case 'fotbal':
      case 'baschet':
        final List<dynamic> formats = (specs?['formats'] as List?) ?? (sport == 'fotbal' ? const ['5x5'] : const ['5x5']);
        for (final f in formats) {
          final int t = _teamSize(f.toString());
          if (t > 0) out.add(t * 2);
        }
        if (out.isEmpty) out.add(10);
        break;
      case 'handbal':
        out.add(((specs?['maxPlayers'] as num?) ?? 14).toInt());
        break;
      case 'mma':
      case 'box':
        final int cap = ((specs?['maxPlayers'] as num?) ?? 10).toInt();
        out.add(2);
        for (int i = 4; i <= cap && i <= 30; i += 2) {
          out.add(i);
        }
        if (cap > 2) out.add(cap);
        break;
      default:
        out.addAll([2, 4]);
    }
    final list = out.toList()..sort();
    return list;
  }

  static String playerOptionLabel(String sport, int n) {
    if (sport == 'fotbal' || sport == 'baschet') {
      return '${n ~/ 2}x${n ~/ 2} · ${tr('spec.n_players', {'n': '$n'})}';
    }
    if (_racketSports.contains(sport)) {
      if (n == 2) return tr('cm.fmt_1v1');
      if (n == 4) return tr('cm.fmt_2v2');
    }
    return tr('spec.n_players', {'n': '$n'});
  }

  static String optionLabel(String option) {
    if (RegExp(r'^\d+x\d+$').hasMatch(option)) return option;
    return tr('spec.o.$option');
  }

  /// Perechi (etichetă, valoare) de afișat jucătorilor.
  static List<(String, String)> summary(String sport, Map<String, dynamic>? specs) {
    final out = <(String, String)>[];
    for (final f in fieldsFor(sport)) {
      final dynamic v = valueOf(sport, f, specs);
      switch (f.type) {
        case SpecType.toggle:
          out.add((f.label, v == true ? tr('spec.yes') : tr('spec.no')));
          break;
        case SpecType.number:
          out.add((f.label, '${(v as num?)?.toInt() ?? 0}'));
          break;
        case SpecType.choice:
          if (v != null) out.add((f.label, optionLabel(v.toString())));
          break;
        case SpecType.multi:
          final list = ((v as List?) ?? const []).map((e) => optionLabel(e.toString())).toList();
          if (list.isNotEmpty) out.add((f.label, list.join(', ')));
          break;
      }
    }
    return out;
  }

  static bool isSupervised(String sport, Map<String, dynamic>? specs) {
    final bool combat = sport == 'mma' || sport == 'box';
    return (specs?['supervised'] ?? (specs == null ? false : combat)) == true;
  }

  static int minAge(Map<String, dynamic>? specs) => ((specs?['minAge'] as num?) ?? 0).toInt();

  static String rulesOf(Map<String, dynamic>? specs) => (specs?['rules'] ?? '').toString().trim();

  /// Sala are ceva de acceptat pentru acest sport (reguli, supraveghere sau vârstă minimă)?
  static bool hasRules(String sport, Map<String, dynamic>? specs, String venueRules) {
    return venueRules.trim().isNotEmpty ||
        rulesOf(specs).isNotEmpty ||
        isSupervised(sport, specs) ||
        minAge(specs) > 0;
  }
}
