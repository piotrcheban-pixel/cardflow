import io

p = 'review_final/tools/render_images_test.dart'
s = io.open(p, encoding='utf-8').read()

old1 = """        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump();
        final Finder image = find.byKey("""
new1 = """        await tester.runAsync(() async {
          await precacheImage(
            MemoryImage(png),
            tester.element(find.byType(Scaffold).first),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump();
        final Finder image = find.byKey("""
assert old1 in s
s = s.replace(old1, new1)

old2 = """    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    for (final String id in <String>['media-1', 'media-2']) {"""
new2 = """    final Map<String, Uint8List> twoBytes = <String, Uint8List>{
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
assert old2 in s
s = s.replace(old2, new2)
io.open(p, 'w', encoding='utf-8').write(s)
print('patched')
