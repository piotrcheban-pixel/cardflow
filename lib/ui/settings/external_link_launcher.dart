/// Открытие внешних ссылок системным браузером (SPEC 3.3, A6.6 «О приложении»).
///
/// Это не WebView: `url_launcher` передаёт адрес системе. Порт инжектируется,
/// чтобы widget-тесты не открывали браузер и проверяли переданный URL.
library;

import 'package:url_launcher/url_launcher.dart';

/// Порт запуска внешней ссылки.
abstract interface class ExternalLinkLauncher {
  /// Открывает [uri]; `false` — не удалось.
  Future<bool> open(Uri uri);
}

/// Реализация поверх `url_launcher`.
class UrlLauncherExternalLinkLauncher implements ExternalLinkLauncher {
  /// Создаёт лаунчер.
  const UrlLauncherExternalLinkLauncher();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
