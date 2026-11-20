import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_limits.dart';

/// Регрессия ревью 7.18.1: `requestBytes` учитывает текст каталога `<images>`,
/// а не только материалы и base64. Без этого большой каталог подписей молча
/// превышал технический лимит тела запроса.
void main() {
  InputImage image({int catalogLineBytes = 0}) => InputImage(
    id: 'img1',
    fileName: 'схема.png',
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    catalogLineBytes: catalogLineBytes,
  );

  InputSection section(List<InputImage> images) => InputSection(
    id: 'doc:a.txt#0',
    tokens: 20,
    text: 'Материал раздела.',
    title: 'Раздел',
    documentName: 'a.txt',
    shortId: 's1',
    images: images,
  );

  test('каталог изображений входит в requestBytes (payload-ограничение)', () {
    final InputPlan plan = const InputPlanner().plan(
      sections: <InputSection>[
        section(<InputImage>[image(catalogLineBytes: 6000)]),
      ],
      limits: const ModelLimits(
        contextTokens: Sourced<int>(
          128000,
          source: CapabilitySource.userConfigured,
        ),
        maxRequestBytes: Sourced<int>(
          3000,
          source: CapabilitySource.userConfigured,
        ),
      ),
      fixedTokens: 100,
      desiredOutputTokens: 4000,
    );
    expect(
      plan.budget.payloadExceeded,
      isTrue,
      reason: 'каталог 6000 Б + материалы уже больше лимита 3000 Б',
    );
    expect(plan.warnings, contains(PlanWarningCode.payloadLimited));
    expect(plan.strategy, InputStrategy.wholeDocument);
  });

  test('без каталога тот же запрос помещается', () {
    final InputPlan plan = const InputPlanner().plan(
      sections: <InputSection>[
        section(<InputImage>[image()]),
      ],
      limits: const ModelLimits(
        contextTokens: Sourced<int>(
          128000,
          source: CapabilitySource.userConfigured,
        ),
        maxRequestBytes: Sourced<int>(
          3000,
          source: CapabilitySource.userConfigured,
        ),
      ),
      fixedTokens: 100,
      desiredOutputTokens: 4000,
    );
    expect(plan.budget.payloadExceeded, isFalse);
    expect(plan.parts.single.bytes, lessThanOrEqualTo(3000));
  });
}
