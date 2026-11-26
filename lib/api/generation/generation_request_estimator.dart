/// Оценка фактически собранного запроса генерации (TASK 03, раздел 2).
///
/// Планировщик и исполнитель обязаны считать одним механизмом. Планировщик
/// оценивает бюджет фрагмента по единицам и обвязке, а перед отправкой сервис
/// собирает реальный `userContent` (материалы + пожелания + каталог + сводка
/// продолжения) и оценивает **именно его**. Оценка остаётся эвристикой
/// ([TokenValueKind.estimate]) и никогда не выдаётся за `usage` провайдера.
///
/// Схема ответа оценивается канонической проекцией ([canonicalCardsResponseSchema]):
/// адаптеры протоколов шлют свои проекции, но по объёму они близки, а
/// расхождение покрыто запасом бюджета. Это документированная аппроксимация,
/// а не «точное количество токенов».
library;

import 'dart:convert';

import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

/// Оценка одного собранного запроса: компоненты, итог и резерв вывода.
class GenerationRequestEstimate {
  /// Создаёт оценку.
  const GenerationRequestEstimate({
    required this.systemPrompt,
    required this.schema,
    required this.userContent,
    required this.images,
    required this.inputTotal,
    required this.outputReserve,
    required this.estimatorVersion,
    required this.assumptions,
  });

  /// Системный промпт.
  final TokenValue systemPrompt;

  /// Схема ответа (каноническая проекция).
  final TokenValue schema;

  /// Собранное пользовательское сообщение (материалы, пожелания, каталог,
  /// сводка продолжения, обёртка).
  final TokenValue userContent;

  /// Image-части и их подписи.
  final TokenValue images;

  /// Суммарный вход (оценка).
  final TokenValue inputTotal;

  /// Резерв вывода (`max_tokens`), отправленный в запросе.
  final TokenValue outputReserve;

  /// Версия оценщика.
  final String estimatorVersion;

  /// Поля/допущения, на которые опирается оценка (`image_tokens`, ...).
  final List<String> assumptions;

  /// true, если какая-то компонента неизвестна (в текущей реализации — нет,
  /// но контракт это допускает).
  bool get hasUnknown => !inputTotal.isKnown || !outputReserve.isKnown;

  @override
  String toString() =>
      'GenerationRequestEstimate(input: ${inputTotal.tokens ?? 'unknown'}, '
      'reserve: ${outputReserve.tokens ?? 'unknown'}, '
      'estimator: $estimatorVersion)';
}

/// Считает оценку собранного запроса тем же оценщиком единиц.
class GenerationRequestEstimator {
  /// Создаёт оценщик; по умолчанию — production-промпт и каноническая схема.
  const GenerationRequestEstimator({
    this.estimator = const HeuristicContentTokenEstimator(),
    this.systemPrompt = systemPromptGenRuV9,
    this.responseSchema = canonicalCardsResponseSchema,
  });

  /// Оценщик единиц (тот же, что у плана).
  final ContentTokenEstimator estimator;

  /// Системный промпт запроса.
  final String systemPrompt;

  /// Каноническая схема ответа.
  final Map<String, Object?> responseSchema;

  /// Оценивает собранный запрос.
  ///
  /// [userContent] — готовое сообщение пользователя; [attachments] — image-части
  /// (включая вложения пользователя и изображения документов); [maxOutputTokens]
  /// — резерв вывода, который реально уйдёт в запрос; [unknownFields] —
  /// неизвестные возможности модели (для диагностики, не для арифметики).
  GenerationRequestEstimate estimate({
    required String userContent,
    required List<GenerationAttachment> attachments,
    required int maxOutputTokens,
    List<String> unknownFields = const <String>[],
  }) {
    final String version = '${estimator.version}/request-1';
    final TokenValue system = TokenValue.estimate(
      estimator.estimateText(systemPrompt),
      source: version,
    );
    final TokenValue schema = TokenValue.estimate(
      estimator.estimateText(jsonEncode(responseSchema)),
      source: version,
    );
    final TokenValue user = TokenValue.estimate(
      estimator.estimateText(userContent),
      source: version,
    );

    var imageTokens = 0;
    var imageAssumption = false;
    for (final GenerationAttachment attachment in attachments) {
      final ImageTokenEstimate estimate = estimator.estimateImage(
        bytes: attachment.bytes.length,
      );
      imageTokens += estimate.tokens;
      imageAssumption = imageAssumption || estimate.isAssumption;
      final String? label = attachment.label;
      if (label != null && label.isNotEmpty) {
        imageTokens += estimator.estimateText(label);
      }
    }
    final TokenValue images;
    if (attachments.isEmpty) {
      images = const TokenValue.exact(0, source: 'no-image-parts');
    } else {
      images = TokenValue.estimate(imageTokens, source: version);
    }

    final TokenValue inputTotal = TokenValue.sum(<TokenValue>[
      system,
      schema,
      user,
      images,
    ], source: 'sum(system,schema,user,images)');
    final List<String> assumptions = <String>[
      for (final String field in unknownFields)
        if (field.isNotEmpty) field,
      if (imageAssumption && attachments.isNotEmpty) 'image_tokens',
    ];
    return GenerationRequestEstimate(
      systemPrompt: system,
      schema: schema,
      userContent: user,
      images: images,
      inputTotal: inputTotal,
      outputReserve: TokenValue.reserve(
        maxOutputTokens,
        source: 'request.maxOutputTokens',
      ),
      estimatorVersion: version,
      assumptions: List<String>.unmodifiable(assumptions),
    );
  }
}
