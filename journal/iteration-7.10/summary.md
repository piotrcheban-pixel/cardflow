# Итерация 7.10 — «Фикс генерации без файлов, PDF и картинок»

**Статус:** завершена; push `bdb0bd1..5cbb653`, CI run
[`43728048903`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43728048903) — 9/9 job success.

## Что сделано

1. **Генерация без файлов (SHAГ 1).** Экран больше не требует ни одного файла: запуск
   разрешён при непустой теме/описании, иначе ARB «Напишите тему или описание — файлы не
   обязательны». `GenerationPipeline`, если нет документов/вложений и чанкер пуст, создаёт
   один фрагмент с пустым `materialsText`; `buildGenerationUserContent` допускает пустой
   `<materials>`; `CardGenerationService` бросает `noMaterials` только когда нет ни текста,
   ни вложений, ни пожеланий. Оценка токенов учитывает тему и показывается для prompt-only.
   Промпт `gen-ru-v4`: пустой `<materials>` + тема в `<wishes>` → карточки по общим знаниям,
   `source_excerpt` — `null`.
2. **PDF (ШАГ 2).** `TextSanitizer` — единый санитайзер: удаляет Unicode Cc/Cf (PDFium отдаёт
   C1 `U+0080–U+009F`), BOM/zero-width/bidi, одиночные суррогаты, `U+2028/2029` → `\n`;
   `PdfTextQuality` нормализует UTF-8 и при ≥ 5 заменах `U+FFFD` и доле > 5 % поднимает
   `ParserErrorCode.garbledText` («PDF содержит нечитаемый текст»). `GenerationDiagnostics`
   (debug-only, release no-op) пишет статус и редактированное тело ответа при ошибке
   провайдера и сырой ответ модели; 400 сквозь пайплайн показывает в UI безопасную причину
   (`providerReason`) — закреплено интеграционным и widget-тестами.
3. **Картинки (ШАГ 3).** Промпт v4: для `basic`/`cloze` предметных карточек `image_query`
   **обязателен** (английский). Живой DeepSeek подтвердил: prompt-only 3 карточки, `image_query=3`.
   `ImageSearchService` пишет в debug-диагностику итог поиска (успех/нет результата/ошибка),
   чтобы «модель не дала image_query» не путать с «не удалось скачать». Интеграционный тест
   на production-графе с **реальным** `ImageSearchService` и fake-Dio: `image_query` → Openverse
   JSON → JPEG → `GeneratedCard.image` → импорт → `MediaStore` + `media` + файл.
   Предпросмотр картинки покрыт widget-тестом (7.9, подтверждён).
4. **Границы.** Схема БД/`schemaVersion`/`format_version` не менялись, новых зависимостей нет.

## Доказательства

- `fvm flutter test --no-pub --coverage --exclude-tags golden` → **1409 passed + 3 skipped**;
  покрытие рукописного кода **92.9 % (9393/10114)**; `analyze` 0; `format` 334/0;
  `fvm flutter build windows --release --no-pub` → `cardflow.exe` (63,9 с).
- Red-фаза: 20 падений assertion-level (`journal/iteration-7.10/red-output.txt`).
- Живой DeepSeek: 3 live-теста passed, в т.ч. `prompt-only: cards=3, image_query=3,
  prompt=gen-ru-v4, tokens=1502`.
- Полный список — `journal/iteration-7.10/verify.md`.

## ADR

- **ADR-024** — prompt-only (пустой `<materials>` + тема), стойкость PDF-текста
  (`garbledText`), debug-only диагностика ответов и обязательный `image_query`.

## Ограничения (KNOWN_LIMITATIONS)

- **L61** — живой Openverse с хоста агента не завершается за 20 с; проводка проверена
  интеграционным тестом, причина видна в диагностике.
- **L62** — prompt-only опирается на общие знания модели (`source_excerpt` = null).
- **L63** — порог `garbledText` эвристический (5 замен / 5 %).
- **L64** — живые проблемные PDF владельца не переразбирались (программные фикстуры).
- L35 (независимый reviewer), L11/L37/L42 (ручная приёмка), L52/L53 (живые Vision/PDF) в силе.

## Ретроспектива

- **Что помогло:** спайк PDFium до кода дал точную причину (C1/суррогаты) вместо догадок;
  диагностика вместе с фиксом сразу развела «нет image_query» и «не скачалось»; live-тест
  prompt-only с подсчётом `image_query` подтвердил промпт v4 на реальной модели.
- **Что замедлило:** `flutter test`/`build` без `--no-pub` зависают на `pub get --example` в
  сессии агента (первый baseline-прогон потерял 10 минут); пришлось перейти на `--no-pub`.
- **Улучшение:** в инструкции по окружению зафиксировать `--no-pub`; для сетевых сервисов с
  `null`-контрактом (поиск картинок) сразу добавлять диагностику — иначе баг-репорт владельца
  («картинок нет») нечем разложить.
