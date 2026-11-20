import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_plan_splitter.dart';

/// 7.18.1 §2.3: перепланирование после переполнения контекста с бюджетом ×0.8.
void main() {
  const GenerationPlanSplitter splitter = GenerationPlanSplitter();

  /// Фрагмент из [count] единиц по [tokens] токенов каждая.
  PlannedChunk chunkWith({
    int count = 3,
    int tokens = 1000,
    int limit = 10,
    int splitDepth = 0,
  }) {
    final StringBuffer buffer = StringBuffer();
    final List<UnitSpan> units = <UnitSpan>[];
    for (var index = 0; index < count; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      final String text = 'Раздел $index. ${'слово ' * 40}';
      buffer.write(text);
      units.add(
        UnitSpan(
          unitId: 'doc:a.txt#0#$index',
          start: start,
          end: buffer.length,
          tokens: tokens,
        ),
      );
    }
    return PlannedChunk(
      index: 1,
      kind: ChunkKind.text,
      units: units,
      textTokens: tokens * count,
      imageTokens: 0,
      bodyBytes: buffer.length,
      limit: limit,
      splitDepth: splitDepth,
      materialsText: buffer.toString(),
    );
  }

  int contentTokens(PlannedChunk part) =>
      part.units.fold<int>(0, (int sum, UnitSpan unit) => sum + unit.tokens) +
      part.imageTokens;

  test('цель ×0.8: части не крупнее бюджета, сумма лимитов сохраняется', () {
    final PlannedChunk chunk = chunkWith(count: 4, tokens: 1000, limit: 10);
    final List<PlannedChunk>? parts = splitter.splitToBudget(
      chunk,
      targetTokens: 1600,
    );
    expect(parts, isNotNull);
    expect(parts!.length, greaterThanOrEqualTo(3));
    expect(
      parts.every((PlannedChunk part) => contentTokens(part) <= 1600),
      isTrue,
    );
    expect(
      parts.fold<int>(0, (int sum, PlannedChunk part) => sum + part.limit),
      chunk.limit,
    );
    expect(
      parts.map((PlannedChunk part) => part.materialsText).join(),
      chunk.materialsText,
      reason: 'ни один символ материалов не потерян и не задвоен',
    );
    expect(
      parts.every((PlannedChunk part) => part.splitDepth > chunk.splitDepth),
      isTrue,
    );
  });

  test('часть уже помещается в цель — деление не нужно (null)', () {
    final PlannedChunk chunk = chunkWith(count: 1, tokens: 500);
    expect(splitter.splitToBudget(chunk, targetTokens: 2000), isNull);
  });

  test('prompt-only и цель 0 — делить нечего', () {
    final PlannedChunk promptOnly = PlannedChunk.promptOnly(index: 1, limit: 5);
    expect(splitter.splitToBudget(promptOnly, targetTokens: 10), isNull);
    expect(
      splitter.splitToBudget(chunkWith(), targetTokens: 0),
      isNull,
      reason: 'нулевая цель не должна приводить к бесконечному делению',
    );
  });

  test('предохранитель maxParts ограничивает число частей', () {
    final PlannedChunk chunk = chunkWith(count: 8, tokens: 1000, limit: 8);
    final List<PlannedChunk>? parts = splitter.splitToBudget(
      chunk,
      targetTokens: 100,
      maxParts: 3,
    );
    expect(parts, isNotNull);
    expect(parts!.length, lessThanOrEqualTo(3));
  });
}
