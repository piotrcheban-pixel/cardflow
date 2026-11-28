/// Реализация [LlmPort] поверх существующих адаптеров провайдеров (срез 5).
///
/// Адаптеры (`lib/api/providers/`) не переписываются: порт строит запрос тем же
/// `buildRequest`, отправляет его существующим `GenerationTransport` и
/// нормализует исход в [ProviderResult]. Промпт — `gen-cards-v3`
/// (`lib/api/prompts/cards_prompt.dart`): вход — единицы с якорями, выход —
/// карточки с `unit_id`, `angle`, `quote_ref`.
///
/// Ошибки провайдера/транспорта пробрасываются `GenerationException`: решение
/// о повторе (429 `Retry-After`, 5xx) принимает движок по коду ошибки, поэтому
/// повторы видны в журнале прогона, а не внутри транспорта.
library;

import 'package:json_schema/json_schema.dart';

import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/api/generation/provider_result.dart';
import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/schema_compat_profile.dart';

/// Порт вызова модели поверх адаптеров провайдеров.
class AdapterCardsBatchPort implements LlmPort {
  /// Создаёт порт.
  ///
  /// [transport] — существующий HTTP-транспорт генерации (таймауты, отмена,
  /// редактирование логов); [apiKeyStore] — ключи аккаунтов (значение в логи
  /// не попадает); [adapters] — production-набор `generationAdapters`.
  AdapterCardsBatchPort({
    required this.transport,
    required this.apiKeyStore,
    this.adapters = generationAdapters,
    this.normalizer = const ProviderResponseNormalizer(),
    this.extractor = const CardsJsonExtractor(),
    this.tolerant = true,
    SchemaCompatProfile? compat,
  }) : compat = compat ?? SchemaCompatProfile();

  /// Транспорт запросов провайдера.
  final GenerationTransport transport;

  /// Хранилище ключей API по аккаунтам.
  final ApiKeyStore apiKeyStore;

  /// Адаптеры провайдеров.
  final List<GenerationProviderAdapter> adapters;

  /// Нормализация ответа адаптера в единый [ProviderResult].
  final ProviderResponseNormalizer normalizer;

  /// Извлекатель JSON из текста ответа.
  final CardsJsonExtractor extractor;

  /// Разрешать markdown-ограждение вокруг JSON (OpenAI-совместимые серверы).
  final bool tolerant;

  /// Память о совместимости провайдера со strict-схемой (срез 13, часть 2).
  ///
  /// Один экземпляр на прогон (общий с Understanding): первая `400` на strict
  /// запоминается, и следующие батчи идут сразу без схемы — лестница ADR-021
  /// перестаёт быть двухступенчатой на каждом запросе.
  final SchemaCompatProfile compat;

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    final GenerationProviderAdapter adapter = adapterFor(account.protocol);
    final String apiKey = await apiKeyStore.read(account.id) ?? '';
    final int outputTokens =
        maxOutputTokens ?? batch.budget * kDefaultOutputTokensPerCard;
    // Лестница совместимости ADR-021 — та же, что в `CardGenerationService`:
    // strict `json_schema` → без схемы → без схемы и `max_tokens`. Только
    // `badRequest`, не больше трёх запросов; нативные протоколы — один.
    final bool tolerantFallback =
        account.protocol == ProviderProtocol.openaiCompletions;
    final bool strictKnownRejected =
        tolerantFallback &&
        compat.isRejected(
          provider: account.protocol.name,
          model: account.modelId,
          schema: cardsPromptVersion,
          rung: SchemaCompatRung.strictSchema,
        );
    final List<({bool strictSchema, bool sendMaxTokens})> attempts =
        <({bool strictSchema, bool sendMaxTokens})>[
          if (!strictKnownRejected) (strictSchema: true, sendMaxTokens: true),
          if (tolerantFallback) (strictSchema: false, sendMaxTokens: true),
          if (tolerantFallback) (strictSchema: false, sendMaxTokens: false),
        ];
    Map<String, Object?>? json;
    GenerationException? lastError;
    for (final ({bool strictSchema, bool sendMaxTokens}) attempt in attempts) {
      final ProviderRequest request = adapter.buildRequest(
        apiKey: apiKey,
        model: account.modelId,
        systemPrompt: cardsSystemPromptGenCardsV3,
        userContent: buildCardsUserContent(batch),
        maxOutputTokens: outputTokens,
        baseUrl: account.baseUrl,
        strictSchema: attempt.strictSchema,
        sendMaxTokens: attempt.sendMaxTokens,
        responseSchema: cardSchemaV3For(_flavorOf(account.protocol)),
      );
      try {
        json = await transport.postJson(request);
        break;
      } on GenerationException catch (error) {
        lastError = error;
        if (tolerantFallback && error.code == GenerationErrorCode.badRequest) {
          if (attempt.strictSchema) {
            // Проба strict-схемы — один раз на прогон, а не на батч (срез 13).
            compat.rememberRejected(
              provider: account.protocol.name,
              model: account.modelId,
              schema: cardsPromptVersion,
              rung: SchemaCompatRung.strictSchema,
            );
          }
          continue;
        }
        rethrow;
      }
    }
    if (json == null) throw lastError!;
    final ProviderResult normalized = normalizer.normalize(adapter, json);

    if (normalized.isTruncated) {
      return _truncatedResult(batch, account, adapter, normalized);
    }
    if (normalized.isError) {
      throw GenerationException(
        normalized.rawError ?? GenerationErrorCode.invalidResponse,
        details: normalized.detail,
      );
    }

    final CardResponseSchema schema = _v3Schema();
    final Object? decoded = extractor.decode(
      normalized.content,
      tolerant:
          tolerant && account.protocol == ProviderProtocol.openaiCompletions,
    );
    final CardPayloadValidation validation = schema.splitValid(decoded);
    if (validation.rootInvalid) {
      throw const GenerationException(
        GenerationErrorCode.invalidResponse,
        details: 'Ответ модели не по схеме карточек gen-cards-v3',
      );
    }

    final List<GeneratedCard> cards = <GeneratedCard>[];
    var rejected = validation.rejectedCards;
    for (final Map<String, Object?> raw in validation.cards) {
      final GeneratedCard? card = _cardOf(raw);
      if (card == null) {
        rejected++;
      } else {
        cards.add(card);
      }
    }
    return _result(
      account: account,
      adapter: adapter,
      cards: cards,
      rejectedCards: rejected,
      usage: normalized.usage,
      truncated: false,
      salvagedCards: 0,
    );
  }

  /// Адаптер протокола аккаунта.
  GenerationProviderAdapter adapterFor(ProviderProtocol protocol) {
    final GenerationProvider provider = protocol.adapterProvider;
    for (final GenerationProviderAdapter adapter in adapters) {
      if (adapter.provider == provider) return adapter;
    }
    throw ArgumentError.value(
      provider,
      'protocol',
      'Нет адаптера для протокола провайдера',
    );
  }

  /// Ответ оборван по лимиту вывода: спасаем **полные** карточки, остальное —
  /// следующий запрос по остатку единиц (деление делает движок).
  GenerationResult _truncatedResult(
    CardsBatch batch,
    ProviderAccount account,
    GenerationProviderAdapter adapter,
    ProviderResult normalized,
  ) {
    final CardResponseSchema schema = _v3Schema();
    final List<GeneratedCard> cards = <GeneratedCard>[];
    var rejected = 0;
    for (final Map<String, Object?> raw in extractor.salvageCards(
      normalized.content,
    )) {
      if (!schema.cardSchema.validate(raw).isValid) {
        rejected++;
        continue;
      }
      final GeneratedCard? card = _cardOf(raw);
      if (card == null) {
        rejected++;
      } else {
        cards.add(card);
      }
    }
    return _result(
      account: account,
      adapter: adapter,
      cards: cards,
      rejectedCards: rejected,
      usage: normalized.usage,
      truncated: true,
      salvagedCards: cards.length,
    );
  }

  GenerationResult _result({
    required ProviderAccount account,
    required GenerationProviderAdapter adapter,
    required List<GeneratedCard> cards,
    required int rejectedCards,
    required TokenUsage usage,
    required bool truncated,
    required int salvagedCards,
  }) => GenerationResult(
    provider: adapter.provider,
    model: account.modelId,
    promptVersion: cardsPromptVersion,
    cards: List<GeneratedCard>.unmodifiable(cards),
    usage: usage,
    rejectedCards: rejectedCards,
    truncated: truncated,
    salvagedCards: salvagedCards,
  );

  /// Локальная схема ответа `gen-cards-v3` (корень и карточка).
  static CardResponseSchema _v3Schema() => CardResponseSchema(
    schema: JsonSchema.create(cardsResponseSchemaV3()),
    cardSchema: JsonSchema.create(localCardV3ItemSchema()),
  );

  /// Карточка ответа в доменный тип; `null` — карточка непригодна.
  ///
  /// `unit_id`, `angle` и `quote_ref` обязательны: карточка без привязки к
  /// единице не восстанавливает цитату и не идёт в принятые (TASK «Срез 5»).
  static GeneratedCard? _cardOf(Map<String, Object?> raw) {
    final Object? rawFront = raw['front'];
    final Object? rawBack = raw['back'];
    final Object? rawType = raw['card_type'];
    final Object? rawUnit = raw['unit_id'];
    final Object? rawAngle = raw['angle'];
    final Object? rawQuote = raw['quote_ref'];
    if (rawFront is! String ||
        rawFront.trim().isEmpty ||
        rawBack is! String ||
        rawType is! String ||
        rawUnit is! String ||
        rawUnit.trim().isEmpty ||
        rawAngle is! String ||
        rawQuote is! String ||
        rawQuote.trim().isEmpty) {
      return null;
    }
    final ({bool valid, String? angle}) angle = _angleOf(rawAngle);
    if (!angle.valid) return null;
    final CardType cardType;
    if (rawType == 'occlusion') {
      // SPEC A5: occlusion — разметка внутри basic, а не тип карточки.
      cardType = CardType.basic;
    } else {
      try {
        cardType = CardType.fromWire(rawType);
      } on FormatException {
        return null;
      }
    }
    final Object? rawTags = raw['tags'];
    final List<String> tags = <String>[
      if (rawTags is List)
        for (final Object? tag in rawTags)
          if (tag is String && tag.trim().isNotEmpty) tag.trim(),
    ];
    final Object? rawHint = raw['hint'];
    final Object? rawExcerpt = raw['source_excerpt'];
    final Object? rawSourceFile = raw['source_file'];
    final Object? rawSection = raw['section_id'];
    return GeneratedCard(
      front: rawFront,
      back: rawBack,
      cardType: cardType,
      hint: rawHint is String && rawHint.trim().isNotEmpty
          ? rawHint.trim()
          : null,
      tags: List<String>.unmodifiable(tags),
      sourceExcerpt: rawExcerpt is String && rawExcerpt.trim().isNotEmpty
          ? rawExcerpt.trim()
          : null,
      sourceFile: rawSourceFile is String && rawSourceFile.trim().isNotEmpty
          ? rawSourceFile.trim()
          : null,
      sectionId: rawSection is String && rawSection.trim().isNotEmpty
          ? rawSection.trim()
          : null,
      unitId: rawUnit.trim(),
      angle: angle.angle,
      quoteRef: rawQuote.trim(),
    );
  }

  /// Угол карточки: `primary` — основная (`angle == null`), остальные — как в
  /// плане; неизвестное значение делает карточку непригодной.
  static ({bool valid, String? angle}) _angleOf(String wire) {
    if (wire == 'primary') return (valid: true, angle: null);
    if (kCardAngleWires.contains(wire)) return (valid: true, angle: wire);
    return (valid: false, angle: null);
  }

  /// Проекция схемы под протокол аккаунта.
  static ProviderSchemaFlavor _flavorOf(ProviderProtocol protocol) =>
      switch (protocol) {
        ProviderProtocol.openai ||
        ProviderProtocol.openaiCompletions => ProviderSchemaFlavor.openAi,
        ProviderProtocol.geminiGenerateContent => ProviderSchemaFlavor.gemini,
        ProviderProtocol.anthropicMessages => ProviderSchemaFlavor.anthropic,
      };
}
