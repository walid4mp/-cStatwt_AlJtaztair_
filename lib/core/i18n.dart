import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n_strings.dart';

const List<String> kLanguages = ['ar', 'fr', 'en'];

const Map<String, String> kLanguageNames = {
  'ar': 'العربية',
  'fr': 'Français',
  'en': 'English',
};

String _currentLang = 'ar';
String get currentLang => _currentLang;
void setCurrentLang(String code) => _currentLang = code;
bool get isRtl => _currentLang == 'ar';

String _lookup(String lang, String key) {
  return kStrings[lang]?[key] ?? kStrings['en']?[key] ?? kStrings['ar']?[key] ?? key;
}

String _fmt(String text, Map<String, String>? args) {
  if (args == null || args.isEmpty) return text;
  var out = text;
  args.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}

/// Translate without a BuildContext (services, async callbacks).
String trNow(String key, [Map<String, String>? args]) => _fmt(_lookup(_currentLang, key), args);

extension TrContext on BuildContext {
  /// Registers a dependency on the locale so widgets rebuild when the language changes.
  String tr(String key, [Map<String, String>? args]) {
    final code = Localizations.localeOf(this).languageCode;
    return _fmt(_lookup(code, key), args);
  }

  String get lang => Localizations.localeOf(this).languageCode;
}

/// Human readable text for any thrown error, in the current language.
String errMsg(Object e) {
  if (e is ApiException) {
    final key = 'err_${e.code}';
    final txt = kStrings[_currentLang]?[key] ?? kStrings['en']?[key];
    if (txt != null) return txt;
    if (e.status == 0) return trNow('err_NETWORK');
    if (e.status >= 500) return trNow('err_SERVER_ERROR');
    // server messages are English/Arabic; fall back to them for unknown 4xx codes
    return e.message.isNotEmpty ? e.message : trNow('err_unknown');
  }
  return trNow('err_unknown');
}

String reportTypeLabel(BuildContext c, String type) {
  final k = reportTypeKey(type);
  return k == 'other' ? type : c.tr('type_$k');
}

/// Server stores the Arabic name of the report type.
String reportTypeKey(String type) {
  switch (type) {
    case 'مدني':
      return 'civic';
    case 'مفقودات':
      return 'lost';
    case 'خدمات':
      return 'services';
    case 'سلامة عامة':
      return 'safety';
    case 'احتيال/نصب':
      return 'fraud';
    case 'بيئة':
      return 'env';
    case 'مرور وطرق':
      return 'traffic';
    default:
      return 'other';
  }
}

const List<String> kReportTypes = ['مدني', 'سلامة عامة', 'مرور وطرق', 'بيئة', 'خدمات', 'احتيال/نصب', 'مفقودات'];
const List<String> kReportStatuses = ['PENDING', 'REVIEWED', 'VERIFIED', 'RESOLVED', 'REJECTED'];
const List<String> kLostCategories = ['phone', 'documents', 'wallet', 'keys', 'bag', 'vehicle', 'pet', 'person', 'jewelry', 'electronics', 'other'];
