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
    this.documentImageParts,
    this.continuation,
    this.maxOutputTokens,
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

  /// Изображения, которые план отправил image-частями (TASK 03).
  ///
  /// Контракт: это **префикс** [documentImages] в том же порядке. Планировщик
  /// строит `documentImages` как `imageParts + catalogOnly`, поэтому первые
  /// `documentImageParts.length` записей — части. `null` — легаси-режим: сервис
  /// сам выбирает части из каталога (`selectVisionDocumentImages`), как до
  /// TASK 03. Пустой список — «частей нет, только каталог».
  final List<DocumentImage>? documentImageParts;

  /// Компактное состояние уже созданных карточек (prompt-only, TASK 03).
  ///
  /// Сервис добавляет его в `<wishes>` после исходных пожеланий пользователя;
  /// исходный текст не переписывается. `null` — передавать нечего.
  final String? continuation;

  /// Максимум токенов ответа для этого запроса (из плана, D.2).
  ///
  /// `null` — взять лимит аккаунта/сервиса. Планировщик ограничивает резерв
  /// ожидаемым выводом фрагмента, поэтому `max_tokens` соответствует плану и
  /// не резервирует всё окно маленьких моделей.
  final int? maxOutputTokens;
}
