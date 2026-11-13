# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3a «Парсеры» — **завершена** (verify/summary), ждёт push по команде владельца · **Следующая:** 3b «Провайдеры» · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; локальная Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub-remote `origin` → piotrcheban-pixel/cardflow; локальный `main` = `origin/main` + коммиты итерации 3a (`4b91adc`…`ecf845a` + docs), рабочее дерево clean. Последний CI — зелёный: прогон [`43468349877`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43468349877) attempt 4 — все 9 job success (включая `build android` после фикса диска и `build ios` с 4-й попытки L22). Прогон итерации 3a в CI **ещё не выполнялся** (push — по команде владельца).

## Следующее действие

1. **Push итерации 3a** (по команде владельца): `git push origin main` → дождаться CI-прогона.
   Первым делом смотреть `test` (Linux/Windows/macOS): там впервые в CI собираются native assets **pdfrx/PDFium**
   для PDF-тестов (L26). При падении только PDF-тестов на какой-то ОС — платформенный skip + `KNOWN_LIMITATIONS`,
   тесты не удалять; при падении по другой причине — разбирать лог.
2. После зелёного CI — **итерация 3b «Провайдеры»** (SPEC A8.2/A8.3: 3 адаптера OpenAI/Gemini/Anthropic,
   строгая схема, локальная валидация, retry/backoff, 429/5xx/401, редактирование логов; ключей API нет —
   mock/контрактные тесты, live — skip). Перед стартом сверить STATE с репозиторием.

## Итерация 3a — итог

- **Сделано:** нативные парсеры A8.3 (`lib/api/parsers/`): PDF (pdfrx/PDFium в изоляте), DOCX/PPTX/ODT
  (archive+xml), XLSX (excel_plus: листы, кэш формул, даты), TXT/MD (BOM/UTF-8/cp1251/KOI8-R), RTF
  (собственный конвертер); `ParsedDocument` с нормализацией и границами разделов (домен `lib/domain/text/`);
  `FileParsingService` (лимит 25 МБ, сигнатуры, `Isolate.run`, ошибки по файлу); ARB-сообщения ошибок.
  ADR-010 (+дополнения), `docs/parsers.md`, `docs/dependencies.md` §9–§10.
- **Доказательства:** `fvm flutter test` → **595 тестов зелёные** (+111); `analyze` 0; `format` 0 (142 файла);
  покрытие **95.3% (3152/3309)**; новые парсеры 85.3–100%; `build windows --release` → `cardflow.exe`;
  ревью `journal/iteration-3a/review.md` — 0 blocker/critical, 2 high/8 medium/9 low → fix `ecf845a`.
- **Ревью:** независимый reviewer (fresh context) на снимке `e12d819`; высокие находки: RTF `\*`-группы
  (потеря видимого текста полей) и XLSX без ZIP-лимитов (zip-bomb/OOM) — исправлены с тестами; mediums M1–M8
  закрыты; lows L1–L3/L6/L8 исправлены, L4/L5/L7/L9 задокументированы/закрыты (L7 — docs, L9 — ADR).
- **Коммиты:** `4b91adc` (enough_convert), `27fadd7` (план/ADR-010/спайки), `6c3a019` (красная фаза +12/−70),
  `ba13128` (домен), `7501ffe` (DOCX/PPTX/ODT), `e12d819` (XLSX/TXT/RTF/PDF/сервис/ARB), `ecf845a` (fix ревью),
  `+ docs` (verify/summary/parsers.md/STATE/AGENTS). Рабочее дерево — clean.
- **Не проверено:** CI-прогон 3a (L26), реальные Word/LibreOffice/PDF-файлы (L23), 25 МБ/OOM (L25);
  вложенные таблицы DOCX уплощаются и нумерация списков не извлекается (L24); формула без кэша → `=формула` (L27).

## Открытые вопросы к владельцу

Нет. Платных зависимостей нет (PDF — pdfrx/MIT; RTF — собственный конвертер); SPEC не менялся; удаление
функций не предлагалось. Push/CI-прогон итерации 3a — по отдельной команде.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (устаревание due-счётчиков), L11 (живые диалоги file_picker/mobile), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15/L16/L17, L18 (neighbor-squish), L19 (семантика «Новые» vs очередь), L20 (сессия без requeue), **L23** (реальные файлы не проверялись), **L24** (вложенные таблицы DOCX/нумерация), **L25** (25 МБ/производительность/OOM), **L26** (pdfrx в CI Linux/macOS — до прогона 3a), **L27** (формула без кэша → `=формула`). L9/L9b/L21/L22 сняты, L2b/L3/L6b сняты ранее.
