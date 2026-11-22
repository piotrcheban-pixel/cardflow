# Индекс доказательств (скриншоты)

Все снимки — `review/screenshots/`, сняты с клиентской области окна release-сборки (`53ead19`), DPI 150 % (1 логический px = 1,5 физического). Имена: `<экран>_<номер/состояние>_<размер>.png`; суффикс `_work` = рабочий размер 1660×900, на котором выполнялись интерактивные проверки.

## Списки и колоды
| Файл | Что доказывает |
|---|---|
| `decks_1920x1080.png`, `decks_1366x768.png`, `decks_1024x768.png`, `decks_800x600.png` | «Мои колоды», 4 обязательных разрешения |
| `decks_00_first_launch_real_db.png` | первый снимок приложения до вмешательства |
| `decks_02_search_no_results_*` | пустой результат поиска: чужой текст и кнопка «Отмена» |
| `decks_04_create_dialog.png`, `decks_05_create_validation.png`, `decks_06_deck_created.png` | создание колоды, валидация, результат |
| `decks_07_fake_search_no_input.png` | поле-обманка «Поиск карточек…» в боковой панели |
| `firstrun_01_empty_decks_*` | первый запуск на пустой БД (включая 800×600) |
| `dark_01_decks.png` | тёмная тема |
| `a11y_01_decks_bigfont.png` | масштаб текста 150 %, переполнений нет |
| `a11y_02_tab_focus.png` | три `Tab` — фокус не виден |
| `verify_restored_data.png` | данные владельца после восстановления (идентично исходному) |

## Колода
| Файл | Что доказывает |
|---|---|
| `deck_01_main_*` | экран колоды, 4 разрешения |
| `deck_02_modes_sheet_*` | лист режимов, 4 разрешения |
| `deck_03_sheet_closed_esc.png` | `Esc` закрывает лист |
| `deck_05_cloze_raw_markup_in_list.png` | сырая разметка `{{c1::…}}` в списке карточек |
| `deck_07_menu.png` | меню колоды |
| `deck_08_empty_deck.png`, `deck_09_empty_snackbar.png` | пустая колода и «Начать сессию» |
| `deck_10_modes_mixed.png`, `deck_11_modes_disabled_2cards.png` | недоступные режимы и их формулировки |
| `deck_12_daily_limit_dialog_*`, `deck_13_no_limit_warning.png` | диалог дневного лимита и отсутствие предупреждения на колоде |
| `deck_04_after_session_exit.png`, `deck_06_after_session.png` | состояние колоды после выхода из сессии |

## Обучение
| Файл | Что доказывает |
|---|---|
| `study_04_front.png` | карточка до раскрытия |
| `study_11_rated_without_reveal.png` | **оценка без раскрытия** (счётчик 1→2, «Оценено: 1») |
| `study_05_revealed_no_question.png` | раскрытая карточка без вопроса |
| `study_10_classic_revealed_*` | раскрытая карточка, 4 разрешения (включая обрезание на 800×600) |
| `study_01_revealed_*` | то же до рестарта профиля (4 разрешения) |
| `study_06_cloze_front.png`, `study_07_cloze_revealed.png` | cloze: пропуск и раскрытие |
| `study_02_exit_dialog_*` | диалог выхода, 4 разрешения |
| `study_02b_exit_dialog_from_plan.png`, `study_02c_dialog_closed_esc.png` | диалог из сессии по плану; `Esc` закрывает диалог |
| `study_09_esc_noop.png` | `Esc` на экране сессии ничего не делает |
| `study_03_undo_snackbar_overlap.png` | снекбар перекрывает кнопки оценок |
| `study_08_completed.png` | завершение сессии |
| `study_14_undo_after_completion.png` | undo после завершения |
| `study_13_front_real_profile.png` | карточка в реальном профиле |
| `feed_01_initial.png`, `feed_02_after_timer.png`, `feed_03_revealed.png` | лента: старт, таймер, раскрытие |
| `practice_01.png` | тренировка |
| `typing_01_question.png`, `typing_02_correct.png` | ввод ответа: вопрос и «Верно» |
| `truefalse_01.png`, `truefalse_02_correct_no_feedback.png`, `truefalse_03_wrong_feedback.png` | верно/неверно: вопрос, верный ответ без обратной связи, ошибка |

## Карточки (форма)
| Файл | Что доказывает |
|---|---|
| `cardform_01_edit.png` | редактирование: срезанная подпись «Вопрос», тип read-only |
| `cardform_02_filled_latex.png` | карточка с LaTeX в полях |
| `cardform_04_unsaved_discarded.png` | правки потеряны без предупреждения |
| `cardform_05_new_empty.png`, `cardform_06_validation_errors.png` | пустая форма и ошибки валидации, перекрытые нижней панелью |
| `cardform_07_images_section.png` | секция изображений и масок |
| `cardform_08_saved_snackbar.png` | снекбар после сохранения |
| `cardform_09_cloze_error.png`, `cardform_10_cloze_error_offscreen.png` | ошибка cloze и её невидимость при прокрутке |
| `cardform_11_cloze_selected.png`, `cardform_13_cloze_syntax_typed.png` | выбранный тип и введённый синтаксис `{{c1::…}}` |
| `cardform_12_ctrl_a_failed_garbled.png` | последствие неудачной попытки заменить текст (побочный артефакт аудита) |

## Конструктор, статистика, настройки, генерация
| Файл | Что доказывает |
|---|---|
| `constructor_01_*`, `constructor_02.png`, `constructor_03_selected.png`, `constructor_04_session_plan.png` | конструктор: 4 разрешения, выбор колоды, старт сессии по плану |
| `stats_01_*` | статистика, 4 разрешения |
| `stats_03_retention_blob.png` | «клякса» вместо графика недели + удержание 100 % при n=1 |
| `stats_04_forecast_weak.png` | прогноз с однобуквенными подписями и ряд нулей |
| `settings_01_*` | настройки, 4 разрешения |
| `settings_10_appearance.png`, `settings_08_a11y.png`, `settings_04_a11y_dark.png` | разделы «Оформление», «Доступность» (светлая/тёмная) |
| `settings_05_font_scale_max.png` | максимальный масштаб шрифта |
| `settings_09_api_section.png`, `settings_06_real_ai_section.png` | блок API (одноразовый/реальный профиль) |
| `settings_11_about.png` | «О приложении» |
| `settings_12_daily_limits.png`, `settings_13_daily_limits_values.png` | дневные лимиты/доступность в реальном профиле |
| `settings_02_providers_*`, `providers_02_broken_primary.png` | список провайдеров, невалидный «Основной» |
| `providers_03_edit_dialog.png` | диалог изменения провайдера обрезан |
| `licenses_01.png` | экран лицензий |
| `generation_01_form.png` | форма генерации: баннер ошибки с нечитаемой ссылкой |
| `generation_02_model_section.png` | нижняя часть формы: нет видимого выхода |
| `generation_03_esc_noop.png` | `Esc` на экране генерации не работает |
| `generation_04_scrolled_top.png` | возврат к началу формы |

## Импорт
| Файл | Что доказывает |
|---|---|
| `import_01.png`, `import_01_picker.png`, `import_02_cancelled.png` | импорт: стартовый экран, системный выбор файла (`Select File`), отмена |
