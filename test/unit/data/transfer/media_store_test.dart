import 'dart:io';
import 'dart:typed_data';

import 'package:cardflow/data/transfer/media_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Тесты файлового хранилища медиа (`MediaStore`).
///
/// Хранилище работает с относительными путями внутри корневого каталога;
/// выход за корень (path traversal) запрещён, запись атомарна.

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  late Directory tempRoot;
  late Directory root;
  late MediaStore store;

  Directory createTempDir() {
    final dir = Directory.systemTemp.createTempSync('cardflow_media_test_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    return dir;
  }

  setUp(() {
    tempRoot = createTempDir();
    root = Directory(p.join(tempRoot.path, 'media'));
    store = MediaStore(root);
  });

  group('MediaStore: запись и чтение', () {
    test(
      'writeMedia создаёт файл в корневом каталоге и читается обратно',
      () async {
        final content = _bytes(<int>[1, 2, 3, 255, 0]);

        await store.writeMedia(relativePath: 'image.bin', bytes: content);

        final file = File(p.join(root.path, 'image.bin'));
        expect(file.existsSync(), isTrue);
        expect(await file.readAsBytes(), content);
        expect(await store.readMedia('image.bin'), content);
      },
    );

    test('writeMedia создаёт вложенные каталоги', () async {
      await store.writeMedia(
        relativePath: p.join('decks', 'deck-1', 'photo.png'),
        bytes: _bytes(<int>[7, 8]),
      );

      final nested = File(p.join(root.path, 'decks', 'deck-1', 'photo.png'));
      expect(nested.existsSync(), isTrue);
      expect(
        await store.readMedia('decks/deck-1/photo.png'),
        _bytes(<int>[7, 8]),
      );
    });

    test('writeMedia создаёт сам корневой каталог, если его нет', () async {
      final missingRoot = Directory(p.join(tempRoot.path, 'created', 'media'));
      final createdStore = MediaStore(missingRoot);

      await createdStore.writeMedia(
        relativePath: 'a.bin',
        bytes: _bytes(<int>[1]),
      );

      expect(missingRoot.existsSync(), isTrue);
      expect(await createdStore.readMedia('a.bin'), _bytes(<int>[1]));
    });

    test('пустой файл допустим', () async {
      await store.writeMedia(relativePath: 'empty.bin', bytes: _bytes(<int>[]));

      expect(await store.readMedia('empty.bin'), isEmpty);
    });

    test('перезапись заменяет содержимое', () async {
      await store.writeMedia(relativePath: 'a.bin', bytes: _bytes(<int>[1, 2]));
      await store.writeMedia(relativePath: 'a.bin', bytes: _bytes(<int>[3]));

      expect(await store.readMedia('a.bin'), _bytes(<int>[3]));
    });

    test('после записи в каталоге не остаётся временных файлов', () async {
      await store.writeMedia(relativePath: 'a.bin', bytes: _bytes(<int>[1, 2]));
      await store.writeMedia(relativePath: 'a.bin', bytes: _bytes(<int>[3]));

      final names = root
          .listSync()
          .map((FileSystemEntity entity) => p.basename(entity.path))
          .toList();
      expect(names, <String>['a.bin']);
    });
  });

  group('MediaStore: отсутствующие файлы', () {
    test('чтение отсутствующего файла → null', () async {
      expect(await store.readMedia('нет.bin'), isNull);
    });

    test(
      'чтение отсутствующего файла в отсутствующем каталоге → null',
      () async {
        expect(await store.readMedia('нет/такого/файла.bin'), isNull);
      },
    );

    test('удаление отсутствующего файла не бросает', () async {
      await expectLater(store.deleteMedia('нет.bin'), completes);
    });

    test('deleteMedia удаляет файл', () async {
      await store.writeMedia(relativePath: 'a.bin', bytes: _bytes(<int>[1]));

      await store.deleteMedia('a.bin');

      expect(File(p.join(root.path, 'a.bin')).existsSync(), isFalse);
      expect(await store.readMedia('a.bin'), isNull);
    });
  });

  group('MediaStore: защита от выхода за корень', () {
    final List<String> traversalPaths = <String>[
      '../evil.bin',
      '..\\evil.bin',
      'nested/../../evil.bin',
      'nested\\..\\..\\evil.bin',
      '.',
      '',
    ];

    for (final String path in traversalPaths) {
      test('writeMedia("$path") → ArgumentError', () async {
        expect(
          () => store.writeMedia(relativePath: path, bytes: _bytes(<int>[1])),
          throwsArgumentError,
        );
      });

      test('readMedia("$path") → ArgumentError', () async {
        expect(() => store.readMedia(path), throwsArgumentError);
      });

      test('deleteMedia("$path") → ArgumentError', () async {
        expect(() => store.deleteMedia(path), throwsArgumentError);
      });
    }

    test('абсолютный путь → ArgumentError', () {
      final absolute = p.join(tempRoot.path, 'evil.bin');

      expect(
        () => store.writeMedia(relativePath: absolute, bytes: _bytes(<int>[1])),
        throwsArgumentError,
      );
    });

    test('путь с другим диском (Windows) → ArgumentError', () {
      expect(
        () => store.writeMedia(
          relativePath: 'C:/evil.bin',
          bytes: _bytes(<int>[1]),
        ),
        throwsArgumentError,
      );
    });

    test(
      'нормализованный безопасный путь ("nested/../a.bin") допустим',
      () async {
        await store.writeMedia(
          relativePath: 'nested/../a.bin',
          bytes: _bytes(<int>[5]),
        );

        expect(File(p.join(root.path, 'a.bin')).existsSync(), isTrue);
        expect(await store.readMedia('a.bin'), _bytes(<int>[5]));
      },
    );
  });
}
