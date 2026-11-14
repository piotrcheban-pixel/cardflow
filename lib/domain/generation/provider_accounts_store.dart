/// Контракт хранилища настроенных провайдеров (ADR-020).
///
/// Список аккаунтов и выбранный основной живут одним значением `app_settings`
/// (ключ `generation.providers`, JSON `version=1`); ключи API — отдельно, только
/// в `ApiKeyStore` (secure storage, SPEC 3.4).
library;

import 'package:cardflow/domain/generation/provider_account.dart';

/// Хранилище провайдеров генерации.
abstract interface class ProviderAccountsStore {
  /// Читает список провайдеров; отсутствие/повреждение — пустой список
  /// (для пустого хранилища допустима миграция старых настроек).
  Future<ProviderAccounts> read();

  /// Сохраняет список провайдеров (перезапись единственной записи).
  Future<void> write(ProviderAccounts accounts);
}
