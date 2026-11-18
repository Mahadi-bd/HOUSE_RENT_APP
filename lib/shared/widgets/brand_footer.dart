import 'package:flutter/material.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';

/// A small permanent line: brand and developer credit.
class BrandFooter extends StatelessWidget {
  /// Creates the footer.
  const BrandFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        '${BrandConfig.companyName} · ${t.aboutDeveloped} ${BrandConfig.developerName}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
