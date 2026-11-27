# Verify — генерация v3, срез 2 (журнал, стейт-машина, порты)

**Дата:** 2026-11-27 · **Срез:** `TASK.txt` «Срез 2. Ledger, стейт-машина
прогона, порты» · **Снимок:** `main`, от `fe76629` (docs среза 1).

## Что проверялось

Бухгалтерия прогона (`requested/generated/invalid/duplicates/accepted/
remaining` по партиям и суммарно, класс недобора), стейт-машина этапов
(`planned → … → replenishing → ready | partial | failed | cancelled`,
недопустимый переход — исключение) и порты этапов (`LlmPort`, `CardSink`,
`ProgressSink`, `Clock`, `KnowledgeMapCache`).

## Красная фаза

`journal/generation-v3/red-s2.txt` — прогон тестов на скелетах до реализации:
**28 падений assertion-level**, например

- `Expected: <211> Actual: <0>` (Σ бюджетов против `requested`);
- `Expected: throws <Instance of 'AssertionError'> Actual: returned
  GenerationLedger:<GenerationLedger()>` (инварианты журнала);
- `Expected: contains 'принято 3/8' Actual: 'GenerationLedger()'`;
- `Expected: throws <Instance of 'InvalidGenerationStageTransition'>` на
  `generating → ready`.

То есть красная фаза — не только ошибка компиляции (ретроспектива итерации 0).

## Гейты итогового снимка

| Команда | Результат |
|---|---|
| `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` | **No issues found!** (0 issues) |
| `.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` | **628 files — 0 changed** |
| `.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage --exclude-tags golden` | **2863 passed + 17 skipped**, `exit 0` |
| baseline до среза | 2825 passed + 17 skipped |
| новые тесты | **+38** (`generation_ledger_test` 21, `generation_stage_test` 11, `ports_test` 5, guard +1) |
| покрытие рукописного кода (`tool/coverage_check.dart --min=80`) | **90.8 % (23860/26277)**, порог пройден |

**Покрытие новых файлов.**

| Файл | Покрытие |
|---|---|
| `lib/domain/generation/generation_ledger.dart` | **100 % (99/99)** |
| `lib/domain/generation/ports.dart` | не измеряется: только объявления портов, исполняемых строк нет (прецедент — `api_key_store.dart`, репозитории портов) |
| `lib/domain/generation/generation_run.dart` (изменён) | 94.7 % (36/38); непокрыты прежние `planWarnings` — к срезу не относятся |

DoD «покрытие новых файлов ≥90 %» выполнен на всём исполняемом новом коде:
журнал — 100 %, новые ветки стейт-машины покрыты матрицей переходов 10×10.

## DoD среза 2

| Требование `TASK.txt` | Как закрыто |
|---|---|
| Property-тест: сумма бюджетов == `requested` на случайных планах | `generation_ledger_test.dart` → «DoD: property-тесты сумма бюджетов партий == requested на случайных планах»: 200 итераций `Random(20261127)`, случайный заказ 1…300, случайное разбиение на 1…9 партий, план собирается `testPlanFromChunks` (production тип `GenerationPlan`); проверяются Σ бюджетов, `ledger.requested == plan.requestedCards` и порядок партий |
| Тест переходов: `generating → ready` невозможно | `generation_stage_test.dart` → «DoD: переход generating → ready невозможен» (исключение с `from`/`to`) + «полная матрица переходов согласована» (все 10×10 пар: `allowedNext`/`canAdvanceTo`/`advanceTo` согласованы) |
| Ledger после сбоя батча сохраняет принятое | `generation_ledger_test.dart` → «DoD: после сбоя батча принятое сохраняется»: партия 0 приняла 3 из 6, партия 1 упала `provider_error` — принятое партии 0 не теряется ни при `markCause`, ни при повторном `replace`, долг 9, класс прогона `provider_error` |
| Покрытие новых файлов ≥90 % | см. таблицу выше: `generation_ledger.dart` 100 %; `ports.dart` без исполняемых строк |

## Решения и толкования

1. **Стейт-машина — в существующем `generation_run.dart`** (TASK.txt называет
   файл `generation_run.dart`, а он уже есть в `lib/domain/generation/` с
   `GenerationRunRequest/Result`). Новый файл с тем же именем в другом слое
   создал бы два «прогона»; старые типы не менялись, добавлены
   `GenerationStage`, `GenerationRunState`, `InvalidGenerationStageTransition`
   и маппинг `GenerationStage.jobStatus` на `generation_jobs.status` (SPEC A5).
2. **`ready`/`partial` — только из `replenishing`** (дословная цепочка
   TASK.txt: `dedup → replenishing → ready|partial`). `failed` и `cancelled`
   разрешены с любого незавершённого этапа: сбой/отмена возможны на любом шаге.
3. **Самопереход запрещён**; `planned → generating` и любые пропуски этапов —
   исключение (проверяется матрицей).
4. **Класс недобора для дублей** — `validation_rejects` (в списке TASK.txt
   класса «дубли» нет); счётчик `duplicates` при этом отдельный (Q5).
5. **Приоритет класса прогона** — `cancelled` → `provider_error` → `truncated`
   → `exhausted_material` → `validation_rejects` (Q7). У партии без событий
   `shortfall == null` — причина ещё неизвестна.
6. **`KnowledgeMapCache<M>` параметризован типом карты**: тип `KnowledgeMap` —
   предмет S2 BACKLOG, срез 2 его не создаёт (Q6).
7. **`LlmPort` не реализован поверх провайдеров** (TASK.txt: «это срез 5»);
   контракт реализуется одним адаптером `CardGenerationService.generate` без
   изменения сервиса.
8. **Guard расширен, а не добавлен отдельным файлом:**
   `test/guards/architecture_test.dart` теперь запрещает `package:dio/` и
   `package:drift/` в `lib/domain/` — это делает «Dio и drift в этапах
   запрещены» проверяемым правилом для всех будущих этапов.
9. **Схема БД, UI, старый конвейер не менялись** (protocol §9: старый путь не
   удаляется, пока новый не покрыт и не включён флагом).

## Известная хрупкость прогона

`test/integration/settings_persistence_file_db_test.dart` на полном прогоне под
нагрузкой иногда падает `TimeoutException 30s` (файловая drift-БД в OneDrive);
в этом прогоне зелёный. К срезу не относится (новые файлы БД не трогают).
