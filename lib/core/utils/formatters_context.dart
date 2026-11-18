import 'package:flutter/widgets.dart';
import 'package:rent_solution/core/utils/formatters.dart';

/// `context.fmt` gives money, number and date text in the current app language.
extension FormattersContext on BuildContext {
  /// Formatters for the language shown on screen.
  AppFormatters get fmt => AppFormatters(Localizations.localeOf(this).languageCode);
}
