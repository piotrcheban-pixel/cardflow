import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:cardflow/domain/text/normalization.dart';

/// Нормализованный текст для дедупликации (SPEC A5/A8.5): нижний регистр,
/// `ё` → `е`, сжатые пробелы, без пунктуации.
String normalizeCardText(String value) => normalizeForComparison(value);

/// Хеш `front + "\u0000" + back` по нормализованным сторонам (SPEC A5).
///
/// Используется для дедупликации при импорте (A6.9), генерации (A8.5) и
/// ручном создании карточек.
String contentHashOf({required String front, required String back}) {
  final normalized =
      '${normalizeCardText(front)}\u0000${normalizeCardText(back)}';
  return sha256.convert(utf8.encode(normalized)).toString();
}
