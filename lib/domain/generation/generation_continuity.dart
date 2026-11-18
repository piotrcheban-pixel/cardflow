/// Компактное состояние prompt-only запуска (TASK 03, раздел 4, L130).
///
/// Большой заказ без материалов выполняется несколькими запросами. Чтобы
/// модель не повторяла уже созданные факты и держала единый уровень сложности,
/// каждый следующий запрос получает компактную сводку: покрытые темы (tags) и
/// уже созданные вопросы (front). Сводка:
/// - **ограничена бюджетом** ([maxTokens], [maxCards], [maxFrontChars]) — она
///   не растёт бесконечно от запроса к запросу;
/// - **не меняет требования пользователя**: исходные `<wishes>` остаются
///   дословно, сводка добавляется отдельным блоком после них;
/// - строится только из **принятых** карточек этого запуска (дедуп уже
///   выполнен пайплайном), поэтому при частичном сбое не теряет успешное.
///
/// Это не система памяти и не БД: состояние живёт в рамках одного запуска
/// (`GenerationPipeline`), как и план. Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Сколько токенов максимум занимает блок продолжения в одном запросе.
///
/// Конфигурационный резерв приложения (не лимит модели): столько планировщик
/// вычитает из бюджета prompt-only плана, когда запросов больше одного.
const int kPromptOnlyContinuationMaxTokens = 1200;

/// Максимум карточек в компактной сводке (при большем — равномерная выборка).
const int kPromptOnlyContinuationMaxCards = 40;

/// Максимум символов front в одной строке сводки.
const int kPromptOnlyContinuationMaxFrontChars = 140;

/// Максимум уникальных тегов в сводке.
const int kPromptOnlyContinuationMaxTags = 40;

/// Состояние продолжения prompt-only запуска.
class GenerationContinuityState {
  /// Создаёт состояние с оценщиком (тем же, что у плана).
  GenerationContinuityState({
    required this.estimator,
    this.maxTokens = kPromptOnlyContinuationMaxTokens,
    this.maxCards = kPromptOnlyContinuationMaxCards,
    this.maxFrontChars = kPromptOnlyContinuationMaxFrontChars,
    this.maxTags = kPromptOnlyContinuationMaxTags,
  }) : assert(maxTokens > 0),
       assert(maxCards > 0),
       assert(maxFrontChars > 0),
       assert(maxTags > 0);

  /// Оценщик токенов (единый с планировщиком).
  final ContentTokenEstimator estimator;

  /// Предел токенов блока.
  final int maxTokens;

  /// Предел карточек в блоке.
  final int maxCards;

  /// Предел символов front.
  final int maxFrontChars;

  /// Предел тегов.
  final int maxTags;

  /// Уже покрытые карточки (кратко) в порядке появления.
  final List<_ContinuityCard> _cards = <_ContinuityCard>[];

  /// Хеши карточек (дедуп повторов между запросами).
  final Set<String> _hashes = <String>{};

  /// Теги в порядке появления (дедуп).
  final List<String> _tags = <String>[];

  String? _cachedBlock;
  int _cachedTokens = 0;

  /// Сколько карточек уже учтено (все, включая не вошедшие в блок).
  int get cardCount => _cards.length;

  /// true, если есть что передавать.
  bool get isEmpty => _cards.isEmpty;

  /// true, если есть карточки для блока.
  bool get isNotEmpty => _cards.isNotEmpty;

  /// Токены текущего блока (0 — пусто).
  int get tokens => _block == null ? 0 : _cachedTokens;

  /// Добавляет принятые карточки. Повторы по `contentHashOf` пропускаются.
  void addAll(Iterable<GeneratedCard> cards) {
    for (final GeneratedCard card in cards) {
      final String hash = contentHashOf(front: card.front, back: card.back);
      if (!_hashes.add(hash)) continue;
      final String front = _clean(card.front);
      if (front.isEmpty) continue;
      _cards.add(
        _ContinuityCard(front: front, back: _clean(card.back, maxLength: 80)),
      );
      for (final String tag in card.tags) {
        final String cleaned = _clean(tag, maxLength: 32).toLowerCase();
        if (cleaned.isEmpty || _tags.contains(cleaned)) continue;
        _tags.add(cleaned);
      }
      _cachedBlock = null;
    }
  }

  /// Текст блока продолжения для следующего запроса; `null` — нечего передавать.
  ///
  /// Формат — обычный текст внутри `<wishes>` (отдельный блок не вводится,
  /// чтобы не менять контракт схемы/промпта): заголовок, покрытые темы и
  /// вопросы. Исходные пожелания пользователя идут до блока дословно.
  String? get block => _block;

  String? get _block {
    if (_cards.isEmpty) return null;
    final String? cached = _cachedBlock;
    if (cached != null) return cached;
    final String text = _buildBlock();
    _cachedBlock = text;
    _cachedTokens = estimator.estimateText(text);
    return text;
  }

  /// Заголовок блока (ARB не нужен: текст адресован модели, не пользователю).
  static const String header =
      'Уже созданные карточки (не повторяй их факты и не переформулируй те же '
      'вопросы; сохраняй прежние уровень сложности и терминологию):';

  String _buildBlock() {
    final List<String> lines = <String>[header];

    final List<String> tags = _tags.take(maxTags).toList(growable: false);
    if (tags.isNotEmpty) {
      lines.add('Покрытые темы: ${tags.join(', ')}.');
    }

    final List<_ContinuityCard> chosen = _sampleCards();
    for (final _ContinuityCard card in chosen) {
      lines.add(
        card.back.isEmpty
            ? '- ${card.front}'
            : '- ${card.front} → ${card.back}',
      );
    }
    final int omitted = _cards.length - chosen.length;
    if (omitted > 0) {
      lines.add(
        'Ещё $omitted карточек уже созданы; не повторяй их темы и факты.',
      );
    }

    // Обрезаем по бюджету: добавляем строки, пока оценка не превысит предел.
    final StringBuffer buffer = StringBuffer();
    for (final String line in lines) {
      final String candidate = buffer.isEmpty ? line : '$buffer\n$line';
      if (estimator.estimateText(candidate) > maxTokens) break;
      buffer
        ..clear()
        ..write(candidate);
    }
    if (buffer.isEmpty) {
      // Даже заголовок не влез — сообщаем только самое короткое.
      return header;
    }
    return buffer.toString();
  }

  /// Равномерная выборка карточек, если их больше [maxCards].
  ///
  /// Выборка детерминирована и сохраняет порядок: первые карточки запуска не
  /// вытесняются последними, иначе модель снова повторит начало темы.
  List<_ContinuityCard> _sampleCards() {
    if (_cards.length <= maxCards) return _cards;
    final int step = (_cards.length / maxCards).ceil();
    final List<_ContinuityCard> result = <_ContinuityCard>[];
    for (var index = 0; index < _cards.length; index += step) {
      result.add(_cards[index]);
      if (result.length >= maxCards) break;
    }
    return result;
  }

  static String _clean(
    String value, {
    int maxLength = kPromptOnlyContinuationMaxFrontChars,
  }) {
    final String cleaned = value
        .replaceAll(RegExp(r'\s+', unicode: true), ' ')
        .trim();
    if (cleaned.length <= maxLength) return cleaned;
    return '${cleaned.substring(0, maxLength).trim()}…';
  }
}

/// Краткая карточка сводки.
class _ContinuityCard {
  const _ContinuityCard({required this.front, required this.back});

  final String front;
  final String back;
}
