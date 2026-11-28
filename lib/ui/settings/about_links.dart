/// Данные блока «О приложении» (SPEC A6.6).
library;

/// Версия приложения для отображения (совпадает с `pubspec.yaml`; контракт
/// проверяется тестом `test/unit/ui/about_links_test.dart`).
const String appVersion = '1.0.3';

/// Публичная политика приватности (docs/privacy.md в репозитории).
///
/// Открывается системным браузером через [ExternalLinkLauncher], не WebView.
final Uri privacyPolicyUri = Uri.parse(
  'https://github.com/piotrcheban-pixel/cardflow/blob/main/docs/privacy.md',
);
