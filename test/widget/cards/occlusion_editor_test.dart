import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/ui/cards/occlusion_mask_editor.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('рисование прямоугольной и эллиптической маски', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    var document = const OcclusionDocument();
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              height: 560,
              child: StatefulBuilder(
                builder: (context, setState) => OcclusionMaskEditor(
                  imageBytes: Uint8List.fromList(png),
                  document: document,
                  onChanged: (value) => setState(() => document = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('occlusion-editor-canvas'));

    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(document.masks, hasLength(1));
    expect(document.masks.single.shape, OcclusionShape.rectangle);
    expect(document.masks.single.width, greaterThan(0));
    expect(document.masks.single.height, greaterThan(0));
    expect(
      find.byKey(const ValueKey('occlusion-editor-mask-mask-1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Эллипс'));
    await tester.pump();
    final second = await tester.startGesture(tester.getCenter(canvas));
    await second.moveBy(const Offset(60, 0));
    await tester.pump();
    await second.moveBy(const Offset(0, 40));
    await tester.pump();
    await second.up();
    await tester.pumpAndSettle();
    expect(document.masks, hasLength(2));
    expect(document.masks.last.shape, OcclusionShape.ellipse);

    await tester.tap(find.byKey(const ValueKey('occlusion-delete-mask-1')));
    await tester.pump();
    expect(document.masks, hasLength(1));
    expect(document.masks.single.shape, OcclusionShape.ellipse);
  });

  testWidgets('вертикальное начало жеста рисует маску внутри прокрутки', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    var document = const OcclusionDocument();
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              height: 1400,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 500,
                  height: 560,
                  child: StatefulBuilder(
                    builder: (context, setState) => OcclusionMaskEditor(
                      imageBytes: Uint8List.fromList(png),
                      document: document,
                      onChanged: (value) => setState(() => document = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('occlusion-editor-canvas'));

    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(document.masks, hasLength(1));
    expect(document.masks.single.width, greaterThan(0));
    expect(document.masks.single.height, greaterThan(0));
  });
}
