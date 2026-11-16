/// Метаданные медиа карточки: атрибуция и источник (итерация 7.14).
///
/// `media` хранит только путь/MIME/размер (SPEC A5), поэтому провайдер,
/// ссылка, автор, лицензия, флаг заглушки и исходный запрос модели
/// сохраняются рядом с файлом — в побочном JSON `<путь>.meta.json`
/// (`MediaStore`). Схема БД не меняется.
///
/// Домен без Flutter: разметку/показ атрибуции делает UI.
library;

import 'package:cardflow/domain/generation/card_image_kind.dart';

/// Метаданные одного медиафайла.
class MediaMetadata {
  /// Создаёт метаданные.
  const MediaMetadata({
    this.provider,
    this.sourceUrl,
    this.author,
    this.license,
    this.isPlaceholder = false,
    this.query,
    this.fallbackQuery,
    this.kind,
  });

  /// Провайдер (`wikimedia`, `wikipedia`, `openverse`, `pixabay`, `pexels`,
  /// `file`, `placeholder`).
  final String? provider;

  /// URL источника (для атрибуции).
  final String? sourceUrl;

  /// Автор изображения.
  final String? author;

  /// Лицензия изображения.
  final String? license;

  /// Изображение — локальная заглушка.
  final bool isPlaceholder;

  /// Исходный запрос модели (для «Найти картинку заново»).
  final String? query;

  /// Запасной запрос модели.
  final String? fallbackQuery;

  /// Вид иллюстрации.
  final GeneratedCardImageKind? kind;

  /// Готовая строка атрибуции для показа: «автор · лицензия».
  String? get attributionLine {
    final List<String> parts = <String>[
      if (author != null && author!.trim().isNotEmpty) author!.trim(),
      if (license != null && license!.trim().isNotEmpty) license!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Версия формата побочного JSON.
  static const int jsonVersion = 1;

  /// JSON для `MediaStore` (`version` — для будущих миграций формата).
  Map<String, Object?> toJson() => <String, Object?>{
    'version': jsonVersion,
    if (provider != null) 'provider': provider,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (author != null) 'author': author,
    if (license != null) 'license': license,
    'isPlaceholder': isPlaceholder,
    if (query != null) 'query': query,
    if (fallbackQuery != null) 'fallbackQuery': fallbackQuery,
    if (kind != null) 'kind': kind!.wireName,
  };

  /// Разбирает JSON; `null` — не объект/неизвестная версия.
  static MediaMetadata? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? version = json['version'];
    if (version is int && version > jsonVersion) return null;
    return MediaMetadata(
      provider: _stringOf(json['provider']),
      sourceUrl: _stringOf(json['sourceUrl']),
      author: _stringOf(json['author']),
      license: _stringOf(json['license']),
      isPlaceholder: json['isPlaceholder'] == true,
      query: _stringOf(json['query']),
      fallbackQuery: _stringOf(json['fallbackQuery']),
      kind: GeneratedCardImageKind.tryParse(json['kind']),
    );
  }

  /// Копия с изменёнными полями.
  MediaMetadata copyWith({
    String? provider,
    String? sourceUrl,
    String? author,
    String? license,
    bool? isPlaceholder,
    String? query,
    String? fallbackQuery,
    GeneratedCardImageKind? kind,
  }) => MediaMetadata(
    provider: provider ?? this.provider,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    author: author ?? this.author,
    license: license ?? this.license,
    isPlaceholder: isPlaceholder ?? this.isPlaceholder,
    query: query ?? this.query,
    fallbackQuery: fallbackQuery ?? this.fallbackQuery,
    kind: kind ?? this.kind,
  );

  static String? _stringOf(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() =>
      'MediaMetadata(provider: $provider, placeholder: $isPlaceholder, '
      'license: $license)';
}
