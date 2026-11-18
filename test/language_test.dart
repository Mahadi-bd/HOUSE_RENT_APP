import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/localization/locale_provider.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';

class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(body: Text(AppLocalizations.of(context).tabTenants)),
      ),
    );
  }
}

void main() {
  group('language store', () {
    test('defaults to English and ignores unsupported codes', () async {
      final memory = MemoryKeyValueStore();
      final store = LanguageStore(memory);
      expect(await store.load(), 'en');
      await store.save('fr');
      expect(await store.load(), 'en');
      await memory.write('language_v1', 'xx');
      expect(await store.load(), 'en');
    });

    test('the chosen language survives a restart', () async {
      final memory = MemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [languageStoreProvider.overrideWithValue(LanguageStore(memory))],
      );
      addTearDown(container.dispose);
      container.read(localeProvider.notifier).setLanguage('bn');
      await Future<void>.delayed(Duration.zero);

      final restartedLanguage = await LanguageStore(memory).load();
      expect(restartedLanguage, 'bn');
      final restarted = ProviderContainer(
        overrides: [initialLanguageProvider.overrideWithValue(restartedLanguage)],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(localeProvider).languageCode, 'bn');
    });
  });

  testWidgets('English by default, then Bengali and Hindi switch instantly', (tester) async {
    final container = ProviderContainer(
      overrides: [
        languageStoreProvider.overrideWithValue(LanguageStore(MemoryKeyValueStore())),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const _Probe()));
    expect(find.text('Tenants'), findsOneWidget);

    container.read(localeProvider.notifier).setLanguage('bn');
    await tester.pumpAndSettle();
    expect(find.text('ভাড়াটিয়া'), findsOneWidget);

    container.read(localeProvider.notifier).setLanguage('hi');
    await tester.pumpAndSettle();
    expect(find.text('किरायेदार'), findsOneWidget);
  });
}
