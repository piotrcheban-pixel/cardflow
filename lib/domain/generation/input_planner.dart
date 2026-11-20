/// Input Planner: сначала весь документ, потом минимальное число частей
/// (ADR-040 §3–4).
///
/// Планировщик решает **только** вопрос «отправлять материал целиком или
/// частями» и зависит исключительно от бюджета входа и резерва вывода
/// (`R`, который не зависит от числа запрошенных карточек). Количества
/// карточек в его интерфейсе нет — независимость от заказа структурная.
/// Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/model_limits.dart';

/// Стратегия входа.
enum InputStrategy {
  /// Без материалов: тема/пожелания пользователя (ADR-024).
  promptOnly,

  /// Весь материал помещается в один запрос (после уменьшения резерва вывода).
  wholeDocument,

  /// Материал делится на минимальное число смысловых частей.
  fragmented,
}

/// Тип раздела для планирования и распределения карточек.
enum SectionKind {
  /// Содержательный раздел (может получать карточки).
  content,

  /// Служебный раздел (оглавление, литература, колонтитулы): 0 карточек.
  service,
}

/// Изображение, участвующее в запросе.
final class InputImage {
  /// Создаёт изображение плана.
  const InputImage({
    required this.id,
    required this.fileName,
    required this.bytes,
    this.tokens = 0,
    this.page,
  }) : assert(id != ''),
       assert(fileName != '');

  /// Стабильный id (`img1…` или `doc:<файл>#<n>`).
  final String id;

  /// Имя файла-источника.
  final String fileName;

  /// Байты (до base64).
  final Uint8List bytes;

  /// Оценка токенов изображения.
  final int tokens;

  /// Номер страницы, если известен.
  final int? page;
}

/// Раздел материала для Input Planner.
final class InputSection {
  /// Создаёт раздел с готовой оценкой токенов.
  const InputSection({
    required this.id,
    required this.tokens,
    this.title = '',
    this.text = '',
    this.kind = SectionKind.content,
    this.shortId,
    this.images = const <InputImage>[],
    this.unitIds = const <String>[],
  }) : assert(id != ''),
       assert(tokens >= 0);

  /// Полный стабильный id раздела (`doc:<файл>#<индекс>`).
  final String id;

  /// Заголовок раздела (может быть пустым).
  final String title;

  /// Текст раздела (для `<materials>` и упаковки).
  final String text;

  /// Оценка токенов текста.
  final int tokens;

  /// Служебный или содержательный раздел.
  final SectionKind kind;

  /// Короткий стабильный id для модели (`s3`).
  final String? shortId;

  /// Изображения раздела (в порядке следования).
  final List<InputImage> images;

  /// Идентификаторы единиц содержимого (для покрытия).
  final List<String> unitIds;

  /// Короткий id для `<materials>`/`<focus>`.
  String get promptId => shortId ?? id;
}

/// Часть материала (входная единица запросов).
final class InputPart {
  /// Создаёт часть.
  const InputPart({
    required this.index,
    required this.sections,
    required this.materialsText,
    required this.tokens,
    required this.bytes,
    this.outlineText = '',
    this.images = const <InputImage>[],
    this.contextOnlyText = '',
  }) : assert(index >= 0),
       assert(tokens >= 0),
       assert(bytes >= 0);

  /// Номер части (с нуля).
  final int index;

  /// Разделы части в порядке документа.
  final List<InputSection> sections;

  /// Текст `<materials>` части (с заголовками файлов и разделов).
  final String materialsText;

  /// Оценка токенов материалов части.
  final int tokens;

  /// Байты тела части (текст + base64 изображений + запас JSON).
  final int bytes;

  /// Компактное оглавление части (только при fragmented).
  final String outlineText;

  /// Изображения, байты которых отправляются с этой частью.
  final List<InputImage> images;

  /// Перекрытие с предыдущей частью (`<context_only>`).
  final String contextOnlyText;

  /// Номер части для текста «часть k из n» (с 1).
  int get partNumber => index + 1;
}

/// План входа: стратегия, части, бюджет и статусы вложений.
final class InputPlan {
  /// Создаёт план входа.
  const InputPlan({
    required this.strategy,
    required this.parts,
    required this.fixedTokens,
    required this.inputTokens,
    required this.maxTokens,
    required this.accuracy,
    required this.budget,
    required this.materialTokens,
    this.materialBudgetPerPart,
    this.outlineReserveTokens = 0,
    this.warnings = const <PlanWarningCode>[],
    this.images = const <PlannedImage>[],
    this.contextTokens,
  });

  /// Стратегия входа.
  final InputStrategy strategy;

  /// Части материала (пусто для prompt-only).
  final List<InputPart> parts;

  /// Служебная часть запроса `P`, токенов.
  final int fixedTokens;

  /// Оценка входа: общая для whole, максимальная по части для fragmented.
  final int inputTokens;

  /// Резерв вывода на запрос: `maxTokens` для whole, `R` для fragmented.
  final int maxTokens;

  /// Точность подсчёта входа.
  final InputAccuracy accuracy;

  /// Бюджет (whole — всего запроса, fragmented — максимальной части).
  final RequestBudget budget;

  /// Сумма токенов материалов.
  final int materialTokens;

  /// Максимальный объём материалов части (fragmented), токенов.
  final int? materialBudgetPerPart;

  /// Резерв на оглавление в каждой части, токенов.
  final int outlineReserveTokens;

  /// Предупреждения плана.
  final List<PlanWarningCode> warnings;

  /// Статусы изображений: передано модели / только каталог / исключено.
  final List<PlannedImage> images;

  /// Окно контекста модели (`null` — неизвестно).
  final int? contextTokens;

  /// Число частей материала.
  int get partCount => parts.length;

  /// true, если весь документ отправляется целиком.
  bool get isWholeDocument => strategy == InputStrategy.wholeDocument;

  /// true, если материал разделён.
  bool get isFragmented => strategy == InputStrategy.fragmented;

  /// true, если материалы отсутствуют.
  bool get isPromptOnly => strategy == InputStrategy.promptOnly;

  @override
  String toString() =>
      'InputPlan(${strategy.name}, parts: ${parts.length}, '
      'input: $inputTokens, max: $maxTokens)';
}

/// Строит план входа (ADR-040 §3–4).
final class InputPlanner {
  /// Создаёт планировщик.
  const InputPlanner({this.config = const GenerationPlanningConfig()});

  /// Коэффициенты бюджета/вывода.
  final GenerationPlanningConfig config;

  /// Строит план входа.
  ///
  /// Ни [requestedCards], ни распределение карточек здесь не участвуют:
  /// разбиение зависит только от бюджета входа и резерва вывода `R`.
  InputPlan plan({
    required List<InputSection> sections,
    required ModelLimits limits,
    required int fixedTokens,
    required int desiredOutputTokens,
    InputAccuracy accuracy = InputAccuracy.estimated,
    int outlineReserveTokens = 0,
    List<InputImage> orphanImages = const <InputImage>[],
  }) {
    // RED-фаза итерации 7.18: контракт зафиксирован, алгоритм — следующий шаг.
    final int materialTokens = sections.fold<int>(
      0,
      (int sum, InputSection section) => sum + section.tokens,
    );
    final RequestBudget budget = RequestBudget.compute(
      limits: limits,
      fixedTokens: fixedTokens,
      materialTokens: materialTokens,
      desiredOutputTokens: desiredOutputTokens,
      accuracy: accuracy,
      config: config,
    );
    return InputPlan(
      strategy: InputStrategy.fragmented,
      parts: <InputPart>[
        InputPart(
          index: 0,
          sections: List<InputSection>.unmodifiable(sections),
          materialsText: '',
          tokens: materialTokens,
          bytes: utf8.encode('').length,
        ),
      ],
      fixedTokens: fixedTokens,
      inputTokens: budget.inputTokens,
      maxTokens: budget.maxTokens,
      accuracy: accuracy,
      budget: budget,
      materialTokens: materialTokens,
    );
  }

  /// Байты текста в UTF-8.
  static int textBytes(String text) => utf8.encode(text).length;

  /// Длина тела после base64 (округление вверх до 4 байт).
  static int base64EncodedByteLength(int bytes) {
    if (bytes <= 0) return 0;
    return ((bytes + 2) ~/ 3) * 4;
  }

  /// Сумма байтов изображений после base64.
  static int imageBytes(Iterable<InputImage> images) {
    var total = 0;
    for (final InputImage image in images) {
      total += base64EncodedByteLength(image.bytes.length);
    }
    return total;
  }

  /// Бюджет материалов части при дроблении: `floor((limit − R)/(1+m)) − P`.
  static int materialBudget({
    required int limit,
    required int outputReserve,
    required double margin,
    required int fixedPartTokens,
    required bool subtractOutput,
  }) {
    final double room = subtractOutput ? (limit - outputReserve).toDouble() : limit.toDouble();
    final double available = room / (1 + margin) - fixedPartTokens;
    return math.max(1, available.floor());
  }
}
