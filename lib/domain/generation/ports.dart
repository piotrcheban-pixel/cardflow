/// Порты этапов генерации v3 (ARCH §2, ADR-050).
///
/// Этапы (`planned → understanding → generating → validating → dedup →
/// replenishing`) зависят только от этих контрактов: HTTP (Dio) живёт в
/// `lib/api/`, drift — в `lib/data/`, UI — в `lib/ui/`. В домене запрещены
/// импорты Dio, drift и Flutter (guard `test/guards/architecture_test.dart`),
/// поэтому этап нельзя «потерять» из-за транспорта или БД.
///
/// Реализации: `LlmPort` — срез 5 (`AdapterCardsBatchPort` поверх существующих
/// адаптеров), `CardSink` — срез 8 (журнал запуска), остальные — по мере
/// подключения этапов.
library;

import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Порт вызова модели: один вызов на партию (этап Generation).
///
/// Партия приходит как [CardsBatch] — единицы с якорями, карточки плана и
/// принятое этого батча: ответ модели привязывается к `unit_id`, поэтому
/// недобор считается по партиям и единицам, а не «к текущему запросу».
/// Ошибки — `GenerationException` (домен,
/// `lib/domain/generation/generation_error.dart`): этап не видит HTTP-коды и
/// тела ответов провайдера.
abstract interface class LlmPort {
  /// Запрашивает карточки у модели по партии [batch].
  ///
  /// [account] — аккаунт провайдера (протокол, адрес, модель); [maxOutputTokens]
  /// — лимит ответа этой партии (`max_tokens`), `null` — лимит аккаунта.
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  });
}

/// Сигнал отмены прогона для этапов домена.
///
/// Этап не знает про Dio (`CancelToken`): он проверяет [isCancelled] между
/// запросами и прекращает работу, сохраняя принятое. Поток отправки реализация
/// порта отменяет своим транспортом.
abstract interface class CancellationSignal {
  /// true — пользователь отменил прогон.
  bool get isCancelled;
}

/// Порт записи принятых карточек (этап Persistence, инвариант ARCH §3.5).
///
/// Пишется по ходу прогона, а не после: падение процесса не должно терять
/// принятое. Повторная запись после сбоя не создаёт дубль (идемпотентность —
/// обязанность реализации, журнал запуска пишет по хешу содержимого).
abstract interface class CardSink {
  /// Записывает принятую [card] в журнал прогона партии [batchIndex].
  Future<void> save(GeneratedCard card, {required int batchIndex});
}

/// Порт прогресса прогона: этап и текущая бухгалтерия.
///
/// Этапы не знают про UI: экран получает события через адаптер и сам решает,
/// как показать этап, «принято/запрошено» и долг.
abstract interface class ProgressSink {
  /// Сообщает текущий [stage] и снимок [ledger] (значения неизменяемы).
  void report(GenerationStage stage, GenerationLedger ledger);
}

/// Порт времени: вместо `DateTime.now()` — чтобы прогон повторялся в тестах.
abstract interface class Clock {
  /// Текущий момент.
  DateTime now();
}

/// Часы production: текущее локальное время.
class SystemClock implements Clock {
  /// Создаёт часы.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Порт кэша понимания материала (этап Understanding).
///
/// Ключ — документ и хеш его содержимого: правка файла даёт новый ключ, и
/// старая карта знаний не подменяет новую. Тип карты — параметр [M]: срез 2
/// создаёт только контракт, форму `KnowledgeMap` определит этап Understanding
/// (`docs/generation/BACKLOG.md` S2), и порт не фиксирует её преждевременно.
abstract interface class KnowledgeMapCache<M> {
  /// Карта знаний документа [documentId] с содержимым [contentHash]; `null` —
  /// в кэше нет.
  Future<M?> read({required String documentId, required String contentHash});

  /// Сохраняет [map] как понимание документа [documentId] и [contentHash].
  Future<void> write({
    required String documentId,
    required String contentHash,
    required M map,
  });
}
