# Красная фаза/диагностика (fix-gen)

## 1. Спайк JSON-экранирования (подтверждение Д4/Д6)

`dart run` над `dart:convert` с формами реального ответа модели:

```
OK   {"front":"$\\frac{a}{b}$"} -> 24 5c 66 ...   (корректный JSON)
OK   {"front":"$\frac{a}{b}$"}  -> 24 0c 72 61 63 (0x0C = form feed + "rac")
OK   {"front":"$\times$"}       -> 24 09 ...       (tab + "imes")
OK   {"front":"$\beta$"}        -> 24 08 ...       (backspace + "eta")
OK   {"front":"$\rho$"}         -> 24 0d ...       (CR + "ho")
OK   {"front":"$\nabla$"}       -> 24 0a ...       (LF + "abla")
FAIL {"front":"$\alpha$"}       -> FormatException: Unrecognized string escape
FAIL {"front":"$\sum$"}         -> FormatException: Unrecognized string escape
FAIL {"front":"$\Delta$"}       -> FormatException: Unrecognized string escape
FAIL {"front":"$\cdot$"}        -> FormatException: Unrecognized string escape
```

Ожидаемое поведение после фикса (тест `latex_escape_repair_test.dart`):
`\fraс`/`\alpha`/`\nabla` доходят до карточки командой; `\n` между словами
остаётся переносом; не-JSON без LaTeX по-прежнему `json_parse`.

## 2. Факты БД приложения (`generation_jobs`)

```
2c56db4e  partial  truncated        11 chunk  80 cards  42552 tok  PDF 30 стр.
300ab344  error    invalidResponse   1 chunk   0 cards      0 tok  без файлов
2b2d5c61  done     —                1 chunk  13 cards   4598 tok  PDF минералы (media_json = [])
24605600  error    invalidResponse   1 chunk   0 cards      0 tok  без файлов
f174e507  error    truncated         2 chunk   0 cards      0 tok  PDF 3 стр.
```

Вывод: «Не удалось обработать фрагмент…» — это `failures` предпросмотра; причина
была неотличима (`invalidResponse` = JSON/схема/структура; `truncated` = обрезка).

## 3. Старое поведение валидатора (до фикса)

- `CardResponseSchema.validate` проверял документ целиком: одна карточка без
  `back` → `invalidResponse` для всего фрагмента.
- `CardContentValidator.validateResponse` бросал `_invalidResponse()` при первой
  структурно непригодной записи.
- Предпросмотр: `_import` отказывался от импорта при `!CardDraft.isValid` хотя бы
  у одной выбранной карточки (`generation_preview_screen.dart`).

Ожидаемое после фикса (тесты `failure_reasons_test.dart`,
`generation_preview_partial_test.dart`): плохая карточка отбрасывается сама
(`rejectedCards++`), остальные импортируются.

## 4. Первый полный прогон после изменения схемы (снимок до правки тестов)

`fvm flutter test --no-pub --exclude-tags golden` → `+1439 -45` падений (45):
ожидания старой схемы без `image_id` и старого поведения валидатора
(`frontLooksLikeHeading` появился как новая пометка; `\(…\)` теперь формула;
производный `image_query` удалён). Все падения разобраны: часть — обновлённые
ожидания поведения по SPEC (7.9/7.10/fix-gen), часть — баг собственного
эвристического regex (`\b` в ECMAScript не работает после кириллицы), исправлен
на lookahead. Итог — `+1592 ~7` зелёные (см. `verify.md`).
