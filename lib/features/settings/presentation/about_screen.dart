import 'package:flutter/material.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';

/// About: the permanent brand, developer credit and licence. Open to every role.
class AboutScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Image.asset(
              BrandConfig.logoAsset,
              height: 140,
              errorBuilder: (_, __, ___) => const SizedBox(height: 140),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            BrandConfig.companyName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Text(t.aboutDeveloped, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          Text(
            BrandConfig.developerName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          Text(
            '${BrandConfig.appName} ${t.aboutVersion(BrandConfig.appVersion)}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(BrandConfig.licenceLine, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
