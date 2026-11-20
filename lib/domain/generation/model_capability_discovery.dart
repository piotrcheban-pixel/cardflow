/// Порт discovery характеристик модели (ADR-039 §3).
///
/// Discovery получает лимиты от API провайдера, но **никогда** не вызывается
/// при построении плана: план читает только кэш. Домен не зависит от Flutter,
/// Dio и secure storage — реализация живёт в `lib/api/models/`.
library;

import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Статус попытки discovery.
enum DiscoveryStatus {
  /// Ответ получен и разобран.
  success,

  /// 401/403 — ключ не принят (или отсутствует).
  unauthorized,

  /// 404 — эндпоинт/модель не найдены.
  notFound,

  /// Таймаут/сеть.
  timeout,

  /// Протокол не поддерживает discovery (generic compatible и т.п.).
  unsupported,

  /// Прочий ответ/ошибка разбора.
  error,
}

/// Результат discovery: лимиты со источником `providerApi` и метаданные.
final class DiscoveryResult {
  /// Создаёт результат.
  const DiscoveryResult({
    required this.status,
    required this.accountId,
    required this.model,
    this.limits,
    this.models = const <String>[],
    this.errorCode,
    this.warnings = const <String>[],
    this.fetchedAt,
    this.sourceRef,
  });

  /// Неуспешная попытка без сети (например, протокол не поддерживается).
  factory DiscoveryResult.unsupported({
    required String accountId,
    required String model,
    String? sourceRef,
  }) => DiscoveryResult(
    status: DiscoveryStatus.unsupported,
    accountId: accountId,
    model: model,
    sourceRef: sourceRef,
  );

  /// Статус.
  final DiscoveryStatus status;

  /// id аккаунта (ключ кэша).
  final String accountId;

  /// Модель, для которой запрошены характеристики.
  final String model;

  /// Разобранные лимиты (только подтверждённые поля, source = providerApi).
  final ModelLimits? limits;

  /// Список id моделей, которые вернул провайдер (если есть).
  final List<String> models;

  /// Машинный код ошибки (`unauthorized`, `timeout`, …) — не тело ответа.
  final String? errorCode;

  /// Предупреждения (например, `ollama_num_ctx_assumption`).
  final List<String> warnings;

  /// Когда получено (для `providerApi`).
  final DateTime? fetchedAt;

  /// URL эндпоинта без query-параметров.
  final String? sourceRef;

  /// true, если ответ успешно разобран.
  bool get isSuccess => status == DiscoveryStatus.success;

  /// true, если ошибка не должна стирать последнее удачное значение.
  bool get keepsPrevious => status != DiscoveryStatus.success;

  @override
  String toString() =>
      'DiscoveryResult(${status.name}, $model, models: ${models.length})';
}

/// Порт discovery: реализация на каждый протокол/провайдера.
abstract interface class ModelCapabilityDiscovery {
  /// Запрашивает характеристики [account].
  ///
  /// Реализация не вызывает генерацию и не пишет ключи в логи/ошибки; при
  /// ошибке возвращает [DiscoveryResult] с машинным кодом, а не исключение
  /// (кроме отмены).
  Future<DiscoveryResult> discover(ProviderAccount account);
}
