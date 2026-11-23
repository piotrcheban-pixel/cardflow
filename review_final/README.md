# review_final — финальный визуальный аудит CardFlow

Снимок `fbe344a`. Аудит внешнего вида (art direction / product design), без правок кода.

| Документ | Что внутри |
|---|---|
| [REPORT.md](REPORT.md) | Вердикт **НЕ ГОТОВО**, 37 находок (F01–F37) с замерами и кадрами, оценки 1–10, топ-20, визуальный долг, ограничения |
| [GATES.md](GATES.md) | Гейты V1–V12: PASS/FAIL, измерения, кадры, требования к исправлению |
| [MEASUREMENTS.md](MEASUREMENTS.md) | Числа по разрешениям: карточка, шрифты, кнопки, изображения, пустоты, доли площадей, контраст, палитра |
| [ANIMATIONS.md](ANIMATIONS.md) | Инвентаризация анимаций, разрывы reduced motion, требования |
| [CHECKLIST.md](CHECKLIST.md) | Каждый экран/состояние: проверено живьём/рендером/кодом или не проверено (с причиной) |

## Скриншоты

- `screenshots/live_*` — живое приложение (`cardflow.exe`, Debug, 150 % DPI), 2560×1440 … 800×600, 21:9.
- `screenshots/rendered/` — production-экраны на точных размерах: карточка (15 размеров × вопрос/ответ), 12 экранов × 7 конфигураций, изображения, состояния, тёмная тема. 4K — только здесь (ОС не даёт окно больше экрана).
- `screenshots/_contact_*.png` — сводные листы для быстрого просмотра.

## Инструменты (воспроизводимо)

| Файл | Назначение |
|---|---|
| `tools/render_card_test.dart` | Карточка классики/ленты, 15 конфигураций, замеры геометрии/кеглей/пустоты |
| `tools/render_screens_test.dart` | 12 экранов × 7 конфигураций, ширины колонок, переполнения, размеры кнопок |
| `tools/render_images_test.dart` | Изображения 3 пропорций × 4 конфигурации + сетка двух |
| `tools/render_states_test.dart` | Пусто/ошибка/загрузка/меню/удаление |
| `tools/render_direct_states_test.dart` | `ReviewCompletedView`, `ReviewEmptyView`, `ReviewLoadErrorView`, `ReviewTimeUpView` |
| `tools/ui.ps1`, `tools/sweep.ps1` | Управление живым окном и серии скриншотов |
| `tools/analyze.py`, `contrast.py`, `palette.py`, `visual_debt.py`, `anim_inventory.py` | Пиксельные замеры, контраст WCAG, палитра, визуальный долг, инвентарь анимаций |
| `raw/` | Логи прогонов (`render_card.txt`, `screens_run.txt`, `contrast.txt`, `palettes.txt`, `animations.txt`, `screens_run.txt`) |

Запуск (из корня репозитория):

```
.fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_card_test.dart --no-pub
.fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_screens_test.dart --no-pub
.fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_images_test.dart --no-pub
.fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_states_test.dart --no-pub
.fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_direct_states_test.dart --no-pub
python review_final/tools/contrast.py
python review_final/tools/palette.py review_final/screenshots/rendered/card_classic_A_2k150.png
```
