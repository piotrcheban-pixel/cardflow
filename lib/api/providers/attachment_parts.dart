/// Провайдерские части запроса для вложений (ADR-022, итерация 7.8).
///
/// Один файл на три протокола: OpenAI Chat Completions (`image_url`),
/// Gemini (`inlineData`) и Anthropic (`image`/`document`). Вложения передаются
/// только inline (base64), без внешних файловых API и WebView.
library;

import 'dart:convert';

import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Base64-содержимое вложения для JSON-части.
String attachmentBase64(GenerationAttachment attachment) =>
    base64Encode(attachment.bytes);

/// Data URI для OpenAI `image_url`.
String attachmentDataUri(GenerationAttachment attachment) =>
    'data:${attachment.mimeType};base64,${attachmentBase64(attachment)}';

/// Содержимое пользовательского сообщения OpenAI/OpenAI-compatible.
///
/// Без вложений — строка (совместимо с прежними серверами), с вложениями —
/// массив частей `text` + `image_url`. Если у вложения есть [label], перед
/// изображением идёт текстовая часть с идентификатором каталога (ADR-037).
Object openAiUserContent(
  String userContent,
  List<GenerationAttachment> images,
) {
  if (images.isEmpty) return userContent;
  for (final GenerationAttachment image in images) {
    if (image.isPdf) {
      throw const GenerationException(GenerationErrorCode.pdfScanUnsupported);
    }
  }
  return <Object?>[
    <String, Object?>{'type': 'text', 'text': userContent},
    for (final GenerationAttachment image in images) ...<Object?>[
      if (image.label != null)
        <String, Object?>{'type': 'text', 'text': image.label},
      <String, Object?>{
        'type': 'image_url',
        'image_url': <String, Object?>{'url': attachmentDataUri(image)},
      },
    ],
  ];
}

/// Части Gemini `contents[0].parts`: текст + `inlineData` для каждого вложения.
List<Object?> geminiParts(
  String userContent,
  List<GenerationAttachment> images,
) {
  return <Object?>[
    <String, Object?>{'text': userContent},
    for (final GenerationAttachment image in images) ...<Object?>[
      if (image.label != null) <String, Object?>{'text': image.label},
      <String, Object?>{
        'inlineData': <String, Object?>{
          'mimeType': image.mimeType,
          'data': attachmentBase64(image),
        },
      },
    ],
  ];
}

/// Содержимое пользовательского сообщения Anthropic.
///
/// Изображения — блок `image`, PDF-сканы — блок `document`; без вложений —
/// прежняя строка. Подпись каталога — текстовый блок перед изображением.
Object anthropicUserContent(
  String userContent,
  List<GenerationAttachment> images,
) {
  if (images.isEmpty) return userContent;
  return <Object?>[
    <String, Object?>{'type': 'text', 'text': userContent},
    for (final GenerationAttachment image in images) ...<Object?>[
      if (image.label != null)
        <String, Object?>{'type': 'text', 'text': image.label},
      if (image.isPdf)
        <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': image.mimeType,
            'data': attachmentBase64(image),
          },
        }
      else
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': image.mimeType,
            'data': attachmentBase64(image),
          },
        },
    ],
  ];
}
