import 'package:flutter/material.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';

/// About: the permanent brand, developer credit and licence note.
class AboutScreen extends StatelessWidget {
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
          const SizedBox(height: 4),
          Text(t.appName, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 24),
          Text(t.aboutDevelopedBy, textAlign: TextAlign.center),
          Text(
            BrandConfig.developerName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Text(t.aboutLicense, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
