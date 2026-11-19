/// Независимая проверка качества карточек после live-прогона (TASK 04,
/// раздел 8).
///
/// Автоматизируются только **измеримые** дефекты: дубликаты, пустые поля,
/// превышение лимитов SPEC A8.4, число пометок валидатора, наличие иллюстрации
/// и цитаты-источника. Смысловые критерии (корректность вопроса/ответа,
/// отсутствие выдуманных фактов, самодостаточность, неоднозначность,
/// сохранение определений) остаются **ручной** оценкой по чек-листу: LLM-оценка
/// без отдельного обоснования не вводится (требование раздела 8).
///
/// Успешный HTTP 200 не считается доказательством качества: отчёт показывает
/// именно дефекты и оставляет место для ручных баллов.
library;

import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Лимиты длины карточки по канону SPEC A8.4.
const int kQualityMaxFrontLength = 500;

/// Лимит ответа карточки по SPEC A8.4.
const int kQualityMaxBackLength = 2000;

/// «Мягкие» пороги длинного вопроса/ответа (повод для ручной проверки).
const int kQualitySoftFrontLength = 200;

/// «Мягкий» порог длинного ответа.
const int kQualitySoftBackLength = 1000;

/// Максимум тегов карточки (SPEC A8.4).
const int kQualityMaxTags = 3;

/// Чек-лист ручной оценки (1 — критерий ниже, 2 — выполнен).
const List<String> kManualQualityChecklist = <String>[
  'корректность вопроса (формулировка проверяет знание, а не догадку)',
  'корректность ответа (факт верен и однозначен)',
  'соответствие исходному материалу (для материаловых сценариев)',
  'отсутствие выдуманных фактов (особенно в prompt-only)',
  'отсутствие повторов между карточками (смысловых, не только текстовых)',
  'самодостаточность карточки (понятна без контекста)',
  'отсутствие неоднозначности (один правильный ответ)',
  'сохранение важных определений материала',
  'разумная длина вопроса',
  'разумная длина ответа',
];

/// Результат автоматической проверки набора карточек.
class LiveCardQualityReport {
  /// Создаёт отчёт.
  const LiveCardQualityReport({
    required this.cardCount,
    required this.duplicateCards,
    required this.emptyFront,
    required this.emptyBack,
    required this.tooLongFront,
    required this.tooLongBack,
    required this.longFront,
    required this.longBack,
    required this.tooManyTags,
    required this.cardsWithIssues,
    required this.issueCodes,
    required this.withImage,
    required this.withSourceExcerpt,
    required this.violations,
  });

  /// Сколько карточек оценено.
  final int cardCount;

  /// Сколько карточек — повтор уже встретившейся (по `contentHashOf`).
  final int duplicateCards;

  /// Карточки с пустым вопросом.
  final int emptyFront;

  /// Карточки с пустым ответом.
  final int emptyBack;

  /// Вопросы длиннее [kQualityMaxFrontLength].
  final int tooLongFront;

  /// Ответы длиннее [kQualityMaxBackLength].
  final int tooLongBack;

  /// Вопросы длиннее [kQualitySoftFrontLength] (повод для ручной проверки).
  final int longFront;

  /// Ответы длиннее [kQualitySoftBackLength].
  final int longBack;

  /// Карточки с числом тегов больше [kQualityMaxTags].
  final int tooManyTags;

  /// Карточки с хотя бы одной пометкой валидатора.
  final int cardsWithIssues;

  /// Пометки валидатора по кодам.
  final Map<String, int> issueCodes;

  /// Карточки с иллюстрацией.
  final int withImage;

  /// Карточки с цитатой-источником.
  final int withSourceExcerpt;

  /// Текстовые нарушения (индексы, без содержимого карточек).
  final List<String> violations;

  /// true, если измеримых нарушений нет.
  bool get isClean => violations.isEmpty;

  /// Автоматическая проверка набора.
  static LiveCardQualityReport evaluate(List<GeneratedCard> cards) {
    final Set<String> seen = <String>{};
    final List<String> violations = <String>[];
    final Map<String, int> issueCodes = <String, int>{};
    var duplicates = 0;
    var emptyFront = 0;
    var emptyBack = 0;
    var tooLongFront = 0;
    var tooLongBack = 0;
    var longFront = 0;
    var longBack = 0;
    var tooManyTags = 0;
    var withIssues = 0;
    var withImage = 0;
    var withExcerpt = 0;

    for (var index = 0; index < cards.length; index++) {
      final GeneratedCard card = cards[index];
      final int position = index + 1;
      final String hash = contentHashOf(front: card.front, back: card.back);
      if (!seen.add(hash)) {
        duplicates++;
        violations.add('карточка $position: повтор (contentHash)');
      }
      if (card.front.trim().isEmpty) {
        emptyFront++;
        violations.add('карточка $position: пустой вопрос');
      }
      if (card.back.trim().isEmpty) {
        emptyBack++;
        violations.add('карточка $position: пустой ответ');
      }
      if (card.front.length > kQualityMaxFrontLength) {
        tooLongFront++;
        violations.add(
          'карточка $position: вопрос ${card.front.length} символов '
          '(> $kQualityMaxFrontLength)',
        );
      } else if (card.front.length > kQualitySoftFrontLength) {
        longFront++;
      }
      if (card.back.length > kQualityMaxBackLength) {
        tooLongBack++;
        violations.add(
          'карточка $position: ответ ${card.back.length} символов '
          '(> $kQualityMaxBackLength)',
        );
      } else if (card.back.length > kQualitySoftBackLength) {
        longBack++;
      }
      if (card.tags.length > kQualityMaxTags) {
        tooManyTags++;
        violations.add(
          'карточка $position: тегов ${card.tags.length} '
          '(> $kQualityMaxTags)',
        );
      }
      if (card.issues.isNotEmpty) {
        withIssues++;
        for (final CardIssueCode code in card.issues) {
          issueCodes[code.name] = (issueCodes[code.name] ?? 0) + 1;
        }
      }
      if (card.image != null) withImage++;
      if (card.sourceExcerpt != null && card.sourceExcerpt!.trim().isNotEmpty) {
        withExcerpt++;
      }
    }

    return LiveCardQualityReport(
      cardCount: cards.length,
      duplicateCards: duplicates,
      emptyFront: emptyFront,
      emptyBack: emptyBack,
      tooLongFront: tooLongFront,
      tooLongBack: tooLongBack,
      longFront: longFront,
      longBack: longBack,
      tooManyTags: tooManyTags,
      cardsWithIssues: withIssues,
      issueCodes: Map<String, int>.unmodifiable(issueCodes),
      withImage: withImage,
      withSourceExcerpt: withExcerpt,
      violations: List<String>.unmodifiable(violations),
    );
  }

  /// JSON для отчёта прогона.
  Map<String, Object?> toJson() => <String, Object?>{
    'cardCount': cardCount,
    'duplicateCards': duplicateCards,
    'emptyFront': emptyFront,
    'emptyBack': emptyBack,
    'tooLongFront': tooLongFront,
    'tooLongBack': tooLongBack,
    'longFront': longFront,
    'longBack': longBack,
    'tooManyTags': tooManyTags,
    'cardsWithIssues': cardsWithIssues,
    'issueCodes': issueCodes,
    'withImage': withImage,
    'withSourceExcerpt': withSourceExcerpt,
    'violations': violations,
  };

  /// Markdown-строка для журнала испытаний.
  String toMarkdown() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('| Показатель | Значение |')
      ..writeln('|---|---:|')
      ..writeln('| карточек | $cardCount |')
      ..writeln('| повторов | $duplicateCards |')
      ..writeln('| пустой вопрос / ответ | $emptyFront / $emptyBack |')
      ..writeln(
        '| длинный вопрос / ответ (> SPEC) | $tooLongFront / $tooLongBack |',
      )
      ..writeln('| длинный вопрос / ответ (мягко) | $longFront / $longBack |')
      ..writeln('| > $kQualityMaxTags тегов | $tooManyTags |')
      ..writeln('| с пометками валидатора | $cardsWithIssues |')
      ..writeln('| с иллюстрацией | $withImage |')
      ..writeln('| с цитатой-источником | $withSourceExcerpt |');
    if (issueCodes.isNotEmpty) {
      buffer.writeln(
        '| коды пометок | ${issueCodes.entries.map((MapEntry<String, int> e) => '${e.key}: ${e.value}').join(', ')} |',
      );
    }
    if (violations.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Нарушения:');
      for (final String violation in violations) {
        buffer.writeln('- $violation');
      }
    }
    return buffer.toString();
  }
}
