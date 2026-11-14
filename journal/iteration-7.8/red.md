# Красная фаза — итерация 7.8 (2026-11-15)

Контракт новых тестов зафиксирован до реализации. Полный вывод — `journal/iteration-7.8/red-phase.txt`.

## Компиляционные (новый контракт отсутствует)

```
GenerationException: No named parameter with the name 'providerReason'
test/unit/ui/generation_error_message_test.dart: ... Member not found: 'visionUnsupported'
test/unit/api/generation/card_generation_service_test.dart: ... Member not found:
  'GenerationRequest.images'
test/unit/domain/text_sanitizer_test.dart: Error: couldn't resolve package
  'cardflow/domain/text/text_sanitizer.dart'
test/unit/domain/generation_attachment_test.dart: ... generation_attachment.dart
```

Это ожидаемые red-ошибки новых публичных контрактов: `TextSanitizer`, `GenerationAttachment`,
`supportsVision`, коды вложений, `providerReason`, `images` в запросе.

## Assertion-level (поведение, которое видел пользователь)

```
test/unit/ui/parser_error_message_test.dart: пустой текст: сообщение говорит о скане и пустой форме [E]
  Expected: contains 'скан'
    Actual: 'В файле нет текста'
     Which: does not contain 'скан'
```

То есть старое сообщение не объясняло скан/пустую форму — приёмка шага 1 требовала
«В файле нет текста (скан или пустая форма)».

## Что дополнительно проверялось после реализации

- Word `\u0000`/`\u000B` → `DOCX` текст без управляющих (тест в `docx_parser_test.dart`).
- пустой текст → `noMaterials`, `adapter.buildCalls == 0`, `transport.calls == 0`.
- `supportsVision=true` + PNG → `adapter.buildArgs.images`; `false` → `visionUnsupported`.
- PDF-скан: OpenAI → `pdfScanUnsupported`, Anthropic/Gemini → PDF-часть.
- 400 с `invalid characters in content` → `providerReason` в HTTP/UI; HTML/секреты не утекают.
- production-граф: `image_url` в HTTP-теле; DeepSeek + изображение → ошибка без HTTP.
