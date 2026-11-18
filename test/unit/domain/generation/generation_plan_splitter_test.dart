import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_plan_splitter.dart';

/// F.3: дробление только проблемного фрагмента с сохранением единиц и связей.
void main() {
  const GenerationPlanSplitter splitter = GenerationPlanSplitter();

  DocumentImage imageOf({String fileName = 'doc.txt', int index = 0}) {
    return DocumentImage(
      fileName: fileName,
      bytes: Uint8List.fromList(<int>[index, index + 1, index + 2, index + 3]),
      mediaType: AttachmentMediaType.png,
      sectionIndex: index,
      caption: 'Рис. $index',
    );
  }

  PlannedChunk chunkOf({
    required String text,
    required int limit,
    int splitDepth = 0,
    List<UnitSpan>? units,
    List<DocumentImage> images = const <DocumentImage>[],
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) {
    return PlannedChunk(
      index: 1,
      kind: text.trim().isEmpty ? ChunkKind.images : ChunkKind.mixed,
      units:
          units ??
          <UnitSpan>[
            const UnitSpan(
              unitId: 'doc:a.txt#0#0',
              start: 0,
              end: 30,
              tokens: 10,
            ),
            const UnitSpan(
              unitId: 'doc:a.txt#0#1',
              start: 30,
              end: 70,
              tokens: 20,
            ),
          ],
      imageParts: images,
      imagePartIds: <String>[
        for (var index = 0; index < images.length; index++)
          'img:doc.txt#$index',
      ],
      attachments: attachments,
      textTokens: 30,
      imageTokens: 0,
      bodyBytes: 0,
      limit: limit,
      splitDepth: splitDepth,
      materialsText: text,
    );
  }

  test('делит по единицам: текст и unitIds не теряются, лимит делится', () {
    const String text =
        'Первая единица материала.\n\nВторая единица материала.';
    final PlannedChunk parent = chunkOf(text: text, limit: 5);
    final List<PlannedChunk>? halves = splitter.split(parent);
    expect(halves, isNotNull);
    expect(halves, hasLength(2));
    expect(
      halves![0].materialsText + halves[1].materialsText,
      text,
      reason: 'ни один символ не потерян',
    );
    final List<String> unitIds = <String>[
      for (final PlannedChunk chunk in halves)
        for (final UnitSpan span in chunk.units) span.unitId,
    ];
    expect(unitIds, <String>['doc:a.txt#0#0', 'doc:a.txt#0#1']);
    expect(halves[0].limit + halves[1].limit, parent.limit);
    expect(halves[0].limit, greaterThanOrEqualTo(1));
    expect(halves[1].limit, greaterThanOrEqualTo(1));
    expect(halves[0].splitDepth, 1);
    expect(halves[1].splitDepth, 1);
  });

  test('изображения не дублируются и не теряются', () {
    const String text =
        'Первая единица материала.\n\nВторая единица материала.';
    final PlannedChunk parent = chunkOf(
      text: text,
      limit: 4,
      images: <DocumentImage>[imageOf(index: 0), imageOf(index: 1)],
    );
    final List<PlannedChunk>? halves = splitter.split(parent);
    expect(halves, isNotNull);
    final List<String> partIds = <String>[
      for (final PlannedChunk chunk in halves!) ...chunk.imagePartIds,
    ];
    expect(partIds, hasLength(2));
    expect(partIds.toSet(), hasLength(2), reason: 'без дублей');
  });

  test('делит страницы вложений без дублей', () {
    GenerationAttachment page(int number) => GenerationAttachment(
      fileName: 'scan.pdf',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[number, number + 1, number + 2]),
      pageNumber: number,
      groupKey: 'scan.pdf',
    );
    final PlannedChunk parent = PlannedChunk(
      index: 1,
      kind: ChunkKind.images,
      imageParts: const <DocumentImage>[],
      imagePartIds: const <String>[],
      attachments: <GenerationAttachment>[page(1), page(2), page(3), page(4)],
      textTokens: 0,
      imageTokens: 0,
      bodyBytes: 0,
      limit: 6,
      materialsText: '',
    );
    final List<PlannedChunk>? halves = splitter.split(parent);
    expect(halves, isNotNull);
    final List<int?> pages = <int?>[
      for (final PlannedChunk chunk in halves!)
        for (final GenerationAttachment attachment in chunk.attachments)
          attachment.pageNumber,
    ];
    expect(pages, <int?>[1, 2, 3, 4]);
    expect(halves[0].limit + halves[1].limit, parent.limit);
  });

  test('делит одиночную длинную единицу по границе текста', () {
    final String text = '${'Первое предложение. ' * 20}\n${'Второе. ' * 20}';
    final PlannedChunk parent = PlannedChunk(
      index: 1,
      kind: ChunkKind.text,
      units: <UnitSpan>[
        UnitSpan(
          unitId: 'doc:a.txt#0#0',
          start: 0,
          end: text.length,
          tokens: 100,
        ),
      ],
      textTokens: 100,
      imageTokens: 0,
      bodyBytes: 0,
      limit: 4,
      materialsText: text,
    );
    final List<PlannedChunk>? halves = splitter.split(parent);
    expect(halves, isNotNull);
    expect(halves![0].materialsText + halves[1].materialsText, text);
    expect(halves[0].units.single.unitId, 'doc:a.txt#0#0');
    expect(halves[1].units.single.unitId, isNot('doc:a.txt#0#0'));
  });

  test('не делит prompt-only, лимит 1 и глубина сверх предела', () {
    expect(splitter.split(PlannedChunk.promptOnly(index: 1, limit: 5)), isNull);
    expect(
      splitter.split(
        chunkOf(
          text: 'Первая единица материала.\n\nВторая единица материала.',
          limit: 1,
        ),
      ),
      isNull,
    );
    expect(
      splitter.split(
        chunkOf(
          text: 'Первая единица материала.\n\nВторая единица материала.',
          limit: 5,
          splitDepth: 3,
        ),
      ),
      isNull,
    );
  });
}
