/// All route paths in one place (no magic strings).
abstract final class RouteNames {
  /// Shown while the app decides where to go.
  static const splash = '/splash';

  /// Sign-in screen.
  static const signIn = '/sign-in';

  /// First-time business setup.
  static const createOrganization = '/setup';

  /// Shown when a member is suspended or revoked.
  static const noAccess = '/no-access';

  /// Dashboard (Home for tenants).
  static const dashboard = '/dashboard';

  /// Tenants tab.
  static const tenants = '/tenants';

  /// Payments tab (My Payments for tenants).
  static const payments = '/payments';

  /// Reports tab.
  static const reports = '/reports';

  /// Tickets tab (My Tickets for tenants).
  static const tickets = '/tickets';

  /// Settings tab.
  static const settings = '/settings';

  /// Profile (a tab for tenants; reachable from the top bar for caretakers).
  static const profile = '/profile';

  /// Properties and units.
  static const properties = '/properties';

  /// Shown when the local database key is missing or wrong.
  static const recovery = '/recovery';

  /// Expenses.
  static const expenses = '/expenses';

  /// Business details printed on receipts.
  static const business = '/settings/business';

  /// About: permanent brand and developer credit.
  static const about = '/about';

  /// About: the permanent brand and developer credit.
  static const about = '/about';
}
