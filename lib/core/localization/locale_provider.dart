import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/constants/app_constants.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';

/// Saves and loads the chosen language so it survives app restarts.
class LanguageStore {
  /// Creates the store.
  const LanguageStore([this._store = const SecureKeyValueStore()]);

  final KeyValueStore _store;

  static const _key = 'language_v1';

  /// The saved language code, or the default (English) when nothing valid is saved.
  Future<String> load() async {
    final saved = await _store.read(_key);
    if (saved != null && AppConstants.supportedLanguages.contains(saved)) {
      return saved;
    }
    return AppConstants.defaultLanguage;
  }

  /// Saves [code] if it is supported.
  Future<void> save(String code) async {
    if (AppConstants.supportedLanguages.contains(code)) {
      await _store.write(_key, code);
    }
  }
}

/// The store used by the app (override in tests).
final languageStoreProvider = Provider<LanguageStore>((ref) => const LanguageStore());

/// Language loaded before the first frame in main(). Overridden at startup.
final initialLanguageProvider = Provider<String>((ref) => AppConstants.defaultLanguage);

/// Holds the current app language. Default is English.
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

/// Changes the app language instantly and remembers it.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => Locale(ref.watch(initialLanguageProvider));

  /// Switches to [code] if it is supported; ignores unknown codes.
  void setLanguage(String code) {
    if (AppConstants.supportedLanguages.contains(code)) {
      state = Locale(code);
      ref.read(languageStoreProvider).save(code);
    }
  }
}
