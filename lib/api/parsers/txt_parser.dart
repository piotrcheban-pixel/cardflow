import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:enough_convert/enough_convert.dart';

/// Парсер TXT/MD: чтение байтов с явным определением кодировки (SPEC A8.3).
///
/// Порядок: BOM UTF-8 → BOM UTF-16 → строгий UTF-8 → cp1251/KOI8-R по
/// вероятностной оценке русских букв (ADR-010). Формат (`txt` или `md`)
/// задаётся в конструкторе.
class TxtParser implements DocumentParser {
  /// Создаёт парсер текста; [format] — [DocumentFormat.txt] или `.md`.
  const TxtParser({this.format = DocumentFormat.txt});

  @override
  final DocumentFormat format;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final DecodedText decoded = decodeTextBytes(bytes);
    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
      metadata: ParsedDocumentMetadata(encoding: decoded.encoding),
    );
    builder.addLines(decoded.text.split('\n'));
    return builder.build();
  }
}

/// Результат определения кодировки: текст и имя кодировки (для метаданных).
class DecodedText {
  /// Создаёт результат декодирования.
  const DecodedText({required this.text, required this.encoding});

  /// Декодированный текст.
  final String text;

  /// Название кодировки: `utf-8`, `utf-8-bom`, `utf-16le`, `utf-16be`,
  /// `windows-1251`, `koi8-r`.
  final String encoding;
}

/// Определяет кодировку и декодирует байты текстового файла (ADR-010).
DecodedText decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return DecodedText(
      text: _decodeUtf8Strict(bytes.sublist(3)),
      encoding: 'utf-8-bom',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
      encoding: 'utf-16le',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
      encoding: 'utf-16be',
    );
  }
  final String? utf8Text = _tryDecodeUtf8(bytes);
  if (utf8Text != null) {
    return DecodedText(text: utf8Text, encoding: 'utf-8');
  }
  const Windows1251Codec cp1251 = Windows1251Codec();
  const Koi8rCodec koi8r = Koi8rCodec();
  final String cp1251Text = cp1251.decode(bytes);
  final String koi8rText = koi8r.decode(bytes);
  final double cp1251Score = _russianLetterScore(cp1251Text);
  final double koi8rScore = _russianLetterScore(koi8rText);
  // При равенстве предпочитаем cp1251: она чаще встречается в русских файлах.
  if (koi8rScore > cp1251Score) {
    return DecodedText(text: koi8rText, encoding: 'koi8-r');
  }
  return DecodedText(text: cp1251Text, encoding: 'windows-1251');
}

String? _tryDecodeUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

String _decodeUtf8Strict(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // BOM обещал UTF-8 — декодируем с заменой, чтобы не терять файл целиком.
    return utf8.decode(bytes, allowMalformed: true);
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final int evenLength = bytes.length - bytes.length % 2;
  final List<int> codeUnits = <int>[];
  for (int i = 0; i < evenLength; i += 2) {
    final int first = bytes[i];
    final int second = bytes[i + 1];
    codeUnits.add(littleEndian ? (second << 8) | first : (first << 8) | second);
  }
  return String.fromCharCodes(codeUnits);
}

/// Частоты русских букв (на 1000 символов), для вероятностной оценки кодировки.
const Map<String, double> _russianFrequencies = <String, double>{
  'о': 109.7,
  'е': 84.5,
  'а': 80.1,
  'и': 73.5,
  'н': 67.0,
  'т': 62.6,
  'с': 54.7,
  'р': 47.3,
  'в': 45.4,
  'л': 44.0,
  'к': 34.9,
  'м': 32.1,
  'д': 29.8,
  'п': 28.1,
  'у': 26.2,
  'я': 20.1,
  'ы': 19.0,
  'ь': 17.4,
  'г': 17.0,
  'з': 16.5,
  'б': 15.9,
  'ч': 14.4,
  'й': 12.1,
  'х': 9.7,
  'ж': 9.4,
  'ш': 7.3,
  'ю': 6.4,
  'ц': 4.8,
  'щ': 3.6,
  'э': 3.2,
  'ф': 2.6,
  'ъ': 0.4,
  'ё': 0.4,
};

/// Средняя логарифмическая «правдоподобность» русских букв в тексте.
///
/// Для правильной кодировки буквы распределены как в русском языке; неверная
/// раскладка даёт другой набор частот и меньшую оценку.
double _russianLetterScore(String text) {
  double total = 0;
  int letters = 0;
  for (final int rune in text.runes) {
    final String letter = String.fromCharCode(rune).toLowerCase();
    final double? frequency = _russianFrequencies[letter];
    if (frequency != null) {
      total += math.log(frequency);
      letters++;
    }
  }
  if (letters == 0) {
    return double.negativeInfinity;
  }
  return total / letters;
}
