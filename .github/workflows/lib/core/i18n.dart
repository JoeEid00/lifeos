import 'package:flutter/widgets.dart';

import 'strings_ar.dart';

/// Lightweight i18n: English text is the key, Arabic comes from [kArabic].
extension Tr on BuildContext {
  bool get isAr => Localizations.localeOf(this).languageCode == 'ar';
  String t(String key) => isAr ? (kArabic[key] ?? key) : key;
}
