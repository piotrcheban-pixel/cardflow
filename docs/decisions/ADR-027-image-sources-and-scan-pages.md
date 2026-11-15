# ADR-027 — Иллюстрации: Wikimedia Commons первым, Openverse резервом, бюджет поиска; скан — 3 страницы

**Дата:** 2026-11-15 · **Итерация:** 7.11 · **Статус:** принято

## Контекст

Owner note 7.11: «Картинки не отображаются в предпросмотре», «Сканы PDF не отправляются».
Проверка на этом же хосте 2026-11-15:

- Openverse (`api.openverse.org`): первый запрос — 200; последующие запросы, включая
  англоязычные, **таймаутят** (L61 подтверждён). При 20 карточках это до 20×20 с
  ожидания, и все карточки остаются без иллюстраций.
- Wikimedia Commons API: русские запросы («Московский Кремль», «Иван Грозный»)
  отвечают за 1–2 с релевантными JPEG/PNG.
- Живой DeepSeek принимает `image_url` части (probe 1×1 PNG → ответ модели) и
  отрендеренные PNG-страницы скана (live-тест итерации 7.11: 3 страницы → 2 карточки).

Предпросмотр и после импорта картинка **не теряется** — это подтверждено тестами
(`GenerationPreviewScreen` рендерит `Image` по байтам; после импорта `media`-файл
читается `CardMediaRepository`). Реальный дефект был в источнике: поиск не давал
картинку вовсе.

## Варианты

| Вариант | Оценка |
|---|---|
| **A. Только Openverse (7.9)** | таймауты, картинок нет; генерация ждёт сеть |
| **B. Только Wikimedia Commons** | хорошие русские результаты, но один источник и без резерва |
| **C. Wikimedia первым + Openverse резервом + бюджет времени (выбрано)** | быстрый и релевантный основной источник, резерв для иных тем, ограниченное ожидание |
| **D. Платные API (Bing/Google Images)** | ключи, деньги, приватность — вне MVP |

## Решение

1. **Новый источник.** `WikimediaImageSearchService` (`lib/api/images/`): GET
   `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=…&gsrnamespace=6&gsrlimit=5&prop=imageinfo&iiprop=url|mime|extmetadata&iiurlwidth=800`,
   thumbnail 800 px (fallback — оригинал), только `image/jpeg|image/png` (PDF/DJVU/SVG
   отбрасываются), сигнатура JPEG/PNG, ≤ 5 МБ, User-Agent `CardFlow/1.0 (…repo…)`.
   Атрибуция — `title · artist · license` из `extmetadata` (HTML вычищается).
   Таймаут запроса — 8 с, ошибка → `null` + debug-диагностика (ADR-024).
2. **Композитный поиск.** `CompositeCardImageFinder` перебирает источники по порядку:
   Commons → Openverse (`ImageSearchService`, таймаут снижен с 20 до 8 с).
   Провайдер `cardImageFinderProvider` собирает композит на общем Dio.
3. **Бюджет поиска.** `GenerationPipeline.imageSearchBudget` (по умолчанию 45 с на
   запуск/повтор, часы инжектируются): после дедлайна оставшиеся карточки
   импортируются без иллюстраций, в debug-диагностику пишется
   «пропущен: бюджет времени поиска исчерпан». Недоступный источник больше не
   задерживает генерацию на десятки секунд на карточку.
4. **PDF-скан — 3 страницы.** `PdfScanRenderer.maxPages` по умолчанию `3` (было 4):
   владельцу достаточно первых страниц скана, а PNG-страницы весят много и
   увеличивают тело запроса; ширина ≤ 1600 px сохранена. Механика (PDFium в изоляте,
   `groupKey` страниц, image parts, `pdfScanVisionRequired` без Vision) — без
   изменений из ADR-023.

## Последствия

- Иллюстрации появляются у большинства предметных карточек; при недоступности обоих
  источников карточка остаётся без картинки (генерация не падает).
- Смена источника — не изменение публичного контракта: доменный порт `CardImageFinder`
  и `GeneratedCardImage` прежние; атрибуция по-прежнему не переносится в БД (L58).
- Wikimedia просит осмысленный User-Agent; сервис его отправляет. Лицензии Commons —
  только свободные (CC/PD), как и у Openverse.
- PDF-скан: дальние страницы (с 4-й) не отправляются — ограничение L59.
- Живой Openverse по-прежнему не гарантирован (L61): он резервный.
- Новых пакетов нет: используется уже объявленный Dio.

## Ссылки

- SPEC A8.1, A8.3, A8.5; ADR-022, ADR-023, ADR-024; L58, L59, L61.
- `lib/api/images/wikimedia_image_search_service.dart`,
  `lib/api/images/composite_card_image_finder.dart`,
  `lib/api/images/image_search_service.dart`,
  `lib/api/generation/generation_pipeline.dart`,
  `lib/api/parsers/pdf_scan_renderer.dart`, `lib/ui/state/app_providers.dart`.
