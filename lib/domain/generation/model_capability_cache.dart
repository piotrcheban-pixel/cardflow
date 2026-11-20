/// Кэш характеристик модели (`generation.model_capabilities` v1, ADR-039 §4).
///
/// Кэш живёт в `app_settings` (схема БД и `schemaVersion` не меняются) и
/// хранит только лимиты/возможности с происхождением — **без ключей API**, их
/// хэшей и тел запросов. Ключ записи —
/// `accountId + protocol + нормализованный baseUrl + modelId`.
/// Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Сколько живёт запись до принудительного обновления.
const Duration kModelCapabilityTtl = Duration(days: 7);

/// Нормализует базовый адрес для ключа кэша (без query/fragment).
///
/// Схема и хост — в нижнем регистре, хвостовой `/` убирается; путь сохраняется
/// (важен для `/v1`). Query-параметры отбрасываются: в них бывают ключи.
String normalizeCapabilityBaseUrl(String baseUrl) {
  final Uri? uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }
  final String path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
      '${uri.hasPort && uri.port != 0 ? ':${uri.port}' : ''}$path';
}

/// Одна запись кэша характеристик.
final class ModelCapabilityRecord {
  /// Создаёт запись.
  const ModelCapabilityRecord({
    required this.accountId,
    required this.protocol,
    required this.baseUrl,
    required this.model,
    required this.fetchedAt,
    required this.limits,
    this.checkedAt,
    this.sourceRef,
    this.lastErrorCode,
    this.lastAttemptAt,
  });

  /// id аккаунта.
  final String accountId;

  /// Протокол аккаунта.
  final ProviderProtocol protocol;

  /// Базовый адрес аккаунта (нормализуется при ключе).
  final String baseUrl;

  /// id модели.
  final String model;

  /// Когда успешно получены характеристики.
  final DateTime fetchedAt;

  /// Лимиты с источником `providerApi`.
  final ModelLimits limits;

  /// Дата проверки (YYYY-MM-DD, для UI).
  final String? checkedAt;

  /// URL эндпоинта без query-параметров.
  final String? sourceRef;

  /// Код последней ошибки обновления (значение при этом сохраняется).
  final String? lastErrorCode;

  /// Когда была последняя попытка обновления.
  final DateTime? lastAttemptAt;

  /// Ключ записи.
  String get key =>
      '${accountId.trim().toLowerCase()}|${protocol.wireName}'
      '|${normalizeCapabilityBaseUrl(baseUrl)}|${model.trim().toLowerCase()}';

  /// true, если запись моложе [ttl] (по умолчанию 7 дней).
  bool isFresh(DateTime now, {Duration ttl = kModelCapabilityTtl}) =>
      now.difference(fetchedAt) < ttl;

  /// Копия с ошибкой обновления (последнее удачное значение сохраняется).
  ModelCapabilityRecord withError(String code, DateTime at) =>
      ModelCapabilityRecord(
        accountId: accountId,
        protocol: protocol,
        baseUrl: baseUrl,
        model: model,
        fetchedAt: fetchedAt,
        limits: limits,
        checkedAt: checkedAt,
        sourceRef: sourceRef,
        lastErrorCode: code,
        lastAttemptAt: at,
      );

  /// JSON-представление (без ключей и тел).
  Map<String, Object?> toJson() => <String, Object?>{
    'account_id': accountId,
    'protocol': protocol.wireName,
    'base_url': normalizeCapabilityBaseUrl(baseUrl),
    'model': model,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    if (checkedAt != null) 'checked_at': checkedAt,
    if (sourceRef != null) 'source_ref': sourceRef,
    'limits': modelLimitsToJson(limits),
    if (lastErrorCode != null) 'last_error_code': lastErrorCode,
    if (lastAttemptAt != null)
      'last_attempt_at': lastAttemptAt!.toUtc().toIso8601String(),
  };

  /// Разбирает запись; `null` — запись повреждена и пропускается.
  static ModelCapabilityRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['account_id'];
    final Object? model = json['model'];
    final Object? base = json['base_url'];
    if (id is! String || model is! String || base is! String) return null;
    ProviderProtocol? protocol;
    for (final ProviderProtocol value in ProviderProtocol.values) {
      if (value.wireName == json['protocol']) protocol = value;
    }
    final DateTime? fetched = DateTime.tryParse(
      json['fetched_at'] is String ? json['fetched_at']! as String : '',
    );
    if (protocol == null || fetched == null) return null;
    final Object? checked = json['checked_at'];
    final Object? sourceRef = json['source_ref'];
    final Object? errorCode = json['last_error_code'];
    final DateTime? attempt = DateTime.tryParse(
      json['last_attempt_at'] is String
          ? json['last_attempt_at']! as String
          : '',
    );
    return ModelCapabilityRecord(
      accountId: id,
      protocol: protocol,
      baseUrl: base,
      model: model,
      fetchedAt: fetched.toUtc(),
      limits: modelLimitsFromJson(json['limits']),
      checkedAt: checked is String ? checked : null,
      sourceRef: sourceRef is String ? sourceRef : null,
      lastErrorCode: errorCode is String ? errorCode : null,
      lastAttemptAt: attempt?.toUtc(),
    );
  }

  @override
  String toString() =>
      'ModelCapabilityRecord($accountId/$model, ${fetchedAt.toIso8601String()})';
}

/// Порт кэша характеристик.
abstract interface class ModelCapabilityCache {
  /// Все записи (для фонового обновления/UI).
  Future<List<ModelCapabilityRecord>> readAll();

  /// Запись для аккаунта/модели.
  Future<ModelCapabilityRecord?> read({
    required String accountId,
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  });

  /// Пишет запись (upsert по ключу).
  Future<void> write(ModelCapabilityRecord record);

  /// Инвалидирует все записи аккаунта (например, после смены ключа).
  Future<void> invalidateAccount(String accountId);
}
