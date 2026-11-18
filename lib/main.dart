import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rent_solution/app.dart';
import 'package:rent_solution/core/localization/locale_provider.dart';
import 'package:rent_solution/firebase_options.dart';

/// App entry point: loads the saved language, starts Firebase (relay and sign-in only), Riverpod.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final language = await const LanguageStore().load();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    ProviderScope(
      overrides: [initialLanguageProvider.overrideWithValue(language)],
      child: const RentSolutionApp(),
    ),
  );
}
