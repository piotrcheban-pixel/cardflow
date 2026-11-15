# Итерация 7.12 — verify

**Дата:** 2026-11-15 · Все команды — в этой сессии, через FVM, с `--no-pub`.

## Старт и сверка STATE

- `git status --porcelain` → пусто; `HEAD = origin/main = e9ea08b`
  (`docs: record green CI for iteration 7.11`); в STATE.md было `8925e99` —
  после него был ещё docs-коммит, исправлено в STATE.
- Baseline итерации 7.11 (из STATE): 1458 passed + 4 skipped.

## Гейты

| Гейт | Команда | Результат |
|---|---|---|
| Тесты | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1512 passed + 5 skipped**, exit 0 (skipped — live DeepSeek без ключа в env прогона; живые проверки запускались отдельно) |
| Покрытие | lcov, рукописный код без `*.g.dart`/`app_localizations*` | **92.4 % (10085/10914)** — ≥ 80 % |
| Анализатор | `fvm flutter analyze --no-pub` | **0 issues** |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test` | **355 файлов / 0 changed** (первый прогон — 13 changed, применён) |
| Windows release | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (64,3 с) |
| Windows debug-запуск | `fvm flutter run -d windows --no-pub` | `√ Built ...\Debug\cardflow.exe`, `Syncing files to device Windows... 216ms`, `Flutter run key commands`, VM Service — окно открылось, ошибок старта нет |
| Windows-смоук | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows --no-pub` | **All tests passed!** (сборка 32,0 с; сценарий 9 с) |

### Windows-смоук: что проверено на реальном процессе

Файловая drift-БД + MediaStore + production-провайдеры + настоящий виджет-граф:

1. **Basic + картинка без масок:** нажимается FAB, заполняются поля, `imageGateway`
   отдаёт PNG, в форме виден `card-form-image-preview`, редактора масок нет,
   сохранение пишет `media_json != "[]"`, `occlusion_json = NULL`, файл в
   `MediaStore` совпадает с байтами PNG.
2. **Owner-сценарий лимита:** 20 «новых» оценок за сегодня + карточка создана
   сегодня → «Начать сессию» → «Классический» открывает сессию **без**
   предупреждения, `card-content-image` виден.
3. **Старая карточка** (создана 30 дней назад): появляется диалог
   `reviewDailyLimitTitle`, «Продолжить без лимита» (`review-limit-continue`)
   открывает сессию со старой карточкой.
4. **Генерация:** fake HTTP-провайдер + Wikimedia (`image_query` → PNG) →
   `GenerationPreviewScreen` показывает `generation-preview-image-0`,
   предупреждения о поиске нет → импорт → у карточки `media_json` и файл иллюстрации.

## Живые проверки (ключ из Windows User scope, значение не печаталось)

`fvm flutter test test/live --tags live --no-pub` → **7 passed**:

```
LIVE Wikimedia OK: jpeg, bytes=97201, attribution=... Diego Delso · CC BY-SA 4.0
LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1572
LIVE Wikipedia OK: jpeg, bytes=239077, attribution=Минерал · Wikipedia
LIVE composite OK: jpeg, bytes=239077
  Commons: нет подходящей картинки среди 0 результатов
  Wikipedia (ru): статья «Минерал», скачано 239077 Б, jpeg
LIVE DeepSeek fallback: strict=400, tolerant=200, max_tokens=8192, cards=2
LIVE DeepSeek prompt-only: cards=3, image_query=3, prompt=gen-ru-v4, tokens=1602
LIVE DeepSeek scan OK: pages=3, cards=2, tokens=2897
```

Сырой ответ модели в консоли (диагностика ADR-024) — в логе прогона: JSON
карточек с `image_query` у всех трёх карточек.

### Модель владельца `deepseek-flash`

- prompt-only: `LIVE DeepSeek prompt-only: cards=3, image_query=3,
  prompt=gen-ru-v4, tokens=2421` — сырой ответ показывает `image_query` у всех
  трёх карточек.
- production-пайплайн (живой DeepSeek → реальный поиск картинок → карточки):

```
LIVE image pipeline status=done, cards=3, failures=[], model=deepseek-flash
LIVE image pipeline: cards=3, with_image=3, model=deepseek-flash
LIVE card: image_query=african elephant savanna, image=218670 Б jpeg, issues=[]
LIVE card: image_query=giraffe savanna africa, image=458295 Б jpeg, issues=[]
LIVE card: image_query=male lion pride savanna, image=134919 Б jpeg, issues=[]
```

Это прямой ответ на owner-note №3: у модели владельца карточки приходят
**с картинками** (3/3), а не «молча без них».

## Красная фаза

Зафиксирована в `journal/iteration-7.12/red-output.md`: лимит новых карточек
(4 упавших теста: ожидалась сегодняшняя карточка, получено `[]`), форма
(ожидалось отсутствие редактора масок — найден `occlusion-editor-canvas`),
`wishesForbidImages` (ожидалось `true`, получено `false`).

## Замечания

- `fvm flutter test` без `--no-pub` зависает на `pub get --example` — все
  прогоны с `--no-pub` (L64).
- Диагностика в debug теперь идёт в stdout (`debugPrint`), поэтому прогоны
  генерации в тестах печатают сырой ответ модели — это ожидаемо (ADR-024) и
  полезно как evidence.
- `deepseek-flash` по-прежнему нестабилен на strict-схеме (L66): первый прогон
  live-пайплайна дал `GenerationJobStatus.error` без карточек, повторный — 3/3
  с картинками. Это свойство модели, не пайплайна; для `deepseek-chat` стабильно.
- `tester.pageBack()` в ru-локали не работает (ищет английский tooltip) —
  в смоуке возврат по стрелке AppBar.

