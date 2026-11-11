# STATE — текущее состояние CardFlow

**Дата:** 2026-11-11 · **Итерация:** 0 (Каркас) · **Шаг цикла:** 1 (План) → выполняется
**Автономность:** ИТЕРАЦИИ · **Режим:** остановка после отчёта по итерации 0

## Статус «Следующее действие»

Следующее действие: установить Flutter 3.47.9 (закреплён через FVM) → `flutter create` 5 платформ → локализация ru → guard-тесты → FSRS-тест.

## Что уже сделано (проверено в этой сессии)

- Репозиторий инициализирован (`git init`, `main`), локальные имя/почта git заданы.
- `SPEC.md` скопирован в корень (sha256 совпадает с `work/SPEC.md`); `docs/agent-prompt.md` — сохранённая копия стартового промпта (разделы 0–14).
- Создан скелет каталогов: `docs/`, `docs/decisions/`, `journal/iteration-0/`, `lib/{domain,data,api,ui}`, `test/{unit,widget,integration,golden,guards}`, `.github/workflows/`.
- Написаны `.gitignore`, `AGENTS.md`, `journal/iteration-0/plan.md`, `journal/KNOWN_LIMITATIONS.md`.
- FVM 4.3.2 установлен standalone в `C:\Users\piotr\fvm`, PATH пользователя обновлён; `fvm list` работает.
- Идёт скачивание Flutter SDK 3.47.9 stable (Dart 3.13.7), sha256 будет сверен до распаковки.
- Запущен `deps-researcher` (task-1): проверка пакетов на pub.dev → `docs/dependencies.md`, ADR-001/002/003.

## Открытые вопросы / риски

- Flutter ещё не распакован; FVM-кэш пуст (`C:\Users\piotr\fvm\versions`).
- Хуки DSH не подключены, навыки Flutter недоступны → известные ограничения L4/L5.
- Нет git-remote → CI-прогон невозможен (L3); Android SDK/JDK/Xcode нет (L2).
