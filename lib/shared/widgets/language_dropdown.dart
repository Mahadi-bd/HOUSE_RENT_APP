import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/localization/locale_provider.dart';

/// Language picker. Changes the whole app instantly.
class LanguageDropdown extends ConsumerWidget {
  /// Creates the dropdown.
  const LanguageDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    return DropdownMenu<String>(
      key: ValueKey(locale.languageCode),
      initialSelection: locale.languageCode,
      label: Text(t.languageLabel),
      expandedInsets: EdgeInsets.zero,
      onSelected: (code) {
        if (code != null) {
          ref.read(localeProvider.notifier).setLanguage(code);
        }
      },
      dropdownMenuEntries: [
        DropdownMenuEntry(value: 'en', label: t.languageEnglish),
        DropdownMenuEntry(value: 'bn', label: t.languageBengali),
        DropdownMenuEntry(value: 'hi', label: t.languageHindi),
      ],
    );
  }
}
