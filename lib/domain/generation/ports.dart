/// Порты этапов генерации v3 (ARCH §2, ADR-050).
///
/// Этапы (`planned → understanding → generating → validating → dedup →
/// replenishing`) зависят только от этих контрактов: HTTP (Dio) живёт в
/// `lib/api/`, drift — в `lib/data/`, UI — в `lib/ui/`. В домене запрещены
/// импорты Dio, drift и Flutter (guard `test/guards/architecture_test.dart`),
/// поэтому этап нельзя «потерять» из-за транспорта или БД.
///
/// Реализации появятся в следующих срезах: `LlmPort` — срез 5 (поверх
/// `CardGenerationService`), `CardSink` — срез 8 (журнал запуска), остальные —
/// по мере подключения этапов.
library;

import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';

/// Порт вызова модели: один вызов на партию (этап Generation).
///
/// [batchIndex] — номер партии в журнале прогона ([GenerationLedger]): ответ
/// модели привязывается к партии, а не «к текущему запросу», поэтому недобор
/// считается по партиям даже после восстановления. Ошибки — `GenerationException`
/// (домен, `lib/domain/generation/generation_error.dart`): этап не видит
/// HTTP-коды и тела ответов провайдера.
abstract interface class LlmPort {
  /// Запрашивает карточки у модели по [request]; [batchIndex] — номер партии.
  Future<GenerationResult> generate(
    GenerationRequest request, {
    required int batchIndex,
  });
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
