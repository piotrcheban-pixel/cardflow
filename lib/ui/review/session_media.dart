/// Загрузка медиа сессии: байты + атрибуция (итерация 7.14).
///
/// Классика, лента и тренировка показывают одно и то же изображение карточки и
/// полноэкранный просмотр с атрибуцией, поэтому загрузка вынесена в один helper:
/// по карточкам собираются `media.id`, затем одним проходом читаются байты и
/// метаданные (`<путь>.meta.json`).
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Медиа сессии: байты и метаданные по `media.id`.
class SessionMedia {
  /// Создаёт контейнер медиа.
  const SessionMedia({
    this.bytes = const <String, Uint8List>{},
    this.metadata = const <String, MediaMetadata>{},
  });

  /// Пустой набор (нет картинок).
  static const SessionMedia empty = SessionMedia();

  /// Байты по `media.id`.
  final Map<String, Uint8List> bytes;

  /// Атрибуция по `media.id`.
  final Map<String, MediaMetadata> metadata;
}

/// Читает медиа всех карточек сессии.
Future<SessionMedia> loadSessionMedia(
  WidgetRef ref,
  Iterable<Card> cards,
) async {
  final Set<String> mediaIds = <String>{
    for (final Card card in cards) ...card.mediaIds,
  };
  if (mediaIds.isEmpty) return SessionMedia.empty;
  final repository = ref.read(cardMediaRepositoryProvider);
  final Map<String, Uint8List> bytes = await repository.readMedia(mediaIds);
  final Map<String, MediaMetadata> metadata = await repository.readMetadata(
    mediaIds,
  );
  return SessionMedia(bytes: bytes, metadata: metadata);
}

/// Перечитывает медиа [cards], объединяя с уже загруженными [previous].
///
/// Нужно кнопке «Повторить» в состоянии ошибки изображения: файл мог стать
/// доступен (внешний диск, синхронизация, повторная запись). Ошибка чтения не
/// подменяет данные — возвращается [previous].
Future<SessionMedia> reloadSessionMedia(
  WidgetRef ref,
  Iterable<Card> cards,
  SessionMedia previous,
) async {
  final Set<String> mediaIds = <String>{
    for (final Card card in cards) ...card.mediaIds,
  };
  if (mediaIds.isEmpty) return previous;
  try {
    final repository = ref.read(cardMediaRepositoryProvider);
    final Map<String, Uint8List> bytes = await repository.readMedia(mediaIds);
    final Map<String, MediaMetadata> metadata = await repository.readMetadata(
      mediaIds,
    );
    return SessionMedia(
      bytes: <String, Uint8List>{...previous.bytes, ...bytes},
      metadata: <String, MediaMetadata>{...previous.metadata, ...metadata},
    );
  } on Object {
    return previous;
  }
}
