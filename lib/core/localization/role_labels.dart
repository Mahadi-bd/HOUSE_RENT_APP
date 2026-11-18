import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/role.dart';

/// The localized name of a role.
String roleLabel(AppLocalizations t, Role role) {
  switch (role) {
    case Role.owner:
      return t.roleOwner;
    case Role.admin:
      return t.roleAdmin;
    case Role.manager:
      return t.roleManager;
    case Role.caretaker:
      return t.roleCaretaker;
    case Role.tenant:
      return t.roleTenant;
  }
}
