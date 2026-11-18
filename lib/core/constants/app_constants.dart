/// App-wide constants.
abstract final class AppConstants {
  /// Android applicationId / namespace and iOS bundle id. Must match Firebase and Google OAuth.
  static const applicationId = 'com.rentsolution.app';

  /// Firebase project id.
  static const firebaseProjectId = 'rent-solution-2dd62';

  /// Language codes the app supports. English is the default.
  static const supportedLanguages = <String>['en', 'bn', 'hi'];

  /// Default language.
  static const defaultLanguage = 'en';
}
