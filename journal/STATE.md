# STATE — текущее состояние CardFlow

**Дата:** 2026-11-16 · **Этап:** итерация **7.16** «Подбор пар» и
«Верно/Неверно» (ADR-033) — завершена; дальше — итоговый отчёт и СТОП.
**Режим:** ИТЕРАЦИИ (7.14 → 7.15 → 7.16).

**Факты старта 7.14 (сверено командами):** `git status --porcelain` → пусто,
`HEAD = origin/main = cc88e0c` (`docs: record green CI for generation fix
iteration`) — в STATE fix-gen записан `08b42d8`, после него был docs-коммит,
исправлено. Baseline — **1597 passed + 7 skipped** (`flutter test --no-pub
--exclude-tags golden`), `analyze` **0**, `format` **378 / 0**.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).
Прогоны — только с `--no-pub` (L64). Ключ DeepSeek — present в Windows User
scope (значение не выводилось); `PIXABAY_API_KEY`/`PEXELS_API_KEY` — absent.

## Сверка STATE с кодом (7.14, старт)

Проверено по файлам, расхождения исправлены:

- **Режимы:** реально четыре — `classic`, `feed`, `practice`, `constructor`
  (`_SessionModeAction` в `lib/ui/decks/deck_screen.dart`; маршруты
  `/decks/:deckId/{study,feed,practice}` и `/constructor`). В истории STATE
  конструктор упоминался только в итерации 6 — здесь зафиксировано явно.
- **Промпты генерации:** `gen-ru-v5` — сырой литерал
  `lib/api/prompts/system_prompt.dart`, дословная копия
  `docs/prompts/gen-ru-v5.txt`; механизм версии — константы +
  `CardGenerationService.promptVersion`. Подтверждено.
- **ImageSearchService:** до 7.14 это **Openverse**
  (`lib/api/images/image_search_service.dart`), а цепочка —
  `CompositeCardImageFinder` (Commons → Wikipedia → Openverse). В 7.14
  `ImageSearchService` стал цепочкой провайдеров (ADR-031), старые сервисы
  заменены на `ImageProvider`-реализации.
- **MediaStore:** был только файловый (байты по пути); метаданных
  провайдера/лицензии/isPlaceholder не было, `media` их не хранит. В 7.14
  добавлены побочные `<путь>.meta.json` (`MediaMetadata`), схема БД не менялась.
- **FSRS:** `FsrsScheduler` (`lib/domain/scheduling/scheduler.dart`), маппер
  `fsrs_mapper.dart`, начальное состояние `CardSchedulingMapper.initialScheduling`.
  Подтверждено.
- **Лист режимов:** `showModalBottomSheet` в `_startSession`
  (`lib/ui/decks/deck_screen.dart`), ключи `review-mode-*`. Подтверждено.
- **ARB:** один файл `lib/l10n/app_ru.arb`; `supportedLocales` — только `ru`,
  `app_en.arb` нет. Требование задания «ARB (ru, en)» конфликтует с жёстким
  правилом AGENTS/SPEC (локаль только `ru`) и guard-тестом `ru_strings_test`:
  новые строки добавлялись в `app_ru.arb`; английская локаль не вводилась
  (продуктовое решение, не самовольное изменение).
- **Правило «абстрактные понятия без картинки»** было в валидаторе
  (`_isAbstractCard` + `CardIssueCode.abstractImageQuery`) — удалено в 7.14
  вместе с промптом v6.

## Итерация 7.14 — итог (ADR-031)

**Гейты 7.14:** `test --no-pub --coverage --exclude-tags golden` → **1660
passed + 8 skipped** · покрытие рукописного кода **92.0 % (12159/13218)** ·
`analyze` **0** · `format` **0 changed** · `build windows --release --no-pub` →
`cardflow.exe` (84,4 с) · Windows-смоук
`integration_test/session_smoke_windows_test.dart -d windows --no-pub` →
**All tests passed!** (9 с) — форма+картинка, лимит, сессия, генерация с картинкой.

**Сделано:**
- Промпт `gen-ru-v6` (сырой литерал + `docs/prompts/gen-ru-v6.txt`, тест
  байт-в-байт); v5 сохранён. Обязательный объект `image` у каждой карточки
  (`query`, `fallback_query`, `kind`), канонические якоря схем
  (`free body diagram …`, `force couple diagram …`), запреты (русские слова,
  «image/photo of», имена файлов, LaTeX, одно слово, повторы в колоде).
- Схема: строгая v6 для провайдера; локальная терпимая `localCardItemSchema`
  принимает и v5 (`image_query` строкой/`null`), и карточку без `image`.
- Нормализация `image_query_normalizer.dart`: чистка запрещённых слов,
  не-латиницы, имён файлов и LaTeX; обрезка до 7 слов; сборка из fallback;
  дополнение вида; legacy-вывод kind. Правка → `imageQueryAdjusted`, карточка
  не отбрасывается.
- Цепочка `ImageSearchService` + интерфейс `ImageProvider`
  (`wikimedia`, `wikipedia`, `openverse`, `pixabay`, `pexels`): таймаут 6 с на
  провайдера, бюджет 20 с на карточку, основной запрос → fallback, скачивание
  с лимитом 4 параллельно, фильтры JPEG/PNG/WebP + короткая сторона ≥ 400 px +
  пропорции ≤ 3:1 + безопасный поиск, кэш LRU 32, дедупликация URL, ретрай
  одного 429/5xx с backoff, затем следующий провайдер. Ключи Pixabay/Pexels —
  только `--dart-define`/env; без ключа провайдера нет.
- Заглушки: `PlaceholderImageGenerator` (8 палитр, градиент+паттерн+иконка
  вида, детерминированно от хэша содержимого), PNG 800×450/800×600, флаг
  `isPlaceholder`, провайдер `placeholder`. Метаданные атрибуции
  (`provider`, `sourceUrl`, `author`, `license`, `query`, `fallbackQuery`,
  `kind`) — в `MediaStore` рядом с файлом; GC чистит их вместе с медиа.
- «Найти картинку заново» в редакторе карточки (`CardImageRefresher`) и
  фоновый ретрай заглушек на старте (`main.dart`, ≤ 5 за запуск, ошибки глушатся).
- UI: `CardImageView` (16:9, схема 4:3, cover/contain, скругление 16, fade-in,
  скелетон, max-height 220), полноэкранный просмотр с зумом и атрибуцией;
  картинки в предпросмотре, Классике, Ленте, Тренировке, редакторе; живой
  список карточек во время генерации (`GenerationProgress.cards`).
- Тесты: нормализация, схема/совместимость v5, провайдеры (включая
  Pixabay/Pexels на мок-клиенте), цепочка (приоритет/таймаут/фильтры/ретраи/
  кэш/лимит параллелизма/дедуп), заглушки (детерминизм/флаги), `MediaStore`
  и GC, `CardImageRefresher` (замена заглушки, лимит, ошибки), pipeline
  (заглушка, дедуп URL, fallback/kind), виджеты (фото/схема/заглушка/без
  картинки, overflow 360×640 и 1280×800, fullscreen+атрибуция, «Найти заново»,
  живые карточки).

**Живая проверка (2026-11-16, `deepseek-chat`, настоящая сеть):** две колоды по
18 карточек (`test/live/images_v6_live_test.dart`, отчёт
`journal/iteration-7.14/live-metrics.{md,json}`, картинки в
`journal/iteration-7.14/images/`):

| Колода | Карточек | Настоящих | Заглушек | Провайдеры | Ср. догрузка |
|---|---|---|---|---|---|
| Статика | 18 | 18 (100 %) | 0 | wikipedia 14, wikimedia 4 | 3,5 с |
| Биология | 18 | 18 (100 %) | 0 | wikipedia 10, wikimedia 8 | 1,9 с |

Ручная оценка 10 случайных карточек (`journal/iteration-7.14/relevance.md`):
**Биология 8/10** — цель достигнута; **Статика 1/10** — цель ≥ 7/10 не
достигнута. Выполнена одна итерация правки промпта (канонические якоря схем),
повторный замер: настоящих картинок 100 %, уместность «Статики» осталась низкой
(2/18 по всей колоде), «Биология» — 13/18. Причина — полнотекстовый поиск
Commons/Wikipedia для абстрактных механик совпадает с посторонними статьями
(фазовые диаграммы, карты, портреты); фильтры формата/размера их пропускают.
Ограничение — L84; рекомендация — семантическая проверка релевантности
(vision/LLM) или курируемый источник схем. Заглушка в этих случаях не
включается, т.к. картинка формально найдена.

**Долги 7.14:** L81 (Pixabay/Pexels без ключей), L82 (метаданные вне БД),
L83 (seed заглушки — хэш содержимого), L84 (семантическая релевантность),
L85 (метрики на одной модели), L86 (дедуп URL в пределах запуска).

## Итерация 7.15 — итог (ADR-032)

**Гейты 7.15:** `test --no-pub --coverage --exclude-tags golden` → **1715
passed + 8 skipped** · покрытие рукописного кода **91.7 % (12974/14143)** ·
`analyze` **0** · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (см. отчёт о прогоне) · Windows-смоук — после 7.16.

**Сделано:**
- Домен: `StudyMode` (`test`, `typing`, `match`, `true_false`; wire-значения для
  `review_logs.mode`), политика FSRS (`isDueForStudy`: новая карточка тоже
  «due» — первая оценка создаёт расписание; будущая `due` — тренировка),
  очередь (`buildStudyQueue`: due/новые, затем будущие), `AnswerType`
  (`short_text|number|formula|long_text`; для ввода — ≤ 60 символов, ≤ 6 слов,
  без LaTeX/переносов), нормализация (NFC через `unorm_dart`, регистр, ё/е,
  пробелы, пунктуация, ответы через `/`/`;`), `AnswerMatcher`
  (`exact|almost|wrong`, Левенштейн 1/2, diff missing/extra), `DistractorGenerator`
  (3 ответа из колоды того же типа, близкой длины; числа — та же единица; без
  дублей; позиция правильного по seed; `aiDistractors` как вход).
- `StudySessionController`: общая очередь/прогресс/итоги/undo/«Повторить
  ошибки»; due → `Scheduler`+`ReviewRepository` (`mode`), будущие →
  `PracticeRepository` (`mode`; undo фильтруется по mode, классический журнал
  не удаляется). Порт тренировки расширен необязательным `mode`.
- Экраны: `MultipleChoiceScreen` (4 варианта, зелёный/красный, автопереход 1,2 с
  кроме reduce motion, пружина+haptics, клавиши 1–4/Enter, итоги и повтор
  ошибок), `TypingScreen` (exact/almost/wrong, diff, «Я был прав» = undo +
  Good, «Показать ответ» = Again, Enter); маршруты
  `/decks/:deckId/{test,typing}`; лист режимов с числом доступных карточек и
  неактивными пунктами при их нехватке; ARB (ru).
- Тесты: 9 domain (тип/матчер/дистракторы/очередь/политика), 8 controller,
  16 widget (Тест/Ввод), 3 листа режимов, mode-scoped undo; полный прогон —
  зелёный.

**Решения/отклонения:** ИИ-дистракторы (batch-запрос на колоду и кэш) в этой
итерации не подключены: генератор принимает `aiDistractors`, но production-
источника ИИ и кэша нет — карточки, для которых в колоде меньше 4 подходящих
ответов, пропускаются в Тесте (L87). Дневные лимиты новые режимы не учитывают
(L88) — FSRS пишется только для due, но лимит новых/повторов может быть
превышен; это осознанное упрощение до обсуждения владельцем.

## Итерация 7.14 — CI

Push `cc88e0c..bf28359`; CI run
[`43901313115`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43901313115)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.15 — CI

Push `bf28359..df0e873`; CI run
[`43904903386`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43904903386)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.16 — итог (ADR-033)

**Гейты 7.16:** `test --no-pub --coverage --exclude-tags golden` → **1742
passed + 8 skipped** · покрытие рук��писного кода **91.7 % (13521/14743)** ·
`analyze` 0 · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (52,4 с).

**Сделано:**
- «Подбор пар»: домен `MatchGame` (6 пар, 12 плиток, перемешивание по seed,
  selected/matched/mismatch/moves, `select → selected|matched|mismatch|ignored`),
  экран `MatchScreen` (сетка 3/4 колонки, таймер с первого тапа, встряхивание
  несовпавшей пары, исчезновение найденной, итог + лучшее время, «Ещё раз»,
  «Готово»); `MatchBestStore` + `DriftMatchBestStore` — JSON v1 в `app_settings`
  (`study.match.best`), схема БД не менялась. FSRS не пишется.
- «Верно/Неверно»: домен `TrueFalseQuestion` (50/50 из правильного ответа или
  дистрактора колоды, seed), экран `TrueFalseScreen` (утверждение, кнопки ✓/✗,
  свайп вправо/влево, плашка результата с правильным ответом, авто-переход 0,9 с
  кроме reduce motion, итоги/повтор ошибок) на общем `StudySessionController`
  (`mode='true_false'`, FSRS только для due, остальные — тренировка).
- Маршруты `/decks/:deckId/{match,true-false}`, пункты листа режимов с числом
  доступных карточек и неактивным состоянием, ARB (ru). Тесты: домен
  (MatchGame/TrueFalse), хранилище на реальной drift-БД, widget (9 сценариев),
  лист режимов, роутер (17 маршрутов).

**Решения/долги:** лучшие результаты «Пар» — локальный кэш, не входят в
статистику/экспорт; таймер игры — `Timer.periodic` экрана (L33/L88);
ИИ-дистракторы по-прежнему не подключены (L87).

## Итерация fix-gen — итог (архив, v5)

**Причины (диагностика `journal/iteration-fix-gen/diagnosis.md`):**
- Д4/Д6: модель пишет LaTeX одним `\` в JSON → `\frac`→form feed, `\alpha`→
  `FormatException`; фрагмент падал `invalidResponse`, формула молча портилась.
- Д6: все схема- и структурно-невалидные карточки роняли фрагмент; предпросмотр
  не импортировал пак из-за одной невалидной карточки.
- Д3: изображения файлов не извлекались (парсеры читали только текст).
- Д2: производный `image_query` из текста вопроса давал случайные картинки.

**Сделано:**
- Промпт `gen-ru-v5` дословно (`lib/api/prompts/system_prompt.dart` +
  `docs/prompts/gen-ru-v5.txt`, тест байт-в-байт); блоки `<materials>`,
  `<wishes>`, `<limit>`, `<images>`; `Файл: <имя>`; лимит карточек из пожеланий
  делится по фрагментам пропорционально (`generation_card_limit.dart`).
- Схема A8.4 + `image_id`, поштучная проверка, проекции OpenAI/Gemini/Anthropic
  (ADR-029); валидатор: `image_id` вне каталога → null; `image_query` — латиница
  ≤ 7 слов; абстрактные понятия без картинки; tags ≤ 3.
- LaTeX: `latex_escape_repair.dart` (до/после JSON), `\(\)`/`\[\]` → `$…$`,
  `\$` не формула; `LatexText`/`ClozeText`/`InlineLatexText` через `Math.tex`.
- Изображения DOCX/PPTX/ODT (`DocumentImage` + контекст, фильтры мусора) →
  `<images>` фрагмента → `image_id` → байты файла; предпросмотр: убрать/заменить.
- Причины сбоя фрагмента (`GenerationFailureReason`, 13 кодов) в
  `generation_jobs.error_code` и debug-лог; частичный импорт; кнопка неактивна
  только без выбранных карточек; ошибки «Фрагмент K из M: причина».
- Д5: мягкие проверки качества (7 пометок) + eval-набор 3 сценария + live-метрика.
- Д1: кнопка неактивна без файлов/темы, подсказка ARB, имя колоды из темы,
  `source_excerpt` при пустых материалах → null.

**Доказательства:** `journal/iteration-fix-gen/{diagnosis,red-output,review,verify,summary}.md`;
тесты `latex_escape_repair_test`, `latex_render_fix_test`, `document_images_test`,
`card_generation_images_test`, `generation_fix_gen_test`, `card_quality_test`,
`quality_eval_test`, `generation_preview_partial_test`, `failure_reasons_test`,
`generation_failure_message_test`, `prompt_test` (байты).

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30,
L31–L34, L35, L36, L37–L44, L46–L52, L53 (живой PDF-part), L54, L55, L56,
L57–L59 (≤ 3 страниц), L60 (снято 7.12; предпросмотр — fix-gen), L61, L62–L64,
L65, L66 (обновлено L80), L67, L68, L69, L70, L71–L75,
**L76** (изображения внутри PDF не извлекаются), **L77** (только JPEG/PNG из
документов), **L78** (ручные клики/скриншоты владельца), **L79** (причины
сбоя перечнем в `error_code`), **L80** (поштучный отброс карточек моделей,
не следующих strict-схеме), **L81** (Pixabay/Pexels без ключей), **L82**
(атрибуция в побочном JSON, не в БД), **L83** (seed заглушки — хэш
содержимого), **L84** (семантическая релевантность картинок не проверяется),
**L85** (метрики на `deepseek-chat`), **L86** (дедуп URL в пределах запуска),
**L87** (ИИ-дистракторы не подключены: мало ответов → карточка пропускается в
Тесте), **L88** (новые режимы не учитывают дневные лимиты).

## История

- 7.16 «Подбор пар» и «Верно/Неверно» (2026-11-16) — ADR-033, гейты выше.
- 7.15 «Тест» и «Ввод ответа» (2026-11-16) — ADR-032, гейты выше.
- 7.14 «Картинка у каждой карточки» (2026-11-16) — ADR-031, CI run `43901313115` 9/9.
- fix-gen «Исправление генерации» (2026-11-16) — ADR-029/030.
- 7.12 «Фикс UX картинок, лимитов и поиска ИИ» — CI run `43750931989` 9/9.
- 7.11 «FSRS новых карточек, картинки, сканы и Practice Mode» — CI run
  `43742161910` 9/9.
- 7.10 «Prompt-only, PDF и картинки» — CI run `43728048903` 9/9.
- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.
