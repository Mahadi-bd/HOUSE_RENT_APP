import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/app_destinations.dart';
import 'package:rent_solution/core/routing/route_names.dart';

/// Where the person is in the sign-in and setup journey.
enum SessionStage { loading, recovery, signedOut, needsOrganization, ready }

/// Decides where to send the person. Returns null to stay on [location].
String? redirectFor({
  required String location,
  required SessionStage stage,
  MemberAccess? access,
}) {
  switch (stage) {
    case SessionStage.loading:
      return location == RouteNames.splash ? null : RouteNames.splash;
    case SessionStage.recovery:
      return location == RouteNames.recovery ? null : RouteNames.recovery;
    case SessionStage.signedOut:
      return location == RouteNames.signIn ? null : RouteNames.signIn;
    case SessionStage.needsOrganization:
      return location == RouteNames.createOrganization ? null : RouteNames.createOrganization;
    case SessionStage.ready:
      if (access == null || access.status != MemberStatus.active) {
        return location == RouteNames.noAccess ? null : RouteNames.noAccess;
      }
      const entryRoutes = {
        RouteNames.splash,
        RouteNames.signIn,
        RouteNames.createOrganization,
        RouteNames.noAccess,
        RouteNames.recovery,
      };
      if (entryRoutes.contains(location)) {
        return RouteNames.dashboard;
      }
      // Default deny: any path that is not on this role's list goes back to the dashboard.
      return canOpenPath(access, location) ? null : RouteNames.dashboard;
  }
}
