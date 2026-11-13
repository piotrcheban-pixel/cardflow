# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3a «Парсеры» — завершена; fix L26 (PDFium в CI) — ждёт зелёного прогона после push · **Следующая:** 3b «Провайдеры» (ждём отдельного go) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; локальная Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub-remote `origin` → piotrcheban-pixel/cardflow; локальный `main` = `origin/main` + коммиты итерации 3a (`4b91adc`…`ecf845a` + docs), рабочее дерево clean. CI: последний **зелёный** — [`43468349877`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43468349877) (9/9, диск-фикс + L22); прогон итерации 3a [`43484685899`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43484685899) — 7/9, упали `test (ubuntu)`/`test (macos)` из-за L26 (PDFium не грузится в `flutter test`); фикс — CI-бутстрап PDFium (pinned `chromium/8125` + sha256 + `PDFIUM_PATH`) и guard, ждёт зелёного прогона после push.

## Следующее действие

1. **Push фикса L26** (разрешён владельцем) → дождаться CI-прогона. Критерий приёмки: `test (ubuntu-latest)` и
   `test (macos-latest)` success и все 9 job success в одном прогоне. L22 (macOS-раннер) — перезапуск job'а через
   API без смены label; падение не по capacity — фиксить с отдельным коммитом на каждый цикл.
2. После зелёного CI — **стоп**: итерация 3a и L26 закрыты, **3b «Провайдеры» не начинать** до отдельного «go»
   владельца (план/ветки/STATE под 3b не готовятся).

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
- **Не проверено:** зелёный CI-прогон после L26-фикса (ожидается), реальные Word/LibreOffice/PDF-файлы (L23), 25 МБ/OOM (L25);
  вложенные таблицы DOCX уплощаются и нумерация списков не извлекается (L24); формула без кэша → `=формула` (L27).

## Открытые вопросы к владельцу

Нет. Платных зависимостей нет (PDF — pdfrx/MIT; RTF — собственный конвертер); SPEC не менялся; удаление
функций не предлагалось. Push фикса L26 разрешён; зелёный прогон — критерий закрытия; 3b — по отдельной команде.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (устаревание due-счётчиков), L11 (живые диалоги file_picker/mobile), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15/L16/L17, L18 (neighbor-squish), L19 (семантика «Новые» vs очередь), L20 (сессия без requeue), **L23** (реальные файлы не проверялись), **L24** (вложенные таблицы DOCX/нумерация), **L25** (25 МБ/производительность/OOM), **L26** (PDFium в CI — исправлен бутстрапом, ждёт зелёного прогона), **L27** (формула без кэша → `=формула`). L9/L9b/L21/L22 сняты, L2b/L3/L6b сняты ранее.
