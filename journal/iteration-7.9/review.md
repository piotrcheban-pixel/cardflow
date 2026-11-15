# Итерация 7.9 — ревью Lead (L35: независимый reviewer недоступен)

**Снимок:** `HEAD` после зелёных коммитов шагов 1–3; полный прогон —
`journal/iteration-7.9/full-test-green.log` (1366 passed + 2 skipped, покрытие 92.8 %).
Ревью по чек-листу на неизменяемом снимке; findings — отдельным fix-коммитом с тестами.

## Чек-лист

| Область | Проверка | Итог |
|---|---|---|
| Лента | контр-поворот обратной стороны; тест знака `m00`; нет изменения front-стороны | ок — `feed_card_view.dart`, 2 widget-теста |
| PDF-скан | порог <50, ≤4 страницы, PNG-сигнатура, `groupKey` → один фрагмент, без дублей в `files` | ок — unit + widget + integration |
| PDF-скан | модель без Vision → `pdfScanVisionRequired` и до сети | ок — `CardGenerationService` и `_generate` проверяют до HTTP; widget/unit |
| PDF-скан | сбой PDFium → fallback на PDF (Anthropic/Gemini), иначе прежние понятные ошибки | ок — `_attachPdfPages`; widget-тест fallback |
| PDF-скан | рендер в изоляте (production-путь) | ок — тест `Isolate.run` на реальном PDFium; CI имеет PDFium (L26) |
| Схема | `image_query` в `required`, union с null; enum `occlusion`; проекции Gemini/Anthropic | ок — `card_schema_test` |
| Валидатор | wire `occlusion` → `basic` + `isOcclusion`, SPEC A5 не нарушен; неизвестный тип → `invalidResponse` | ок — `content_validator_test` |
| Промпт | `gen-ru-v3`, правила `image_query`/`occlusion`/запрет в wishes; версия в `generation_jobs` | ок — `prompt_test`; live-путь не проверялся (L57) |
| Поиск | Openverse без ключа, CC-лицензии, thumbnail → fallback url, JPEG/PNG по сигнатуре, ≤5 МБ, 1 req/s | ок — 8 unit-тестов на fake Dio |
| Поиск | любая ошибка (сеть/404/битый JSON/oversized) → `null`, генерация не падает | ок — тесты + `_withCardImage` catch |
| Пайплайн | кэш по запросу, ошибка не отменяет карточку, occlusion без картинки → basic + пометка, с картинкой → маска | ок — 6 unit-тестов |
| Импорт | файл `MediaStore` + строка `media` + `media_json` + `occlusion_json` в одной транзакции; откат удаляет файл; без MediaStore — ошибка | ок — 4 drift-теста + integration production-граф |
| БД/экспорт | `schemaVersion`, `format_version`, `cards.card_type` не менялись; occlusion хранится как `occlusion_json` | ок — схема не тронута; `CardType` без нового значения |
| UI | basic-карточка с media показывает картинку; occlusion — прежний редактор; предпросмотр — миниатюра/подпись/пометка | ок — widget-тесты |
| Безопасность | ключи не добавлены; Openverse-запрос без материалов/ключей; тела не логируются; изображения — только base64 провайдеру | ок — `no_secrets`/`architecture` зелёные; политика обновлена |
| Процесс | ADR-023, docs, STATE, AGENTS; TDD-коммиты 14fa570 / 39e4515 / 5bca... | ок |

## Findings

| # | Уровень | Finding | Решение |
|---|---|---|---|
| F1 | medium | Openverse анонимный лимит ~1 запрос/с: пачка `image_query` из одного фрагмента могла получить 429 и потерять картинки | добавлен троттлинг `minSearchInterval` (1 с) в `ImageSearchService`; кэш по запросу в пайплайне; 429 → карточка без картинки, генерация продолжается (L57) |
| F2 | low | `GeneratedCardImage.attribution` в БД не переносится — в `media` нет полей | зафиксировано L58, политика приватности обновлена; схема в MVP не меняется |
| F3 | low | Найденную иллюстрацию нельзя заменить/удалить в форме basic-карточки | зафиксировано L60; предпросмотр/удаление карточки доступны, occlusion редактируется существующим редактором |
| F4 | low | 4 страницы PDF — фиксированный лимит, дальние страницы не попадают | ADR-023, L59; при необходимости — настройка в post-MVP |
| F5 | low | Реальный Openverse и живые Vision-вызовы PNG-страниц не проверялись | L57/L52/L53; unit/integration на fake-транспорте |

**Blocker/critical/high:** нет. F1 закрыт до verify, F2–F5 — известные ограничения.
