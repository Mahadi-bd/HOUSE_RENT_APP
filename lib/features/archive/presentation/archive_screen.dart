import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// Everything deleted in the last 2 years: bring it back, or (for tenants) open the legal records.
class ArchiveScreen extends ConsumerWidget {
  /// Creates the screen.
  const ArchiveScreen({super.key});

  String _label(AppLocalizations t, String type) {
    switch (type) {
      case 'tenant':
        return t.archTenant;
      case 'payment':
        return t.archPayment;
      case 'extra_charge':
        return t.archCharge;
      case 'expense':
        return t.archExpense;
      case 'household_member':
        return t.archMember;
      case 'document':
        return t.archDocument;
      default:
        return type;
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, DeletedArchive entry) async {
    final t = AppLocalizations.of(context);
    try {
      final repo = await ref.read(archiveRepositoryProvider.future);
      await repo.restore(entry.id);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.itemRestored)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    final canRestore = ref.watch(memberAccessProvider).dataOrNull?.can(Permission.archiveRestore) ?? false;
    final entries = ref.watch(archiveEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.archiveTitle)),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: t.archiveEmpty,
              message: t.archiveHint,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.archiveHint),
              const SizedBox(height: 8),
              for (final e in list)
                Card(
                  child: ListTile(
                    title: Text(_label(t, e.entityType)),
                    subtitle: Text(
                      '${t.deletedOn(fmt.date(e.deletedAt.toLocal()))}\n${t.keptUntil(fmt.date(e.purgeAfter.toLocal()))}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (e.entityType == 'tenant')
                          IconButton(
                            tooltip: t.legalOpen,
                            icon: const Icon(Icons.gavel_outlined),
                            onPressed: () => context.push('${RouteNames.archive}/legal/${e.entityId}'),
                          ),
                        if (canRestore)
                          TextButton(onPressed: () => _restore(context, ref, e), child: Text(t.restoreItem)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
