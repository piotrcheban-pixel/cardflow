/// Сборка провайдеров цепочки картинок (итерация 7.14).
///
/// Обязательные источники без ключа — Wikimedia Commons, Wikipedia, Openverse.
/// Pixabay и Pexels добавляются только при заданном ключе: без ключа провайдера
/// в цепочке нет, и его ошибки не тратят бюджет карточки.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/openverse_image_provider.dart';
import 'package:cardflow/api/images/pexels_image_provider.dart';
import 'package:cardflow/api/images/pixabay_image_provider.dart';
import 'package:cardflow/api/images/wikimedia_image_provider.dart';
import 'package:cardflow/api/images/wikipedia_image_provider.dart';

/// Провайдеры в порядке приоритета (Commons → Wikipedia → Openverse → …).
List<ImageProvider> buildImageProviders({
  required Dio dio,
  String? pixabayApiKey,
  String? pexelsApiKey,
}) {
  return <ImageProvider>[
    WikimediaImageProvider(dio: dio),
    WikipediaImageProvider(dio: dio),
    OpenverseImageProvider(dio: dio),
    if (pixabayApiKey != null && pixabayApiKey.trim().isNotEmpty)
      PixabayImageProvider(dio: dio, apiKey: pixabayApiKey),
    if (pexelsApiKey != null && pexelsApiKey.trim().isNotEmpty)
      PexelsImageProvider(dio: dio, apiKey: pexelsApiKey),
  ];
}
