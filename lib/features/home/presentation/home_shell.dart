import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/routing/app_destinations.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';

/// Bottom navigation that shows only the tabs this role may open.
class HomeShell extends ConsumerWidget {
  /// Creates the shell around the current tab [child].
  const HomeShell({required this.location, required this.child, super.key});

  /// Current route path.
  final String location;

  /// The current tab.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final items = visibleDestinations(access);
    final index = items.indexWhere((d) => location.startsWith(d.path));
    final hasProfileTab = items.any((d) => d.path == RouteNames.profile);
    if (items.length < 2) {
      // A frame can be built while the session is ending; show no bar instead of crashing.
      return Scaffold(body: SafeArea(child: child));
    }
    return Scaffold(
      appBar: hasProfileTab
          ? null
          : AppBar(
              toolbarHeight: 48,
              actions: [
                IconButton(
                  tooltip: t.accountTooltip,
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => context.go(RouteNames.profile),
                ),
              ],
            ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(items[i].path),
        destinations: [
          for (final d in items)
            NavigationDestination(icon: Icon(d.icon), label: d.labelOf(t)),
        ],
      ),
    );
  }
}
