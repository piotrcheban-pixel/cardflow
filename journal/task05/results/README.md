# TASK 05 — результаты live-прогонов

**Статус каталога:** результатов нет, потому что live-тесты **не запускались**
(запрет до отдельного подтверждения владельца).

После разрешения здесь появятся файлы:

- `<YYYY-MM-DD>-test-a.md` — Test A (5 карточек, prompt-only);
- `<YYYY-MM-DD>-test-b.md` — Test B (40 карточек, continuity);
- `<YYYY-MM-DD>-test-c.md` — Test C (небольшой документ);
- при необходимости — `defects.md` (найденные дефекты и минимальные фиксы).

Каждый файл собирается из `build/live/task05-a-c.jsonl` и ручной рубрики:

1. дата/время, provider/model, сценарий;
2. `logicalRequests`, `httpRequests`, `httpAttempts`, `retries`,
   `recoveryRequests`, latency;
3. estimated/actual input/output tokens, цены, `estimatedCostUsd`,
   `actualCostUsd`, `guard*`;
4. результат парсинга, число карточек, ошибки/`failures`, recovery events;
5. авто-метрики (`LiveCardQualityReport.toMarkdown`);
6. ручная рубрика 8 критериев (`LiveScenarioAssessment.toMarkdown`), для
   Test C — покрытие/факты/связи;
7. вердикт «принято / доработка» и найденные дефекты.

**Запрещено** записывать в этот каталог ключи, заголовки, тела запросов,
материалы с персональными данными и полные URL с секретными query-параметрами.
Отсутствующие значения фиксируются как `null`/«неизвестно», а не 0.
