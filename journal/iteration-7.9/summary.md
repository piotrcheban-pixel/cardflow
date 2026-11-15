# Итерация 7.9 — «Фиксы UI, PDF-сканы и Rich-генерация с поиском картинок»

**Статус:** завершена локально; push/CI — по команде владельца (см. итог).

## Что сделано

1. **Лента.** Обратная сторона 3D-переворота получает контр-поворот
   `Matrix4.rotationY(pi)` — текст читается слева направо. Widget-тест проверяет знак `m00`
   у видимой обратной стороны и после анимации.
2. **PDF-сканы (ADR-023 §1).** Если PDF-парсер извлёк < 50 символов или поднял `scannedPdf`,
   `PdfScanRenderer` (PDFium pdfrx + `package:image`) рендерит первые ≤ 4 страницы в PNG
   (ширина ≤ 1600 px, 2× от 72 dpi) в изоляте. Страницы одного PDF имеют `groupKey` и уходят
   **одним** фрагментом; `generation_jobs.files` не дублирует имя. Модель без Vision получает
   `pdfScanVisionRequired`; при сбое рендера — fallback на PDF-документ для Anthropic/Gemini.
3. **Схема и промпт `gen-ru-v3` (ADR-023 §2).** Канон получает `image_query: string|null`
   (required в strict-схеме) и `card_type: occlusion`; промпт дополнен правилами про
   англоязычный `image_query`, обязательность для occlusion и запрет картинок при wishes.
4. **Поиск картинок.** `ImageSearchService` поверх открытого Openverse API без ключа:
   CC0/PDM/CC BY/CC BY-SA, `page_size=5`, User-Agent, троттлинг 1 запрос/с, thumbnail → fallback
   оригинал, JPEG/PNG по сигнатуре, ≤ 5 МБ. Любая ошибка → `null`; генерация продолжается.
5. **Пайплайн (ADR-023 §3–4).** После дедупликации `image_query` разрешается через доменный порт
   `CardImageFinder` с кэшем на запуск; байты в `GeneratedCard.image`. Occlusion с картинкой
   получает `occlusion_json` v1 с прямоугольной маской по центру; без картинки — карточка `basic`
   + `CardIssueCode.occlusionImageMissing`. Wire `occlusion` в БД/экспорт — всегда `basic` +
   `occlusion_json`: SPEC A5 не нарушен, схема БД/`format_version` не менялись.
6. **Импорт и UI.** `DriftGenerationCardStore` пишет файл в `MediaStore`, строку `media`,
   `media_json` и `occlusion_json` в одной транзакции; при откате файл удаляется. Basic-карточка
   с media показывает иллюстрацию в `CardContentView`; предпросмотр — миниатюру, подпись
   «Изображение с маской» и пометку отсутствия картинки.
7. **Документация.** ADR-023, `docs/api-schema.md` (v4), `docs/system-prompt.md` (v3),
   `docs/generation-pipeline.md`, `docs/dependencies.md` (§14, `image ^4.12.0`), `docs/privacy.md`,
   AGENTS, STATE, KNOWN_LIMITATIONS (L57–L60), журнал итерации.

## Доказательства

- `fvm flutter test --coverage --exclude-tags golden` → **1369 passed + 2 skipped**;
  покрытие **92.8 % (9277/9994)**; `analyze` 0; `format` 0 changed;
  `build windows --release` → `cardflow.exe` (80,5 с).
- Live DeepSeek (значение ключа не печаталось): v3-схема принята — `LIVE DeepSeek OK:
  model=deepseek-chat, cards=3, tokens=1351`; fallback `strict=400, tolerant=200,
  max_tokens=8192, cards=2`.
- Production-граф: occlusion + `image_query` → поиск → drift-БД → `MediaStore` → `media`/маска
  (`test/integration/generation_flow_test.dart`); рендер PDF в `Isolate.run` на реальном PDFium.
- Полный список — `journal/iteration-7.9/verify.md`.

## ADR итерации

- **ADR-023** — PDF-сканы через рендер страниц, Openverse-поиск иллюстраций, wire-формат
  `card_type: occlusion` (проекция в `basic` + `occlusion_json`).

## Ограничения (KNOWN_LIMITATIONS)

- **L57** — живой Openverse/429 и латентность, резервный провайдер не проверялись.
- **L58** — атрибуция CC не переносится в БД (в `media` нет полей).
- **L59** — только первые ≤ 4 страницы PDF; живые PNG-страницы в Vision-провайдеры не отправлялись.
- **L60** — иллюстрацию basic-карточки нельзя заменить/удалить в форме; occlusion редактируется.
- L52/L53 (живые Vision/PDF), L35 (независимый reviewer), L11/L37/L42 (ручная приёмка) в силе.

## Ретроспектива

- **Что помогло:** минимальные скелеты новых классов сразу после red-тестов дали assertion-level
  вывод вместо ошибок компиляции; программная PDF-фикстура + реальный PDFium позволили проверить
  рендер и `Isolate.run`; тест production-графа сразу поймал обязательность `mediaStoreProvider`
  (`UnimplementedError`) — без него слои были бы зелёными, а приложение падало.
- **Что замедлило:** широкие правки схемы/промпта потребовали обновить все JSON-фикстуры
  (`image_query: null`) и ожидание версии промпта в интеграционном тесте; полный прогон 2–3 мин
  на каждую волну.
- **Улучшение:** при добавлении обязательного поля strict-схемы сразу обновлять общий
  helper-фикстуру JSON карточки (одно место) вместо трёх файлов; вынести версию промпта в
  константу теста, чтобы интеграционные ожидания не дублировали строку.
