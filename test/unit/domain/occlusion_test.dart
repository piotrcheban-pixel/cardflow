import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/occlusion.dart';

void main() {
  const rectangle = OcclusionMask(
    id: 'm1',
    shape: OcclusionShape.rectangle,
    x: 0.1,
    y: 0.2,
    width: 0.3,
    height: 0.4,
  );
  const ellipse = OcclusionMask(
    id: 'm2',
    shape: OcclusionShape.ellipse,
    x: 0,
    y: 0.5,
    width: 1,
    height: 0.5,
  );

  test('round-trip сохраняет версию, формы и нормализованные координаты', () {
    const document = OcclusionDocument(
      masks: <OcclusionMask>[rectangle, ellipse],
    );

    final decoded = OcclusionDocument.tryParse(document.encode());

    expect(decoded, isNotNull, reason: 'собственный JSON обязан читаться');
    expect(decoded!.masks, hasLength(2));
    expect(decoded.masks[0].id, 'm1');
    expect(decoded.masks[0].shape, OcclusionShape.rectangle);
    expect(decoded.masks[0].x, 0.1);
    expect(decoded.masks[0].y, 0.2);
    expect(decoded.masks[0].width, 0.3);
    expect(decoded.masks[0].height, 0.4);
    expect(decoded.masks[1].shape, OcclusionShape.ellipse);
    expect(decoded.masks[1].width, 1);
  });

  test('маски и JSON-поля сериализуются по контракту ADR-017', () {
    expect(rectangle.toJson(), <String, Object?>{
      'id': 'm1',
      'shape': 'rectangle',
      'x': 0.1,
      'y': 0.2,
      'width': 0.3,
      'height': 0.4,
    });
    expect(
      const OcclusionDocument(masks: <OcclusionMask>[rectangle]).encode(),
      '{"version":1,"masks":[{"id":"m1","shape":"rectangle",'
      '"x":0.1,"y":0.2,"width":0.3,"height":0.4}]}',
    );
  });

  group('tryParse отклоняет повреждённые данные, не роняя сессию', () {
    final invalid = <String, String?>{
      'null': null,
      'пусто': '',
      'не JSON': '{',
      'массив вместо объекта': '[]',
      'другая версия': '{"version":2,"masks":[]}',
      'masks не список': '{"version":1,"masks":{}}',
      'неизвестная форма':
          '{"version":1,"masks":[{"id":"m","shape":"path",'
          '"x":0,"y":0,"width":1,"height":1}]}',
      'нулевая ширина':
          '{"version":1,"masks":[{"id":"m","shape":"rectangle",'
          '"x":0,"y":0,"width":0,"height":1}]}',
      'выход за правый край':
          '{"version":1,"masks":[{"id":"m","shape":"rectangle",'
          '"x":0.8,"y":0,"width":0.3,"height":1}]}',
      'отрицательная координата':
          '{"version":1,"masks":[{"id":"m","shape":"ellipse",'
          '"x":-0.1,"y":0,"width":0.3,"height":1}]}',
      'дубликат id':
          '{"version":1,"masks":['
          '{"id":"m","shape":"rectangle","x":0,"y":0,"width":0.2,"height":0.2},'
          '{"id":"m","shape":"ellipse","x":0.3,"y":0.3,"width":0.2,"height":0.2}]}',
    };
    invalid.forEach((name, source) {
      test(name, () => expect(OcclusionDocument.tryParse(source), isNull));
    });
  });

  test('список масок immutable', () {
    final decoded = OcclusionDocument.tryParse(
      const OcclusionDocument(masks: <OcclusionMask>[rectangle]).encode(),
    );
    expect(() => decoded!.masks.add(ellipse), throwsUnsupportedError);
  });
}
