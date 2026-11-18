import 'package:flutter/material.dart';
import 'package:rent_solution/core/brand/brand_config.dart';

/// The business logo with its name, shown on the sign-in screen and the dashboard.
class BrandHeader extends StatelessWidget {
  /// Creates the header. [name] defaults to the brand of this build.
  const BrandHeader({this.name, super.key});

  /// Business name to show.
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          BrandConfig.logoAsset,
          height: 56,
          errorBuilder: (_, __, ___) => const SizedBox(height: 56),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name ?? BrandConfig.companyName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
