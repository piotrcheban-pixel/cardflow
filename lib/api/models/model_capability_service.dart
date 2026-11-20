/// Сервис характеристик модели: кэш, фоновое обновление и инвалидация
/// (ADR-039 §4).
///
/// Планировщик получает лимиты **только** из кэша ([limitsFor]); сеть
/// вызывается лишь явно ([refresh]) — при сохранении аккаунта, по кнопке
/// «Обновить характеристики» или фоновом обновлении устаревшей записи.
/// Ключ API читается через `ApiKeyReader` и не покидает запрос к провайдеру.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/models/model_discovery.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_capability_discovery.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/model_limits_resolver.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';

/// Результат обновления кэша (для UI: статус, дата, источник).
final class CapabilityRefresh {
  /// Создаёт результат.
  const CapabilityRefresh({
    required this.result,
    this.record,
  });

  /// Ответ discovery.
  final DiscoveryResult result;

  /// Актуальная запись кэша (последняя удачная, даже при ошибке обновления).
  final ModelCapabilityRecord? record;
}

/// Сервис характеристик модели.
class ModelCapabilityService {
  /// Создаёт сервис.
  ModelCapabilityService({
    required this.dio,
    required this.readApiKey,
    required this.cache,
    DateTime Function()? now,
    this.discoveryOverride,
  }) : now = now ?? (() => DateTime.now().toUtc());

  /// HTTP-клиент приложения (общие таймауты, без генерации).
  final Dio dio;

  /// Чтение ключа API (present/absent).
  final ApiKeyReader readApiKey;

  /// Кэш `generation.model_capabilities`.
  final ModelCapabilityCache cache;

  /// Текущее время (инжектируется тестами).
  final DateTime Function() now;

  /// Подмена discovery (тесты без сети); `null` — выбор по протоколу.
  final ModelCapabilityDiscovery Function(ProviderAccount account)?
  discoveryOverride;

  /// Резолвер discovery по аккаунту (политика полей зависит от пресета).
  ModelCapabilityDiscovery discoveryFor(ProviderAccount account) {
    final ModelCapabilityDiscovery Function(ProviderAccount account)?
    override = discoveryOverride;
    if (override != null) return override(account);
    return discoveryForAccount(account, dio, readApiKey: readApiKey);
  }

  /// Запись кэша аккаунта/модели (без сети).
  Future<ModelCapabilityRecord?> recordFor(ProviderAccount account) =>
      cache.read(
        accountId: account.id,
        protocol: account.protocol,
        baseUrl: account.baseUrl,
        model: account.modelId,
      );

  /// Лимиты из кэша; `providerApi`-слой подмешивается к каталогу/аккаунту.
  Future<ModelLimits> limitsFor(ProviderAccount account) async {
    final ModelCapabilityRecord? record = await recordFor(account);
    final ProviderPreset? preset = account.presetId == null
        ? null
        : providerPresetById(account.presetId!);
    return resolveModelLimits(
      account: account,
      preset: preset,
      cached: record,
      now: now(),
    );
  }

  /// Обновляет характеристики через API провайдера.
  ///
  /// Ошибка **не стирает** последнее удачное значение: в запись пишется код
  /// ошибки и время попытки. Успех заменяет лимиты `providerApi` и дату
  /// проверки. Планирование этот метод не вызывает.
  Future<CapabilityRefresh> refresh(ProviderAccount account) async {
    final ModelCapabilityDiscovery discovery = discoveryFor(account);
    final DiscoveryResult result = await discovery.discover(account);
    final DateTime timestamp = now();
    final ModelCapabilityRecord? previous = await recordFor(account);
    if (result.isSuccess && result.limits != null) {
      final ModelCapabilityRecord record = ModelCapabilityRecord(
        accountId: account.id,
        protocol: account.protocol,
        baseUrl: account.baseUrl,
        model: account.modelId,
        fetchedAt: result.fetchedAt ?? timestamp,
        limits: result.limits!,
        checkedAt: _dateOf(result.fetchedAt ?? timestamp),
        sourceRef: result.sourceRef,
      );
      await cache.write(record);
      return CapabilityRefresh(result: result, record: record);
    }
    if (previous != null) {
      final ModelCapabilityRecord errored = previous.withError(
        result.errorCode ?? result.status.name,
        timestamp,
      );
      await cache.write(errored);
      return CapabilityRefresh(result: result, record: errored);
    }
    return CapabilityRefresh(result: result);
  }

  /// Инвалидирует записи аккаунта (смена ключа API — ADR-039 §4).
  Future<void> invalidateAccount(String accountId) =>
      cache.invalidateAccount(accountId);

  static String _dateOf(DateTime value) {
    final DateTime utc = value.toUtc();
    final String month = utc.month.toString().padLeft(2, '0');
    final String day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
