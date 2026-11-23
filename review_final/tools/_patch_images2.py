import io

p = 'review_final/tools/render_images_test.dart'
s = io.open(p, encoding='utf-8').read()

# 1) после precache — дать AnimatedSwitcher завершить fade (два кадра).
old = """        await tester.runAsync(() async {
          await precacheImage(
            MemoryImage(png),
            tester.element(find.byType(Scaffold).first),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump();
        final Finder image = find.byKey("""
new = """        await tester.runAsync(() async {
          await precacheImage(
            MemoryImage(png),
            tester.element(find.byType(Scaffold).first),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump(const Duration(milliseconds: 220));
        final Finder image = find.byKey("""
assert old in s
s = s.replace(old, new)

# 2) два изображения: байты создаются ДО сборки дерева и передаются те же.
old2 = """    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1706.7, 940);
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = 1.24;
    addTearDown(() => AppAdaptive.debugOverride = null);
    await tester.pumpWidget(
      _app(
        factor: 1.24,
        textScale: 0.9,
        card: card,
        bytes: <String, Uint8List>{
          'media-1': _patternPng(1200, 900),
          'media-2': _patternPng(960, 1371),
        },
      ),
    );"""
new2 = """    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1706.7, 940);
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = 1.24;
    addTearDown(() => AppAdaptive.debugOverride = null);
    final Map<String, Uint8List> twoBytes = <String, Uint8List>{
      'media-1': _patternPng(1200, 900),
      'media-2': _patternPng(960, 1371),
    };
    await tester.pumpWidget(
      _app(
        factor: 1.24,
        textScale: 0.9,
        card: card,
        bytes: twoBytes,
      ),
    );"""
assert old2 in s
s = s.replace(old2, new2)

old3 = """    final Map<String, Uint8List> twoBytes = <String, Uint8List>{
      'media-1': _patternPng(1200, 900),
      'media-2': _patternPng(960, 1371),
    };
    await tester.runAsync(() async {
      for (final Uint8List bytes in twoBytes.values) {
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(Scaffold).first),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    for (final String id in <String>['media-1', 'media-2']) {"""
new3 = """    await tester.runAsync(() async {
      for (final Uint8List bytes in twoBytes.values) {
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(Scaffold).first),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 220));
    for (final String id in <String>['media-1', 'media-2']) {"""
assert old3 in s
s = s.replace(old3, new3)

io.open(p, 'w', encoding='utf-8').write(s)
print('patched2')
