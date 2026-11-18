import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/features/settings/presentation/about_screen.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';

Widget _app(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    );

void main() {
  test('the permanent brand values are set', () {
    expect(BrandConfig.companyName, 'LIFE EASY');
    expect(BrandConfig.developerName, 'MAHADI HASAN JEWEL');
    expect(BrandConfig.logoAsset, 'assets/brand/life_easy_logo.png');
  });

  for (final code in ['en', 'bn', 'hi']) {
    testWidgets('About shows brand, developer credit and version in $code', (tester) async {
      await tester.pumpWidget(_app(const AboutScreen(), Locale(code)));
      await tester.pumpAndSettle();
      expect(find.text('LIFE EASY'), findsOneWidget);
      expect(find.text('MAHADI HASAN JEWEL'), findsOneWidget);
      expect(find.textContaining(BrandConfig.appVersion), findsOneWidget);
    });
  }

  testWidgets('the footer carries the brand and the developer', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: BrandFooter()), const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.textContaining('LIFE EASY'), findsOneWidget);
    expect(find.textContaining('MAHADI HASAN JEWEL'), findsOneWidget);
  });
}
