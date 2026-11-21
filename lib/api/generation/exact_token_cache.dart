/// Кэш нативного подсчёта токенов входа (ADR-040 §3.5.1, 7.18.1 §2.2).
///
/// Планировщик не ходит в сеть; конвейер делает **один** запрос `count_tokens`
/// на план и повторяет его только для изменённого содержимого. Ключ кэша —
/// хэш содержимого (системный промпт + пользовательское сообщение + аккаунт +
/// модель): тело запроса, ключи и их хэши в кэш не попадают.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Версия формы запроса подсчёта: при изменении набора частей ключ меняется.
///
/// Кэш живёт в памяти и не сериализуется, но версия защитывает случай
/// переиспользования экземпляра приложения после обновления кода.
const String exactTokenRequestVersion = 'multimodal-1';

/// Стабильный ключ кэша подсчёта: хэш содержимого запроса.
///
/// Включает протокол, адрес, модель и аккаунт: у разных моделей/провайдеров
/// один и тот же текст токенизируется по-разному. Ключ API не участвует.
/// [attachments] входят **дайджестами байтов** и MIME-типами: изменение
/// изображения при том же тексте обязано дать другой ключ.
String exactTokenCacheKey({
  required ProviderAccount account,
  required String systemPrompt,
  required String userContent,
  List<GenerationAttachment> attachments = const <GenerationAttachment>[],
}) {
  final StringBuffer payload = StringBuffer()
    ..write(exactTokenRequestVersion)
    ..write('\u0000')
    ..write(account.id)
    ..write('\u0000')
    ..write(account.protocol.wireName)
    ..write('\u0000')
    ..write(account.baseUrl.trim())
    ..write('\u0000')
    ..write(account.modelId.trim())
    ..write('\u0000')
    ..write(systemPrompt)
    ..write('\u0000')
    ..write(userContent);
  // Мультимодальные части: дайджест байтов + MIME + подпись каталога. Сами
  // байты и ключ API в ключ не попадают — только хэш содержимого.
  for (final GenerationAttachment attachment in attachments) {
    payload
      ..write('\u0000')
      ..write(documentImageDigest(attachment.bytes))
      ..write('\u0000')
      ..write(attachment.mimeType)
      ..write('\u0000')
      ..write(attachment.label ?? '');
  }
  return sha256.convert(utf8.encode(payload.toString())).toString();
}

/// In-memory кэш результатов нативного подсчёта.
///
/// Хранит и удачный, и неудачный результат: повторять неудачный сетевой
/// запрос на каждый план — лишние обращения (требование §2.2). Ошибка
/// деградирует к оценке, а не к исключению.
class ExactTokenCountCache {
  /// Создаёт кэш; [maxEntries] — предохранитель от роста за сессию.
  ExactTokenCountCache({this.maxEntries = 64}) : assert(maxEntries > 0);

  /// Максимум записей (старые вытесняются).
  final int maxEntries;

  final Map<String, ExactTokenCount> _entries = <String, ExactTokenCount>{};

  /// Сколько раз реально вызывали счётчик (для тестов/диагностики).
  int loads = 0;

  /// Сколько раз отдавали значение из кэша.
  int hits = 0;

  /// Число записей.
  int get length => _entries.length;

  /// Возвращает результат из кэша или загружает его [load].
  Future<ExactTokenCount> countOrLoad({
    required String key,
    required Future<ExactTokenCount> Function() load,
  }) async {
    final ExactTokenCount? cached = _entries[key];
    if (cached != null) {
      hits++;
      return cached;
    }
    loads++;
    final ExactTokenCount result = await load();
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = result;
    return result;
  }

  /// Очищает кэш (смена ключа/аккаунта в тестах).
  void clear() => _entries.clear();
}
