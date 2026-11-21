# Итерация 7.18.2 — красная фаза (TDD, до реализации)

**Дата:** 2026-11-21. **База:** `HEAD = origin/main = 170a413`
(`docs(journal): итоги итерации 7.18.1`), `git status --porcelain` → пусто.
Размер workspace-инструкций: 65 143 Б (AGENTS.md усечён бюджетом).

Baseline до правок: `fvm flutter test --no-pub --exclude-tags golden` →
**2302 passed + 16 skipped**, exit 0 (`journal/iteration-7.18/baseline-7.18.2.log`),
`analyze` — 0 (записан в `verify-7.18.2.md`).

## Как получена красная фаза

Каждый тест написан **до** правки реализации и прогнан на текущем коде: все
падения — уровня assertion (ожидаемое/фактическое), а не ошибки компиляции.
Лог: `journal/iteration-7.18/red-7.18.2.log` (30 passed · 15 failed).

```
00:00 +1 -1: image_catalog_budget_test: одно изображение: токены каталога входят в D [E]
  Expected: <24>
    Actual: <0>
00:00 +1 -2: несколько изображений: каталог суммируется по строкам [E]
  Expected: <74>
    Actual: <0>
00:00 +1 -3: длинные подписи и контекст увеличивают каталог и вход [E]
  Expected: a value greater than <0>
    Actual: <0>
00:00 +1 -4: каталог в exact-режиме: нативный подсчёт не пересчитывается [E]
  Expected: <24>
    Actual: <0>
00:00 +1 -5: каталог в fragmentе: каждый фрагмент несёт каталог своих картинок [E]
  Expected: <52>
    Actual: <0>
00:00 +1 -6: generation_payload_bytes_test: payload включает промпт, схему, каталог и base64 [E]
  Expected: a value greater than or equal to <106194>
    Actual: <81165>
00:00 +1 -7: превышение лимита тела: payloadTooLarge, запрос не отправлен [E]
  Expected: throws GenerationException with code payloadTooLarge
    Actual: Future<GenerationResult> (запрос ушёл)
00:00 +2 -8: reasoning_reserve_test: резерв рассуждения вычитается из карточек партии [E]
  Expected: a value less than or equal to <7295>
    Actual: <9343>
00:00 +3 -9: желаемый вывод reasoning-модели включает резерв [E]
  Expected: <4048>
    Actual: <2000>
00:01 +5 -10: T5: две части в одном запросе — payloadTooLarge, без молчаливой потери [E]
  Expected: throws GenerationException with code payloadTooLarge
    Actual: Future<GenerationResult> (34,7 МБ ушли)
00:01 +12 -11: generation_exact_tokens_test: exact-режим не обнуляет стоимость изображений [E]
  Expected: <1294>
    Actual: <1030>
00:02 +26 -12: model_capability_section_test: показывает лимиты с источником и датой [E]
  Expected: exactly 3 matching candidates (неизвестно)
    Actual: 2
00:02 +26 -13: вход изображений: значение, источник и дата проверки [E]
  Expected: exactly one matching candidate (Вход изображений)
    Actual: 0
00:02 +26 -14: неизвестный вход изображений не показан как поддержка [E]
  Expected: exactly one matching candidate (key capability-image-input)
    Actual: 0
00:02 +26 -15: допущение визуально отличается от подтверждённого значения [E]
  Expected: one widget с курсивом и «допущение приложения»
    Actual: 0
```

Дополнительно красным был тест экрана генерации (первый прогон до правки):

```
test/widget/generation/generation_screen_test.dart: явно заданный пользователем Vision
не перекрывается каталогом [E]
  Expected: <1>
    Actual: <0>   (экран показывал «Модель не поддерживает изображения»)
```

## Что подтвердила красная фаза (findings)

| # | Находка | Доказательство |
|---|---|---|
| F1 | Текст каталога `<images>` не входил в `D`/`P` плана: `catalogTokens` был 0, `materialTokens` не рос, `GenerationEstimate.catalogTokens` и `BudgetTrace.catalogTokens` жёстко 0 | тесты 1–5: expected 24/74/52 vs actual 0 |
| F2 | `count_tokens` (Anthropic/Gemini) считает только текст: image-части не входят, а конвейер подставлял это число как весь вход → стоимость изображений = 0 | expected 1294 vs actual 1030 |
| F3 | `requestBytes` плана не включал обвязку протокола (system prompt + JSON-схема + ключи сериализации); фактический payload больше на 29 КБ; лимит `maxRequestBytes` не проверялся по реальному телу — запрос 34,7 МБ уходил при лимите 20 МБ | expected ≥106194 vs actual 81165; payloadTooLarge не брошен |
| F4 | `isReasoningModel` терялся в проекции `ModelCapabilities` и не влиял на `max_tokens`: партия 20 карточек + рассуждение не помещалась (9343 > 7295), желаемый вывод не включал резерв (2000 vs 4048) | тесты 8–9 |
| F5 | UI настроек модели не показывал `supportsImageInput` (источник/дата), допущение не отличалось визуально; `ProviderAccount.copyWith` не переносил `visionConfigured`, поэтому явный Vision пользователя превращался в каталог и экран генерации блокировал запуск | тесты 12–15 + экран генерации |

Не является находкой (проверено, дефекта нет): обработка ошибок discovery
(неверный тип поля, отсутствующее поле, пустой список, 401, таймаут) для всех
четырёх резолверов — 14 тестов `model_discovery_errors_test.dart` зелёные
**до** правок.
