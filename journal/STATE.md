# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Этап:** итерация **7.6** «Пустой ответ LLM: диагностика и фикс» — **завершена
локально**, push/CI — см. ниже · **Режим:** ИТЕРАЦИИ (стоп до команды владельца)
**Факты (сверено командами в этой сессии):** на старте `git status --short` → пусто, `HEAD` =
`origin/main` = `5925ea0` (docs-коммит итерации 7.5; в `STATE.md` 7.5 было записано `a20cd5e` —
исправлено по репозиторию). Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).

## Следующее действие

1. **Стоп:** итерация 7.6 принята локальными гейтами; ждать команды владельца.
2. Приёмка владельцем: сгенерировать карточки из PDF-бланков — вместо «Нейросеть вернула пустой
   ответ» должно быть «Модель не нашла в материалах фактов для карточек…»; на учебных материалах
   (лекции с текстом) генерация работает (живой DeepSeek подтверждён).
3. Дизайн (стекло, тени, анимации) — отдельная задача, не начиналась.

## Итерация 7.6 — итог

**Корневая причина (owner note «Нейросеть вернула пустой ответ»):** модель отвечала валидно —
`{"cards":[]}` по правилу 13 промпта, потому что приложенные PDF — пустые бланки-формы (858 символов:
шапки таблиц и номера столбцов; `generation_jobs` — 5 записей `done`, `cards_count=0`). Ошибку
показывал UI: строка `generationErrorEmptyResponse` переиспользовалась для успешного пустого
результата. Парсинг ответа LLM не был сломан: живой DeepSeek — `finish_reason=stop`, `deepseek-chat`
отдаёт JSON в ```json-ограждении (tolerant-путь его снимал).

**Сделано (ADR-021):**
- `max_tokens` (8192) в OpenAI-совместимом запросе; `sendMaxTokens` в контракте адаптера.
- Лестница совместимости по `badRequest`: strict+`max_tokens` → без схемы+`max_tokens` → без схемы и
  `max_tokens`; не больше трёх запросов, локальная проверка A8.4 на любом шаге.
- `CardsJsonExtractor` (BOM, markdown, текст вокруг JSON) — вынесен из сервиса.
- ARB `generationNoCardsFound` + экран генерации: пустой `cards` больше не выдаётся за пустой ответ.
- Live-тест живого контракта DeepSeek (strict 400 → fallback 200 с `max_tokens=8192`).
- `ApiKeyVerifier`: проверка подключения — без strict-схемы и без `max_tokens` (минимальный
  совместимый запрос, чтобы не было ложного отказа при рабочей генерации).
- `docs/api-schema.md` v3, KNOWN_LIMITATIONS L50/L51, AGENTS.md (слой API).

**Доказательства:** `fvm flutter test --coverage --exclude-tags golden` → **1270 passed + 2 skipped**
(live без ключа в env); покрытие рукописного кода **92.6 % (8772/9469)** (`tool/coverage_check.dart`);
`fvm flutter analyze` → `No issues found!`; `dart format` 319 файлов → 0 changed; `fvm flutter build
windows --release` → `cardflow.exe` (61,8 с); `fvm flutter test test/live --tags live` (ключ из
Windows User scope) → **2 passed**, `LIVE DeepSeek fallback: strict=400, tolerant=200,
max_tokens=8192, cards=2`.

## Известные ограничения (актуальные)

L1, L2, L4, L5, L6, L6c, L7, L8, L10, L11, L12, L13, L14, L15, L16, L18, L19, L20, L23, L24, L25,
L27, L30 (DeepSeek — success-путь живьём; негативные контракты по ADR-014 не проверяются),
L31, L32, L33, L34, L35, L36, L37, L38, L39, L40, L41, L42, L43, L44, L46,
**L28** (сужен: Windows проверен integration-тестом, Android/iOS/macOS/Linux — нет),
**L47** (живые вызовы каталога кроме DeepSeek), **L48** (Windows integration-тест вне CI),
**L50** (DeepSeek отклоняет `json_schema` — пробный strict-запрос на фрагмент), **L51** (третий шаг
лестницы без живого сервера).
