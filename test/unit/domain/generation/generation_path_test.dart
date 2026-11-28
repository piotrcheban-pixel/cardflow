import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_path.dart';

/// Срез 17, часть 2, п. 11: путь генерации — **функция от материала**, а не
/// флаг в настройках. Флаг остаётся ручным переопределением `v3`/`legacy`;
/// режим `auto` выбирает путь по порогу N*.
void main() {
  test('ручное переопределение не зависит от объёма материала', () {
    for (final int units in <int>[0, 1, 10, 33, 1000]) {
      expect(
        selectGenerationPath(
          mode: GenerationPathMode.v3,
          materialUnits: units,
        ).path,
        GenerationPath.v3,
      );
      expect(
        selectGenerationPath(
          mode: GenerationPathMode.legacy,
          materialUnits: units,
        ).path,
        GenerationPath.legacy,
      );
    }
  });

  test('авто по данным S17 — legacy: порог не определён (п. 10 TASK)', () {
    expect(kGenerationPathV3MinUnits, isNull, reason: 'данные не дают разрыва');
    for (final int units in <int>[0, 10, 33, 1000]) {
      final GenerationPathDecision decision = selectGenerationPath(
        mode: GenerationPathMode.auto,
        materialUnits: units,
      );
      expect(decision.path, GenerationPath.legacy);
      expect(
        decision.boundaryNotDetermined,
        isTrue,
        reason:
            'граница выбора не определена данными — это видно, а не '
            'спрятано в комментарии',
      );
      expect(decision.thresholdUnits, isNull);
    }
  });

  test('авто с определённым порогом выбирает v3 от N* единиц', () {
    final GenerationPathDecision below = selectGenerationPath(
      mode: GenerationPathMode.auto,
      materialUnits: 19,
      thresholdUnits: 20,
    );
    final GenerationPathDecision at = selectGenerationPath(
      mode: GenerationPathMode.auto,
      materialUnits: 20,
      thresholdUnits: 20,
    );
    final GenerationPathDecision above = selectGenerationPath(
      mode: GenerationPathMode.auto,
      materialUnits: 200,
      thresholdUnits: 20,
    );
    expect(below.path, GenerationPath.legacy);
    expect(at.path, GenerationPath.v3);
    expect(above.path, GenerationPath.v3);
    expect(at.boundaryNotDetermined, isFalse);
    expect(below.thresholdUnits, 20);
  });

  test('решение несёт режим, объём и порог — его можно показать числом', () {
    final GenerationPathDecision decision = selectGenerationPath(
      mode: GenerationPathMode.v3,
      materialUnits: 33,
    );
    expect(decision.mode, GenerationPathMode.v3);
    expect(decision.materialUnits, 33);
    expect(decision.thresholdUnits, isNull);
    expect(decision.boundaryNotDetermined, isFalse);
  });

  test('JSON-имена режима — wire-коды, читаются обе стороны', () {
    expect(GenerationPathMode.auto.wireName, 'auto');
    expect(GenerationPathMode.v3.wireName, 'v3');
    expect(GenerationPathMode.legacy.wireName, 'legacy');
    for (final GenerationPathMode mode in GenerationPathMode.values) {
      expect(GenerationPathMode.fromWire(mode.wireName), mode);
    }
    expect(GenerationPathMode.fromWire(null), GenerationPathMode.auto);
    expect(GenerationPathMode.fromWire('unknown'), GenerationPathMode.auto);
  });
}
