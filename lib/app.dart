import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/localization/locale_provider.dart';
import 'package:rent_solution/core/routing/router.dart';
import 'package:rent_solution/core/theme/app_theme.dart';
import 'package:rent_solution/features/security/email_link_inbox.dart';

/// Root widget: theme, language and router.
class RentSolutionApp extends ConsumerWidget {
  /// Creates the root widget.
  const RentSolutionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    // Start catching links (email confirmation) as early as possible.
    ref.watch(emailLinkInboxProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
