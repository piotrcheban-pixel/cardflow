import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cardflow/api/images/image_dimensions.dart';

/// Размеры изображений по заголовку (фильтр картинок 7.14).
void main() {
  test('PNG: ширина/высота из IHDR', () {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 800, height: 450)),
    );
    final size = ImageDimensions.read(bytes);
    expect(size, isNotNull);
    expect(size!.width, 800);
    expect(size.height, 450);
    expect(size.isUsable, isTrue);
  });

  test('JPEG: ширина/высота из SOF', () {
    final bytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 1024, height: 768)),
    );
    final size = ImageDimensions.read(bytes);
    expect(size!.width, 1024);
    expect(size.height, 768);
  });

  test('WebP VP8X: canvas-размеры', () {
    expect(ImageDimensions.read(_webp(800, 450)), isNotNull);
    final size = ImageDimensions.read(_webp(800, 450))!;
    expect(size.width, 800);
    expect(size.height, 450);
  });

  test('неизвестный формат и мусор → null', () {
    expect(ImageDimensions.read(<int>[]), isNull);
    expect(ImageDimensions.read(<int>[1, 2, 3, 4, 5]), isNull);
    expect(ImageDimensions.read('<svg></svg>'.codeUnits), isNull);
  });

  test('фильтр: короткая сторона ≥ 400 и соотношение ≤ 3', () {
    expect(const ImageDimensions(800, 450).isUsable, isTrue);
    expect(const ImageDimensions(300, 200).isUsable, isFalse);
    expect(const ImageDimensions(1200, 300).isUsable, isFalse);
    expect(const ImageDimensions(400, 1200).isUsable, isTrue);
    expect(const ImageDimensions(100, 1000).isUsable, isFalse);
  });
}

Uint8List _webp(int width, int height) {
  final bytes = Uint8List(40);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  writeAscii(8, 'WEBP');
  writeAscii(12, 'VP8X');
  bytes[16] = 0x0A;
  final int w = width - 1;
  final int h = height - 1;
  bytes[24] = w & 0xFF;
  bytes[25] = (w >> 8) & 0xFF;
  bytes[26] = (w >> 16) & 0xFF;
  bytes[27] = h & 0xFF;
  bytes[28] = (h >> 8) & 0xFF;
  bytes[29] = (h >> 16) & 0xFF;
  return bytes;
}
