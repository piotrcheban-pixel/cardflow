/// Сообщения об ошибках генерации для UI — только строки ARB (SPEC A8.6).
///
/// Коды ошибок маппятся в русские сообщения; сырые исключения, ответы
/// провайдеров и `GenerationException.details` пользователю не показываются.
library;

import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Сообщение для кода ошибки генерации.
///
/// [retryAfter] используется для кода `rateLimited` («Повтор через N секунд»).
String generationErrorCodeMessage(
  AppLocalizations l10n,
  GenerationErrorCode code, {
  Duration? retryAfter,
}) {
  throw UnimplementedError('generationErrorCodeMessage');
}

/// Сообщение для произвольной ошибки генерации (код или общая строка ARB).
String generationErrorMessage(AppLocalizations l10n, Object error) {
  throw UnimplementedError('generationErrorMessage');
}
