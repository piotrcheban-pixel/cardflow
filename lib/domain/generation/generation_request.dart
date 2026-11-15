/// Запрос на генерацию карточек (SPEC A8.5 шаги 4–7).
///
/// Один вызов модели на один фрагмент; аккаунт провайдера несёт протокол,
/// адрес, модель и id для ключа (ADR-020). Вложения (картинки/PDF-сканы)
/// передаются как inline-части только при поддержке Vision (итерация 7.8).
library;

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Параметры одного вызова модели (чанкинг — в пайплайне).
class GenerationRequest {
  /// Создаёт запрос.
  const GenerationRequest({
    required this.account,
    required this.materialsText,
    required this.limit,
    this.wishes,
    this.images = const <GenerationAttachment>[],
    this.documentImages = const <DocumentImage>[],
  });

  /// Провайдер: протокол, адрес, модель и id ключа.
  final ProviderAccount account;

  /// Текст фрагмента материалов (из парсеров A8.3). Пустой допустим, если
  /// есть [images]: тогда материалы — приложенные изображения/скан.
  final String materialsText;

  /// Максимальное число карточек в ответе (`<limit>`, A8.1).
  final int limit;

  /// Необязательные пожелания пользователя по содержанию (A6.8).
  final String? wishes;

  /// Вложения фрагмента: изображения или PDF-скан.
  final List<GenerationAttachment> images;

  /// Каталог изображений из документов с id (`img1…`) для `<images>` (fix-gen).
  final List<DocumentImage> documentImages;
}
