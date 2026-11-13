import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Собирает ZIP из произвольных байтовых записей.
Uint8List buildZip(Map<String, List<int>> entries) {
  final Archive archive = Archive();
  entries.forEach((String name, List<int> bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Matcher isUnreadableFile() => throwsA(
  isA<ParserException>().having(
    (ParserException e) => e.code,
    'code',
    ParserErrorCode.unreadableFile,
  ),
);

/// Красная фаза итерации 3a (добито в fix-итерации ревью): `SecureZip`.
void main() {
  group('SecureZip: чтение записей', () {
    test('entryNames/contains/readBytes/readUtf8/readXml', () {
      final SecureZip zip = SecureZip(
        buildZip(<String, List<int>>{
          'a.xml': utf8.encode('<root>Привет</root>'),
          'b.bin': <int>[1, 2, 3],
        }),
      );

      expect(zip.entryNames, containsAll(<String>['a.xml', 'b.bin']));
      expect(zip.contains('a.xml'), isTrue);
      expect(zip.contains('missing.xml'), isFalse);
      expect(zip.readBytes('b.bin'), <int>[1, 2, 3]);
      expect(zip.readUtf8('a.xml'), '<root>Привет</root>');
      expect(zip.readXml('a.xml').rootElement.name.local, 'root');
    });

    test('отсутствующая запись → ParserException(unreadableFile)', () {
      final SecureZip zip = SecureZip(
        buildZip(<String, List<int>>{'a.xml': utf8.encode('<a/>')}),
      );
      expect(() => zip.readBytes('missing.xml'), isUnreadableFile());
      expect(() => zip.readXml('missing.xml'), isUnreadableFile());
    });

    test('некорректный XML → ParserException(unreadableFile)', () {
      final SecureZip zip = SecureZip(
        buildZip(<String, List<int>>{'bad.xml': utf8.encode('<a><b>')}),
      );
      expect(() => zip.readXml('bad.xml'), isUnreadableFile());
    });
  });

  group('SecureZip: лимиты ADR-010', () {
    test('слишком много записей → unreadableFile', () {
      final Uint8List bytes = buildZip(<String, List<int>>{
        for (int i = 0; i < 5; i++) 'f$i.txt': <int>[i],
      });
      expect(
        () => SecureZip(bytes, limits: const SecureZipLimits(maxEntries: 3)),
        isUnreadableFile(),
      );
    });

    test('запись больше лимита → unreadableFile', () {
      final Uint8List bytes = buildZip(<String, List<int>>{
        'big.xml': List<int>.filled(2000, 0x41),
      });
      expect(
        () => SecureZip(
          bytes,
          limits: const SecureZipLimits(maxEntryBytes: 1000),
        ),
        isUnreadableFile(),
      );
    });

    test('суммарный объём больше лимита → unreadableFile', () {
      final Uint8List bytes = buildZip(<String, List<int>>{
        'a.xml': List<int>.filled(600, 0x41),
        'b.xml': List<int>.filled(600, 0x42),
      });
      expect(
        () => SecureZip(
          bytes,
          limits: const SecureZipLimits(maxTotalBytes: 1000),
        ),
        isUnreadableFile(),
      );
    });

    test('лимиты по умолчанию пропускают обычный документ', () {
      expect(
        () => SecureZip(
          buildZip(<String, List<int>>{'a.xml': List<int>.filled(100, 0x41)}),
        ),
        returnsNormally,
      );
    });
  });

  group('SecureZip: повреждённый архив', () {
    test('битые байты без ZIP-структуры → unreadableFile', () {
      expect(
        () => SecureZip(Uint8List.fromList(<int>[1, 2, 3, 4])),
        isUnreadableFile(),
      );
    });

    test('обрезанный архив → unreadableFile (strict decode)', () {
      final Uint8List valid = buildZip(<String, List<int>>{
        'a.xml': utf8.encode('<root>${'x' * 100}</root>'),
      });
      final Uint8List truncated = valid.sublist(0, valid.length ~/ 2);
      expect(() => SecureZip(truncated), isUnreadableFile());
    });
  });

  group('decodeXmlText: кодировки XML-записей', () {
    test('UTF-8 BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('<root>Текст</root>'),
      ]);
      expect(decodeXmlText(bytes), '<root>Текст</root>');
    });

    test('UTF-16 LE и BE с BOM', () {
      Uint8List utf16(String text, {required bool littleEndian}) {
        final List<int> bytes = <int>[];
        for (final int codeUnit in text.codeUnits) {
          if (littleEndian) {
            bytes
              ..add(codeUnit & 0xFF)
              ..add((codeUnit >> 8) & 0xFF);
          } else {
            bytes
              ..add((codeUnit >> 8) & 0xFF)
              ..add(codeUnit & 0xFF);
          }
        }
        return Uint8List.fromList(bytes);
      }

      for (final bool littleEndian in <bool>[true, false]) {
        final List<int> marker = littleEndian
            ? <int>[0xFF, 0xFE]
            : <int>[0xFE, 0xFF];
        final Uint8List bytes = Uint8List.fromList(<int>[
          ...marker,
          ...utf16('<root>Текст</root>', littleEndian: littleEndian),
        ]);
        expect(decodeXmlText(bytes), '<root>Текст</root>');
      }
    });

    test('некорректный UTF-8 → unreadableFile', () {
      expect(
        () => decodeXmlText(Uint8List.fromList(<int>[0xC3, 0x28])),
        isUnreadableFile(),
      );
    });
  });
}
