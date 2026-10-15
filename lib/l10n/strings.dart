import 'app_locales.dart';
import 'dict_en_gb.dart';
import 'dict_en_us.dart';
import 'dict_es.dart';
import 'dict_fr.dart';
import 'dict_hu.dart';
import 'dict_ro.dart';

/// Textul [key] în limba curentă. Ordinea de căutare: limba aleasă → engleză → română → cheia însăși.
/// Parametrii se scriu în text ca `{nume}` și se dau prin [args].
String tr(String key, [Map<String, String>? args]) {
  final String? text = _lookup(AppLocales.current.value, key) ?? dictEnUs[key] ?? dictRo[key];
  if (text == null) return key;
  if (args == null || args.isEmpty) return text;
  String result = text;
  args.forEach((name, value) {
    result = result.replaceAll('{$name}', value);
  });
  return result;
}

String? _lookup(String code, String key) {
  switch (code) {
    case 'en_GB':
      return dictEnGb[key] ?? dictEnUs[key];
    case 'en_US':
      return dictEnUs[key];
    case 'fr':
      return dictFr[key];
    case 'es':
      return dictEs[key];
    case 'hu':
      return dictHu[key];
    default:
      return dictRo[key];
  }
}
