/// Интерфейс провайдера картинок и кандидат выдачи (итерация 7.14).
///
/// Провайдер отвечает только за поиск: он возвращает кандидатов (URL + данные
/// атрибуции), а скачивание, проверку формата/размера/пропорций, ретраи и
/// кэш выполняет цепочка `ImageSearchService`. Так один набор фильтров
/// действует для всех источников, а провайдер легко подменить в тестах.
library;

import 'package:cardflow/domain/generation/card_image_kind.dart';

/// Запрос к провайдеру.
class ImageProviderQuery {
  /// Создаёт запрос.
  const ImageProviderQuery({required this.query, required this.kind});

  /// Поисковый запрос на английском (уже нормализованный).
  final String query;

  /// Вид иллюстрации: подсказывает провайдеру тип выдачи.
  final GeneratedCardImageKind kind;

  @override
  String toString() => 'ImageProviderQuery($query, ${kind.wireName})';
}

/// Кандидат выдачи провайдера (ещё не скачан).
class ImageCandidate {
  /// Создаёт кандидата.
  const ImageCandidate({
    required this.provider,
    required this.url,
    this.attribution,
    this.author,
    this.license,
    this.width,
    this.height,
  });

  /// Имя провайдера (`wikimedia`, `wikipedia`, `openverse`, `pixabay`, `pexels`).
  final String provider;

  /// URL для скачивания (http/https).
  final String url;

  /// Готовая строка атрибуции для показа.
  final String? attribution;

  /// Автор изображения.
  final String? author;

  /// Лицензия изображения.
  final String? license;

  /// Ширина, если провайдер её сообщил (позволяет отсеять до скачивания).
  final int? width;

  /// Высота, если провайдер её сообщил.
  final int? height;

  /// Подсказка о размере, если провайдер сообщил обе стороны.
  bool get hasKnownSize => width != null && height != null;

  @override
  String toString() => 'ImageCandidate($provider, $url)';
}

/// Источник кандидатов картинок.
abstract interface class ImageProvider {
  /// Имя провайдера для метаданных `MediaStore`.
  String get name;

  /// Ищет кандидатов; ошибка сети/API пробрасывается вызывающему (цепочка
  /// решает, повторить запрос или перейти к следующему источнику).
  Future<List<ImageCandidate>> search(ImageProviderQuery query);
}
