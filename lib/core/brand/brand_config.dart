/// PERMANENT BRANDING of Rent Solution. This is the one place where the brand lives.
/// The About screen, the footer, the receipts and the sign-in screen all read from here.
/// Users cannot edit it from the app (only business details on receipts are editable).
abstract final class BrandConfig {
  /// Brand name.
  static const companyName = 'LIFE EASY';

  /// Backward-compatible name used by the About screen.
  static const brandName = companyName;

  /// Developer and designer credit.
  static const developerName = 'MAHADI HASAN JEWEL';

  /// Same person as the owner of the business (default owner name on receipts).
  static const ownerName = developerName;

  /// Logo bundled with the app (also used on receipts unless a custom logo is set).
  static const logoAsset = 'assets/brand/life_easy_logo.png';

  /// App name shown to people.
  static const appName = 'Rent Solution';

  /// Version shown on the About screen. Keep equal to `version:` in pubspec.yaml.
  static const appVersion = '0.3.0';

  /// Licence line shown on the About screen.
  static const licenceLine = 'MIT License. Free. No ads. No subscription.';
}
