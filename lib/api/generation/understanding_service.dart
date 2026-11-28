/// Этап Understanding: карта знаний документа (TASK «Срез 3», ADR-050).
///
/// Фрагмент понимания — раздел `ContentModel`: содержательные блоки раздела
/// уходят в запрос, ответ модели разбирается [KnowledgeMapParser], а карта
/// документа кэшируется по паре «документ + хеш содержимого и версии промпта».
/// Невалидный ответ помечает фрагмент и не останавливает прогон (Q9);
/// отмена пробрасывается наружу.
///
/// Токены не оцениваются: `usage` берётся только из фактических ответов модели,
/// а неизвестное слагаемое делает сумму неизвестной, а не нулевой.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/knowledge_map_parser.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';

/// Статус обработки фрагмента.
enum KnowledgeMapFragmentStatus {
  /// Модель вернула единицы.
  understood,

  /// Ответ валиден, но единиц нет (`{"units": []}`) — не сбой.
  empty,

  /// Фрагмент помечен: ответ непригоден (Q9).
  failed,
}

/// Итог обработки одного фрагмента.
class KnowledgeMapFragmentOutcome {
  const KnowledgeMapFragmentOutcome._({
    required this.fragmentId,
    required this.status,
    this.unitCount = 0,
    this.rejectedUnits = 0,
    this.failureReason,
  });

  /// Фрагмент понят; [unitCount] единиц принято (0 — статус `empty`).
  factory KnowledgeMapFragmentOutcome.understood({
    required String fragmentId,
    required int unitCount,
    int rejectedUnits = 0,
  }) => KnowledgeMapFragmentOutcome._(
    fragmentId: fragmentId,
    status: unitCount == 0
        ? KnowledgeMapFragmentStatus.empty
        : KnowledgeMapFragmentStatus.understood,
    unitCount: unitCount,
    rejectedUnits: rejectedUnits,
  );

  /// Фрагмент помечен [reason] и пропущен.
  factory KnowledgeMapFragmentOutcome.failed({
    required String fragmentId,
    required KnowledgeMapFailureReason reason,
  }) => KnowledgeMapFragmentOutcome._(
    fragmentId: fragmentId,
    status: KnowledgeMapFragmentStatus.failed,
    failureReason: reason,
  );

  /// id фрагмента.
  final String fragmentId;

  /// Статус фрагмента.
  final KnowledgeMapFragmentStatus status;

  /// Сколько единиц принято из этого фрагмента.
  final int unitCount;

  /// Сколько единиц отброшено поштучно.
  final int rejectedUnits;

  /// Причина пометки; `null` — фрагмент обработан.
  final KnowledgeMapFailureReason? failureReason;

  /// true, если фрагмент помечен как невалидный.
  bool get isFailed => status == KnowledgeMapFragmentStatus.failed;

  @override
  String toString() =>
      'KnowledgeMapFragmentOutcome($fragmentId, ${status.name}'
      '${failureReason == null ? '' : ': ${failureReason!.code}'})';
}

/// Результат понимания документа: карта, статусы фрагментов и факт `usage`.
class UnderstandingResult {
  /// Создаёт результат.
  const UnderstandingResult({
    required this.map,
    this.fragments = const <KnowledgeMapFragmentOutcome>[],
    this.usage = const TokenUsage(),
    this.fromCache = false,
  });

  /// Карта знаний документа (только успешные фрагменты).
  final KnowledgeMap map;

  /// Статусы фрагментов в порядке документа (пусто при попадании в кэш).
  final List<KnowledgeMapFragmentOutcome> fragments;

  /// Суммарный фактический `usage` ответов; неизвестное слагаемое — `null`.
  final TokenUsage usage;

  /// true — карта взята из кэша, вызовов модели не было.
  final bool fromCache;

  /// true, если хотя бы один фрагмент помечен.
  bool get hasFailures =>
      fragments.any((KnowledgeMapFragmentOutcome outcome) => outcome.isFailed);

  /// Помеченные фрагменты.
  List<KnowledgeMapFragmentOutcome> get failures => fragments
      .where((KnowledgeMapFragmentOutcome outcome) => outcome.isFailed)
      .toList(growable: false);

  /// Число единиц в карте.
  int get unitCount => map.length;

  /// Сколько единиц отброшено поштучно во всех фрагментах.
  int get rejectedUnits => fragments.fold(
    0,
    (int sum, KnowledgeMapFragmentOutcome outcome) =>
        sum + outcome.rejectedUnits,
  );
}

/// Оценка вывода одного пункта карты (утверждение, якоря, JSON-обвязка).
///
/// По этой оценке Understanding делит обрезанный ответ на части **целыми
/// блоками раздела** в пределах `max_tokens`, а не пополам (TASK «Срез 11»,
/// п. 5): деление задаёт лимит вывода, а не длина фрагмента.
const int kTokensPerMapUnit = 96;

/// Сколько блоков раздела просить в одном запросе при лимите [maxOutputTokens].
int blocksPerMapRequest(int maxOutputTokens) =>
    math.max(1, maxOutputTokens ~/ kTokensPerMapUnit);

/// Глубина деления обрезанного фрагмента (защита от бесконечной рекурсии).
const int maxUnderstandingSplits = 8;

/// Лимит вывода запроса Understanding по умолчанию (`max_tokens`).
const int kDefaultMapOutputTokens = 4096;

/// Сервис этапа Understanding.
class UnderstandingService {
  /// Создаёт сервис; [tolerant] — разрешить markdown-ограждение вокруг JSON.
  const UnderstandingService({
    required this.caller,
    required this.cache,
    this.parser = const KnowledgeMapParser(),
    this.tolerant = false,
    this.maxOutputTokens = kDefaultMapOutputTokens,
  });

  /// Лимит вывода одного запроса (`max_tokens`).
  ///
  /// Он же задаёт размер частей при делении обрезанного ответа: части — целые
  /// блоки раздела, сколько их влезает в лимит ([blocksPerMapRequest]).
  final int maxOutputTokens;

  /// Вызов модели на понимание фрагмента.
  final KnowledgeMapCaller caller;

  /// Кэш карт: документ + хеш содержимого и версии промпта.
  final KnowledgeMapCache<KnowledgeMap> cache;

  /// Разбор ответа модели.
  final KnowledgeMapParser parser;

  /// Разрешать markdown-ограждение и текст вокруг JSON.
  final bool tolerant;

  /// Строит карту знаний документа (или отдаёт её из кэша).
  ///
  /// Запросы идут последовательно (SPEC A8.5 шаг 6: без параллельных запросов
  /// к провайдеру). Карта кэшируется только когда все фрагменты обработаны:
  /// иначе повторный прогон «запомнил» бы недобор как готовый результат.
  Future<UnderstandingResult> build(Document document) async {
    final List<Section> sections = <Section>[
      for (final Section section in document.sections)
        if (_contentBlocks(document, section).isNotEmpty) section,
    ];
    if (sections.isEmpty) {
      return UnderstandingResult(map: KnowledgeMap(documentId: document.id));
    }

    final String contentHash = _contentHash(document.text);
    final KnowledgeMap? cached = await cache.read(
      documentId: document.id,
      contentHash: contentHash,
    );
    if (cached != null) {
      return UnderstandingResult(map: cached, fromCache: true);
    }

    final Set<String> sectionIds = <String>{
      for (final Section section in document.sections) section.id,
    };
    final List<KnowledgeUnit> units = <KnowledgeUnit>[];
    final List<KnowledgeMapFragmentOutcome> outcomes =
        <KnowledgeMapFragmentOutcome>[];
    final List<TokenUsage> usages = <TokenUsage>[];

    for (final Section section in sections) {
      final List<Block> blocks = _contentBlocks(document, section);
      final _FragmentOutcome fragment = await _extract(
        fragmentId: section.id,
        sectionId: section.id,
        sectionTitle: section.title,
        blocks: blocks,
        sectionIds: sectionIds,
        usages: usages,
      );
      units.addAll(fragment.units);
      outcomes.add(fragment.toPublic(section.id));
    }

    final KnowledgeMap map = KnowledgeMap(
      documentId: document.id,
      units: units,
    );
    final bool complete = outcomes.every(
      (KnowledgeMapFragmentOutcome outcome) => !outcome.isFailed,
    );
    if (complete) {
      await cache.write(
        documentId: document.id,
        contentHash: contentHash,
        map: map,
      );
    }
    return UnderstandingResult(
      map: map,
      fragments: List<KnowledgeMapFragmentOutcome>.unmodifiable(outcomes),
      usage: _sumUsage(usages),
    );
  }

  /// Понимание одного фрагмента (или его частей после обрезки по `max_tokens`).
  ///
  /// Обрезанный ответ не теряет раздел целиком: блоки делятся на части по
  /// [blocksPerMapRequest] (сколько пунктов карты влезает в лимит вывода), а не
  /// пополам, и каждая часть запрашивается отдельно. Часть, обрезанная снова, —
  /// помеченный фрагмент (`truncated`), как в срезе 3: прогон продолжается.
  Future<_FragmentOutcome> _extract({
    required String fragmentId,
    required String sectionId,
    required String? sectionTitle,
    required List<Block> blocks,
    required Set<String> sectionIds,
    required List<TokenUsage> usages,
    int depth = 0,
  }) async {
    final KnowledgeMapRequest request = KnowledgeMapRequest(
      fragmentId: fragmentId,
      sectionId: sectionId,
      promptVersion: understandingPromptVersion,
      systemPrompt: understandingSystemPromptGenMapV1,
      userContent: buildUnderstandingUserContent(
        sectionId: sectionId,
        sectionTitle: sectionTitle,
        blocks: blocks,
      ),
      maxOutputTokens: maxOutputTokens,
    );

    final KnowledgeMapRawResponse response;
    try {
      response = await caller.extract(request);
    } on GenerationException catch (error) {
      if (error.code == GenerationErrorCode.cancelled) rethrow;
      return const _FragmentOutcome(
        failureReason: KnowledgeMapFailureReason.providerError,
      );
    }

    usages.add(response.usage);
    if (response.truncated) {
      final int perPart = blocksPerMapRequest(maxOutputTokens);
      if (blocks.length <= perPart || depth >= maxUnderstandingSplits) {
        return const _FragmentOutcome(
          failureReason: KnowledgeMapFailureReason.truncated,
        );
      }
      final List<_FragmentOutcome> parts = <_FragmentOutcome>[];
      var partIndex = 0;
      for (var start = 0; start < blocks.length; start += perPart) {
        partIndex++;
        final int end = math.min(start + perPart, blocks.length);
        parts.add(
          await _extract(
            fragmentId: '$fragmentId#$partIndex',
            sectionId: sectionId,
            sectionTitle: sectionTitle,
            blocks: blocks.sublist(start, end),
            sectionIds: sectionIds,
            usages: usages,
            depth: depth + 1,
          ),
        );
      }
      return _FragmentOutcome.merged(parts);
    }

    final KnowledgeMapParseOutcome parsed = parser.parse(
      response.json,
      context: KnowledgeMapFragmentContext(
        fragmentId: fragmentId,
        sectionId: sectionId,
        blockIds: <String>{for (final Block block in blocks) block.id},
        sectionIds: sectionIds,
      ),
      tolerant: tolerant,
    );
    if (!parsed.isSuccess) {
      return _FragmentOutcome(failureReason: parsed.failureReason!);
    }
    return _FragmentOutcome(
      units: parsed.units,
      rejectedUnits: parsed.rejectedUnits,
    );
  }

  /// Содержательные блоки раздела: без мусора и без пустых строк.
  static List<Block> _contentBlocks(Document document, Section section) =>
      document
          .blocksOfSection(section.id)
          .where(
            (Block block) => !block.isNoise && block.text.trim().isNotEmpty,
          )
          .toList(growable: false);

  /// Ключ кэша: содержимое документа и версия промпта.
  ///
  /// Смена промпта меняет понимание материала, поэтому старый ключ не должен
  /// отдавать новому коду карту, построенную другой инструкцией.
  static String _contentHash(String text) => sha256
      .convert(utf8.encode('$understandingPromptVersion\u0000$text'))
      .toString();

  /// Сумма фактических `usage`; отсутствующее поле — `null` (не 0).
  static TokenUsage _sumUsage(List<TokenUsage> usages) {
    if (usages.isEmpty) return const TokenUsage();
    int? sum(int? Function(TokenUsage usage) pick) {
      var total = 0;
      for (final TokenUsage usage in usages) {
        final int? value = pick(usage);
        if (value == null) return null;
        total += value;
      }
      return total;
    }

    return TokenUsage(
      promptTokens: sum((TokenUsage usage) => usage.promptTokens),
      completionTokens: sum((TokenUsage usage) => usage.completionTokens),
      totalTokens: sum((TokenUsage usage) => usage.totalTokens),
    );
  }
}

/// Итог понимания фрагмента (или объединения его частей после обрезки).
class _FragmentOutcome {
  const _FragmentOutcome({
    this.units = const <KnowledgeUnit>[],
    this.rejectedUnits = 0,
    this.failureReason,
  });

  /// Объединяет части разрезанного фрагмента: единицы успешных частей
  /// сохраняются, помеченные части дают причину пометки всего фрагмента.
  factory _FragmentOutcome.merged(List<_FragmentOutcome> parts) {
    KnowledgeMapFailureReason? failure;
    final List<KnowledgeUnit> units = <KnowledgeUnit>[];
    var rejected = 0;
    for (final _FragmentOutcome part in parts) {
      units.addAll(part.units);
      rejected += part.rejectedUnits;
      failure ??= part.failureReason;
    }
    return _FragmentOutcome(
      units: units,
      rejectedUnits: rejected,
      failureReason: failure,
    );
  }

  final List<KnowledgeUnit> units;
  final int rejectedUnits;
  final KnowledgeMapFailureReason? failureReason;

  /// Публичный статус фрагмента для [UnderstandingResult.fragments].
  KnowledgeMapFragmentOutcome toPublic(String fragmentId) =>
      failureReason != null
      ? KnowledgeMapFragmentOutcome.failed(
          fragmentId: fragmentId,
          reason: failureReason!,
        )
      : KnowledgeMapFragmentOutcome.understood(
          fragmentId: fragmentId,
          unitCount: units.length,
          rejectedUnits: rejectedUnits,
        );
}
