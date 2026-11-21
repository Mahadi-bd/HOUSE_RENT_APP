import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/guards.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/security/database_key_exceptions.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/data/local/open_database.dart';
import 'package:rent_solution/features/archive/presentation/archive_screen.dart';
import 'package:rent_solution/features/archive/presentation/legal_screen.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/auth/presentation/sign_in_screen.dart';
import 'package:rent_solution/features/expenses/presentation/add_expense_screen.dart';
import 'package:rent_solution/features/expenses/presentation/expenses_screen.dart';
import 'package:rent_solution/features/home/presentation/home_shell.dart';
import 'package:rent_solution/features/home/presentation/placeholder_tabs.dart';
import 'package:rent_solution/features/home/presentation/settings_screen.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/organization/presentation/create_organization_screen.dart';
import 'package:rent_solution/features/organization/presentation/no_access_screen.dart';
import 'package:rent_solution/features/payments/presentation/add_charge_screen.dart';
import 'package:rent_solution/features/payments/presentation/payments_tab.dart';
import 'package:rent_solution/features/payments/presentation/record_payment_screen.dart';
import 'package:rent_solution/features/properties/presentation/properties_screen.dart';
import 'package:rent_solution/features/recovery/recovery_screen.dart';
import 'package:rent_solution/features/settings/presentation/about_screen.dart';
import 'package:rent_solution/features/settings/presentation/business_details_screen.dart';
import 'package:rent_solution/features/tenants/presentation/add_tenant_screen.dart';
import 'package:rent_solution/features/tenants/presentation/edit_tenant_screen.dart';
import 'package:rent_solution/features/tenants/presentation/tenant_my_profile_screen.dart';
import 'package:rent_solution/features/tenants/presentation/tenant_profile_screen.dart';
import 'package:rent_solution/features/tenants/presentation/tenants_tab.dart';
import 'package:rent_solution/features/ocr/presentation/nid_review_screen.dart';

/// Tells go_router to re-check redirects when session state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(authStateProvider, (_, __) => notifyListeners())
      ..listen(localOrganizationProvider, (_, __) => notifyListeners())
      ..listen(memberAccessProvider, (_, __) => notifyListeners())
      ..listen(appDatabaseProvider, (_, __) => notifyListeners());
  }
}

SessionStage _stageOf(Ref ref) {
  final dbState = ref.read(appDatabaseProvider);
  if (dbState.hasError &&
      (dbState.error is DatabaseKeyMissingException || dbState.error is DatabaseKeyInvalidException)) {
    return SessionStage.recovery;
  }
  final auth = ref.read(authStateProvider);
  final org = ref.read(localOrganizationProvider);
  final access = ref.read(memberAccessProvider);
  if (auth.isLoading || org.isLoading) {
    return SessionStage.loading;
  }
  if (auth.dataOrNull == null) {
    return SessionStage.signedOut;
  }
  if (org.dataOrNull == null) {
    return SessionStage.needsOrganization;
  }
  if (access.isLoading) {
    return SessionStage.loading;
  }
  return SessionStage.ready;
}

/// The app router with sign-in, setup and role guards.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      location: state.matchedLocation,
      stage: _stageOf(ref),
      access: ref.read(memberAccessProvider).dataOrNull,
    ),
    routes: [
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: RouteNames.signIn, builder: (context, state) => const SignInScreen()),
      GoRoute(path: RouteNames.createOrganization, builder: (context, state) => const CreateOrganizationScreen()),
      GoRoute(path: RouteNames.about, builder: (context, state) => const AboutScreen()),
      GoRoute(path: RouteNames.recovery, builder: (context, state) => const RecoveryScreen()),
      GoRoute(path: RouteNames.noAccess, builder: (context, state) => const NoAccessScreen()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: RouteNames.dashboard, pageBuilder: (context, state) => const NoTransitionPage(child: DashboardTab())),
          GoRoute(
            path: RouteNames.tenants,
            pageBuilder: (context, state) => const NoTransitionPage(child: TenantsTab()),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const AddTenantScreen()),
              GoRoute(
                path: ':id',
                builder: (context, state) => TenantProfileScreen(tenantId: state.pathParameters['id']!),
                routes: [
                  GoRoute(path: 'pay', builder: (context, state) => RecordPaymentScreen(tenantId: state.pathParameters['id']!)),
                  GoRoute(path: 'scan-nid', builder: (context, state) => NidReviewScreen(tenantId: state.pathParameters['id']!, args: state.extra! as NidReviewArgs)),
                  GoRoute(path: 'edit', builder: (context, state) => EditTenantScreen(tenantId: state.pathParameters['id']!)),
                  GoRoute(path: 'charge', builder: (context, state) => AddChargeScreen(tenantId: state.pathParameters['id']!)),
                ],
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.expenses,
            builder: (context, state) => const ExpensesScreen(),
            routes: [GoRoute(path: 'new/:propertyId', builder: (context, state) => AddExpenseScreen(propertyId: state.pathParameters['propertyId']!))],
          ),
          GoRoute(
            path: RouteNames.archive,
            builder: (context, state) => const ArchiveScreen(),
            routes: [GoRoute(path: 'legal/:tenantId', builder: (context, state) => LegalScreen(tenantId: state.pathParameters['tenantId']!))],
          ),
          GoRoute(path: RouteNames.properties, builder: (context, state) => const PropertiesScreen()),
          GoRoute(path: RouteNames.payments, pageBuilder: (context, state) => const NoTransitionPage(child: PaymentsTab())),
          GoRoute(path: RouteNames.reports, pageBuilder: (context, state) => const NoTransitionPage(child: ReportsTab())),
          GoRoute(path: RouteNames.tickets, pageBuilder: (context, state) => const NoTransitionPage(child: TicketsTab())),
          GoRoute(path: RouteNames.profile, pageBuilder: (context, state) => const NoTransitionPage(child: _ProfileByRole())),
          GoRoute(
            path: RouteNames.settings,
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
            routes: [GoRoute(path: 'business', builder: (context, state) => const BusinessDetailsScreen())],
          ),
        ],
      ),
    ],
  );
});

/// Tenants get their own profile; staff get Settings (language, business details, sign out).
class _ProfileByRole extends ConsumerWidget {
  const _ProfileByRole();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(memberAccessProvider).dataOrNull;
    return access?.role == Role.tenant ? const TenantMyProfileScreen() : const SettingsScreen();
  }
}
