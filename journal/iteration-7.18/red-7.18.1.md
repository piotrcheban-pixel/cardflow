# Red-фаза итерации 7.18.1 (assertion-level)

Каждый пункт сначала воспроизводился падающим тестом (до реализации), ниже —
сохранённые ключевые строки вывода. Полные прогоны — в терминале сессии.

## 2.1 prompt-only на общей машинерии (`4072f4e`)

`test/unit/domain/generation/prompt_only_unified_test.dart`:

```
buildPromptOnly возвращает общий InputPlan стратегии promptOnly
  Expected: not null
    Actual: <null>
prompt-only не применяет распределение по разделам
  Expected: not null
    Actual: <null>
недостаточный бюджет темы: invalid, а не «всё равно»
  Expected: true
    Actual: <false>
```

## v8 в production (`e30562a`)

```
production: системный промпт по умолчанию — gen-ru-v8
  Which: is different. Both strings start the same, but the actual value is
  missing the following trailing characters: \nПЛАНИРОВ ...
```

## 2.2 нативный count_tokens (`c007328`)

`test/integration/generation_exact_tokens_test.dart`:

```
один нативный подсчёт на план
  Expected: <1>
    Actual: <0>
повторный запуск с тем же содержимым берёт кэш без сети
  Expected: <1>
    Actual: <0>
тела запросов не попадают в диагностику
  Bad state: No element
```

## 2.3 recovery ×0.8 (`0e72b61`, `bd99ace`)

`test/unit/domain/generation/generation_plan_splitter_budget_test.dart`:

```
цель ×0.8: части не крупнее бюджета, сумма лимитов сохраняется
  Expected: not null
    Actual: <null>
предохранитель maxParts ограничивает число частей
  Expected: not null
    Actual: <null>
```

## 2.4 характеристики модели (`c646c61`, `419b625`)

```
ручное редактирование контекста/входа/выхода
  The finder "Found 0 widgets with key [<'capabilities-edit'>]" ...
сброс к автоматическому не теряет Vision пользовательской модели
  Expected: true
    Actual: <false>
```

## 2.5 «Подробнее» (`39ade40`, `9f42da6`)

```
смена модели: «Подробнее» берёт лимиты выбранной модели
  Expected: contains '1 000 000'
    Actual: 'неизвестно'
```

## 3 Discovery по документации (`0e42437`)

```
DeepSeek: input_modalities модели → Vision без догадок по имени
  Expected: true
    Actual: <null>
Anthropic: capabilities.image_input — документированное поле
  Expected: true
    Actual: <null>
Moonshot: supports_image_in и supports_reasoning
  Expected: true
    Actual: <null>
Ollama: семантика окна неизвестна (не догадка total)
  Expected: ContextSemantics:<ContextSemantics.unknown>
    Actual: ContextSemantics:<ContextSemantics.totalInputPlusOutput>
```

## Ревью: каталог в requestBytes (`6b374d7`, `bd99ace`)

```
каталог изображений входит в requestBytes (payload-ограничение)
  Expected: true
    Actual: <false>
bodyBytes фрагмента включает строку каталога изображения
  (до фикса разница 0 вместо 500)
```
