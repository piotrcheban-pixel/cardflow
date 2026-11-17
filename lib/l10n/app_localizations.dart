import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ru')];

  /// Название приложения. Бренд, латиница допустима (SPEC 3.1).
  ///
  /// In ru, this message translates to:
  /// **'CardFlow'**
  String get appTitle;

  /// Кнопка отмены в диалогах (общая).
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// Кнопка сохранения в диалогах (общая).
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// Кнопка удаления в диалогах (общая).
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get delete;

  /// Действие снекбара: отменить последнюю операцию (архив колоды).
  ///
  /// In ru, this message translates to:
  /// **'Отменить'**
  String get undo;

  /// Кнопка повторной загрузки после ошибки.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retry;

  /// Общая ошибка операции без подробностей исключения.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие. Попробуйте ещё раз.'**
  String get genericError;

  /// Заголовок экрана «Колоды» (SPEC A6.2).
  ///
  /// In ru, this message translates to:
  /// **'Мои колоды'**
  String get decksTitle;

  /// Подсказка иконки поиска на экране «Колоды».
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get decksSearchTooltip;

  /// Подсказка иконки фильтра на экране «Колоды».
  ///
  /// In ru, this message translates to:
  /// **'Фильтр'**
  String get decksFilterTooltip;

  /// Подсказка поля поиска колод.
  ///
  /// In ru, this message translates to:
  /// **'Поиск колод'**
  String get decksSearchHint;

  /// Подсказка кнопки очистки поиска.
  ///
  /// In ru, this message translates to:
  /// **'Очистить поиск'**
  String get decksSearchClearTooltip;

  /// Чип фильтра: все активные колоды.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get deckFilterAll;

  /// Чип фильтра: колоды с новыми карточками.
  ///
  /// In ru, this message translates to:
  /// **'Новые'**
  String get deckFilterNew;

  /// Чип фильтра: колоды с карточками в процессе изучения.
  ///
  /// In ru, this message translates to:
  /// **'В процессе'**
  String get deckFilterInProgress;

  /// Чип фильтра: колоды с просроченными карточками.
  ///
  /// In ru, this message translates to:
  /// **'Просроченные'**
  String get deckFilterDue;

  /// Пустое состояние списка колод.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет колод'**
  String get decksEmptyTitle;

  /// Пояснение в пустом состоянии списка колод.
  ///
  /// In ru, this message translates to:
  /// **'Создайте колоду вручную или импортируйте её из ZIP-архива.'**
  String get decksEmptyMessage;

  /// Пустой результат поиска/фильтра по колодам.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get decksNoResults;

  /// Сводная строка в шапке «Мои колоды»: карточек к повторению и число колод.
  ///
  /// In ru, this message translates to:
  /// **'К повторению: {due} · колод: {decks}'**
  String decksSummary(Object decks, Object due);

  /// Подсказка в пустом результате поиска/фильтра по колодам.
  ///
  /// In ru, this message translates to:
  /// **'Попробуйте изменить запрос или фильтр.'**
  String get decksNoResultsHint;

  /// Состояние ошибки загрузки списка колод (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить колоды'**
  String get decksErrorTitle;

  /// Основная кнопка создания колоды (Split button).
  ///
  /// In ru, this message translates to:
  /// **'Создать'**
  String get decksCreateButton;

  /// Расширенная FAB-кнопка создания колоды.
  ///
  /// In ru, this message translates to:
  /// **'Создать колоду'**
  String get decksCreateDeckFab;

  /// Пункт меню создания: ввести название вручную.
  ///
  /// In ru, this message translates to:
  /// **'Вручную'**
  String get decksCreateManual;

  /// Пункт меню/кнопка импорта колоды из ZIP-архива.
  ///
  /// In ru, this message translates to:
  /// **'Импорт ZIP'**
  String get decksImportZip;

  /// Подсказка кнопки меню действий с колодой.
  ///
  /// In ru, this message translates to:
  /// **'Действия с колодой'**
  String get decksMenuTooltip;

  /// Пункт меню колоды: переименовать.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать'**
  String get deckRename;

  /// Пункт меню колоды: экспортировать в ZIP.
  ///
  /// In ru, this message translates to:
  /// **'Экспорт'**
  String get deckExport;

  /// Пункт меню колоды: отправить колоду в архив (альтернатива свайпу, доступность).
  ///
  /// In ru, this message translates to:
  /// **'Архивировать'**
  String get deckActionArchive;

  /// Подсказка второй (меню) сегмента Split-кнопки «Создать».
  ///
  /// In ru, this message translates to:
  /// **'Другие способы создания'**
  String get decksCreateMenuTooltip;

  /// Количество карточек в колоде (плюрализация).
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Нет карточек} one{{count} карточка} few{{count} карточки} many{{count} карточек} other{{count} карточки}}'**
  String deckCardCount(int count);

  /// Счётчик просроченных карточек (на карточке колоды и экране колоды).
  ///
  /// In ru, this message translates to:
  /// **'К повторению: {count}'**
  String deckDueCount(int count);

  /// Счётчик новых карточек на экране колоды.
  ///
  /// In ru, this message translates to:
  /// **'Новые: {count}'**
  String deckNewCount(int count);

  /// Счётчик карточек в процессе изучения на экране колоды.
  ///
  /// In ru, this message translates to:
  /// **'В процессе: {count}'**
  String deckInProgressCount(int count);

  /// Заголовок диалога создания колоды.
  ///
  /// In ru, this message translates to:
  /// **'Новая колода'**
  String get deckCreateDialogTitle;

  /// Заголовок диалога переименования колоды.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать колоду'**
  String get deckRenameDialogTitle;

  /// Подпись поля названия колоды.
  ///
  /// In ru, this message translates to:
  /// **'Название колоды'**
  String get deckNameLabel;

  /// Ошибка валидации: пустое название колоды.
  ///
  /// In ru, this message translates to:
  /// **'Введите название колоды'**
  String get deckNameEmptyError;

  /// Заголовок диалога подтверждения удаления колоды.
  ///
  /// In ru, this message translates to:
  /// **'Удалить колоду?'**
  String get deckDeleteDialogTitle;

  /// Пояснение в диалоге удаления колоды.
  ///
  /// In ru, this message translates to:
  /// **'Колода «{name}» и все её карточки будут удалены без возможности восстановления.'**
  String deckDeleteDialogMessage(String name);

  /// Сообщение снекбара после архивации колоды (с действием «Отменить»).
  ///
  /// In ru, this message translates to:
  /// **'Колода в архиве'**
  String get deckArchivedMessage;

  /// Сообщение снекбара об успешном экспорте колоды.
  ///
  /// In ru, this message translates to:
  /// **'Колода экспортирована'**
  String get deckExportSuccess;

  /// Сообщение снекбара об успешном импорте колоды.
  ///
  /// In ru, this message translates to:
  /// **'Колода импортирована'**
  String get deckImportSuccess;

  /// Запасное имя файла экспорта, если название колоды пустое после очистки.
  ///
  /// In ru, this message translates to:
  /// **'Колода'**
  String get deckDefaultFileName;

  /// Состояние экрана колоды, если колода удалена или не существует.
  ///
  /// In ru, this message translates to:
  /// **'Колода не найдена'**
  String get deckNotFound;

  /// Состояние ошибки загрузки экрана колоды (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить колоду'**
  String get deckErrorTitle;

  /// Пустое состояние списка карточек на экране колоды.
  ///
  /// In ru, this message translates to:
  /// **'В колоде пока нет карточек'**
  String get deckCardsEmpty;

  /// Пояснение к пустому списку карточек колоды.
  ///
  /// In ru, this message translates to:
  /// **'Карточки появятся после создания, генерации или импорта.'**
  String get deckCardsEmptyHint;

  /// Строка тегов карточки на экране колоды.
  ///
  /// In ru, this message translates to:
  /// **'Теги: {tags}'**
  String cardTagsLine(String tags);

  /// Подпись состояния карточки: новая.
  ///
  /// In ru, this message translates to:
  /// **'Новая'**
  String get cardStateNew;

  /// Подпись состояния карточки: изучается.
  ///
  /// In ru, this message translates to:
  /// **'Изучается'**
  String get cardStateLearning;

  /// Подпись состояния карточки: в повторении.
  ///
  /// In ru, this message translates to:
  /// **'В повторении'**
  String get cardStateReview;

  /// Подпись состояния карточки: переизучается.
  ///
  /// In ru, this message translates to:
  /// **'Переизучается'**
  String get cardStateRelearning;

  /// Заголовок диалога предпросмотра импорта.
  ///
  /// In ru, this message translates to:
  /// **'Импорт колоды'**
  String get importPreviewTitle;

  /// Имя импортируемой колоды в предпросмотре.
  ///
  /// In ru, this message translates to:
  /// **'Колода: {name}'**
  String importPreviewDeckName(String name);

  /// Версия формата архива в предпросмотре импорта.
  ///
  /// In ru, this message translates to:
  /// **'Версия формата: {version}'**
  String importPreviewFormatVersion(int version);

  /// Количество карточек в предпросмотре импорта.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Карточек нет} one{{count} карточка} few{{count} карточки} many{{count} карточек} other{{count} карточки}}'**
  String importPreviewCards(int count);

  /// Количество дубликатов, которые будут пропущены при импорте.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Дубликатов нет} one{{count} дубликат} few{{count} дубликата} many{{count} дубликатов} other{{count} дубликата}}'**
  String importPreviewDuplicates(int count);

  /// Количество медиафайлов в предпросмотре импорта.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Без медиафайлов} one{{count} медиафайл} few{{count} медиафайла} many{{count} медиафайлов} other{{count} медиафайла}}'**
  String importPreviewMedia(int count);

  /// Кнопка подтверждения импорта в диалоге предпросмотра.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать'**
  String get importConfirm;

  /// Ошибка импорта: неизвестная версия формата архива.
  ///
  /// In ru, this message translates to:
  /// **'Версия архива не поддерживается. Обновите CardFlow.'**
  String get archiveErrorUnsupportedVersion;

  /// Ошибка импорта: файл не является корректным ZIP-архивом.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать архив: файл повреждён.'**
  String get archiveErrorCorruptZip;

  /// Ошибка импорта: в архиве отсутствует обязательная запись.
  ///
  /// In ru, this message translates to:
  /// **'В архиве нет обязательных файлов.'**
  String get archiveErrorMissingEntry;

  /// Ошибка импорта: некорректный meta.json.
  ///
  /// In ru, this message translates to:
  /// **'Метаданные архива повреждены.'**
  String get archiveErrorInvalidMeta;

  /// Ошибка импорта: некорректные карточки архива.
  ///
  /// In ru, this message translates to:
  /// **'Карточки в архиве повреждены.'**
  String get archiveErrorInvalidCards;

  /// Ошибка импорта: превышены лимиты размера архива.
  ///
  /// In ru, this message translates to:
  /// **'Архив слишком большой.'**
  String get archiveErrorTooLarge;

  /// Ошибка импорта/экспорта: отсутствует медиафайл.
  ///
  /// In ru, this message translates to:
  /// **'В архиве не хватает медиафайлов.'**
  String get archiveErrorMediaMissing;

  /// Ошибка экспорта: колода не найдена.
  ///
  /// In ru, this message translates to:
  /// **'Колода не найдена в архиве.'**
  String get archiveErrorDeckNotFound;

  /// Ошибка импорта: недопустимое имя записи (zip-slip).
  ///
  /// In ru, this message translates to:
  /// **'В архиве недопустимое имя файла.'**
  String get archiveErrorInvalidEntryName;

  /// Общая ошибка операции с архивом без подробностей исключения.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить операцию с архивом. Попробуйте ещё раз.'**
  String get archiveErrorUnknown;

  /// Критическая ошибка старта: БД не открылась (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть базу данных. Перезапустите приложение.'**
  String get databaseOpenError;

  /// Заголовок экрана классической сессии (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'Повторение'**
  String get reviewTitle;

  /// Название классического режима повторения в листе выбора режима.
  ///
  /// In ru, this message translates to:
  /// **'Классический'**
  String get reviewModeClassic;

  /// Название режима «Лента» в листе выбора режима (SPEC A7.3).
  ///
  /// In ru, this message translates to:
  /// **'Лента'**
  String get reviewModeFeed;

  /// Название режима «Тренировка» в листе выбора режима (ADR-025).
  ///
  /// In ru, this message translates to:
  /// **'Тренировка'**
  String get reviewModePractice;

  /// Заголовок экрана тренировки (ADR-025).
  ///
  /// In ru, this message translates to:
  /// **'Тренировка'**
  String get practiceTitle;

  /// Пояснение режима тренировки на экране и в листе режимов.
  ///
  /// In ru, this message translates to:
  /// **'Карточки идут без учёта интервалов: FSRS не меняется.'**
  String get practiceSubtitle;

  /// Пустое состояние тренировки: в колоде нет доступных карточек.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек для тренировки'**
  String get practiceEmptyTitle;

  /// Пояснение пустого состояния тренировки.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте карточки в колоду или снимите приостановку.'**
  String get practiceEmptyMessage;

  /// Итоговый экран тренировки.
  ///
  /// In ru, this message translates to:
  /// **'Тренировка завершена'**
  String get practiceCompletedTitle;

  /// Сколько карточек пройдено в тренировке.
  ///
  /// In ru, this message translates to:
  /// **'Пройдено карточек: {count}.'**
  String practiceCompletedMessage(int count);

  /// Прогресс тренировки: пройдено карточек из всего.
  ///
  /// In ru, this message translates to:
  /// **'Пройдено {count} из {total}'**
  String practiceRatedLabel(int count, int total);

  /// Заголовок bottom sheet выбора режима сессии (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Выберите режим'**
  String get reviewSessionModeTitle;

  /// Заголовок листа режимов сессии на экране колоды (REDESIGN-SPEC §9.3).
  ///
  /// In ru, this message translates to:
  /// **'Режим сессии'**
  String get reviewModeSheetTitle;

  /// Заголовок секции карточек колоды: надпись и число карточек.
  ///
  /// In ru, this message translates to:
  /// **'КАРТОЧКИ · {count}'**
  String deckCardsSection(Object count);

  /// Большая карточка запуска сессии на экране колоды (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Начать сессию'**
  String get reviewStartSession;

  /// Сообщение при попытке начать сессию, когда очередь пуста.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек к повторению'**
  String get reviewStartEmptyMessage;

  /// Пустое состояние экрана сессии.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек к повторению'**
  String get reviewEmptyTitle;

  /// Пояснение пустого состояния экрана сессии.
  ///
  /// In ru, this message translates to:
  /// **'Все карточки на сегодня повторены. Возвращайтесь позже или добавьте новые.'**
  String get reviewEmptyMessage;

  /// Пустое состояние сессии, когда дневной лимит новых карточек израсходован (A6.6, ADR-019 §8).
  ///
  /// In ru, this message translates to:
  /// **'Дневной лимит исчерпан'**
  String get reviewDailyLimitTitle;

  /// Пояснение к исчерпанному дневному лимиту с предложением продолжить без лимита или тренировкой (ADR-028).
  ///
  /// In ru, this message translates to:
  /// **'Дневной лимит на сегодня исчерпан. Можно продолжить без лимита или пройти карточки в режиме «Тренировка» — интервалы FSRS не изменятся.'**
  String get reviewDailyLimitMessage;

  /// Кнопка продолжения изучения с игнорированием дневного лимита (ADR-028, итерация 7.12).
  ///
  /// In ru, this message translates to:
  /// **'Продолжить без лимита'**
  String get reviewDailyLimitContinueAction;

  /// Предупреждение перед продолжением без дневного лимита на экране колоды (ADR-028).
  ///
  /// In ru, this message translates to:
  /// **'Дневной лимит на сегодня исчерпан. Продолжить изучение без лимита или пройти карточки в режиме «Тренировка» — интервалы FSRS не изменятся.'**
  String get reviewDailyLimitContinueMessage;

  /// Кнопка запуска тренировки из пустой сессии и листа режимов.
  ///
  /// In ru, this message translates to:
  /// **'Тренировать'**
  String get practiceStartAction;

  /// Кнопка возврата из пустого/завершённого экрана сессии.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get reviewBack;

  /// Ошибка загрузки карточек при старте сессии (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить карточки сессии.'**
  String get reviewLoadError;

  /// Подсказка кнопки undo в каркасе сессии (SPEC A6.4).
  ///
  /// In ru, this message translates to:
  /// **'Отменить последнюю оценку'**
  String get reviewUndoTooltip;

  /// Сообщение после успешного undo оценки.
  ///
  /// In ru, this message translates to:
  /// **'Оценка отменена'**
  String get reviewUndoneMessage;

  /// Ошибка записи оценки в БД (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить оценку. Попробуйте ещё раз.'**
  String get reviewSaveError;

  /// Ошибка отката оценки (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отменить оценку. Попробуйте ещё раз.'**
  String get reviewUndoError;

  /// Подсказка крестика выхода из сессии (SPEC A6.4).
  ///
  /// In ru, this message translates to:
  /// **'Выйти из сессии'**
  String get reviewCloseTooltip;

  /// Заголовок диалога выхода из сессии (SPEC A6.4).
  ///
  /// In ru, this message translates to:
  /// **'Выйти из сессии?'**
  String get reviewExitDialogTitle;

  /// Пояснение в диалоге выхода: каждая оценка уже записана.
  ///
  /// In ru, this message translates to:
  /// **'Оценки сохраняются сразу, прогресс не потеряется.'**
  String get reviewExitDialogMessage;

  /// Кнопка диалога выхода: остаться в сессии.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get reviewExitContinue;

  /// Кнопка диалога выхода: покинуть сессию.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get reviewExitConfirm;

  /// Подсказка кнопки «Почему?» в каркасе сессии (SPEC A6.4).
  ///
  /// In ru, this message translates to:
  /// **'Почему?'**
  String get reviewWhyTooltip;

  /// Заголовок bottom sheet с цитатой исходника.
  ///
  /// In ru, this message translates to:
  /// **'Почему эта карточка?'**
  String get reviewWhySheetTitle;

  /// Семантическая подпись линейного прогресса классической сессии.
  ///
  /// In ru, this message translates to:
  /// **'Прогресс сессии'**
  String get reviewProgressLabel;

  /// Кнопка паузы авто-продвижения в ленте (SPEC A7.3).
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get feedPause;

  /// Кнопка возобновления авто-продвижения в ленте (SPEC A7.3).
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get feedResume;

  /// Интервал авто-продвижения ленты в секундах (SPEC A7.3: 3/5/8).
  ///
  /// In ru, this message translates to:
  /// **'{count} с'**
  String feedSeconds(int count);

  /// Подсказка выбора интервала авто-продвижения в ленте.
  ///
  /// In ru, this message translates to:
  /// **'Авто-продвижение'**
  String get feedAutoAdvanceTooltip;

  /// Счётчик текущей карточки ленты: «2 из 10».
  ///
  /// In ru, this message translates to:
  /// **'{position} из {total}'**
  String feedCounter(int position, int total);

  /// Пометка оценённой карточки при возврате к ней в ленте.
  ///
  /// In ru, this message translates to:
  /// **'Оценено'**
  String get feedRatedLabel;

  /// Семантическая подпись Stories-прогресса ленты.
  ///
  /// In ru, this message translates to:
  /// **'Оценено {rated} из {total}'**
  String feedProgressSemantics(int rated, int total);

  /// Семантическая подсказка жестов оценки в ленте (SPEC A7.3).
  ///
  /// In ru, this message translates to:
  /// **'Свайп вправо — «Знаю», влево — «Не знаю»'**
  String get feedSwipeHint;

  /// Заголовок состояния завершённой сессии.
  ///
  /// In ru, this message translates to:
  /// **'Сессия завершена'**
  String get reviewCompletedTitle;

  /// Итог сессии: сколько карточек оценено.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Нет оценённых карточек} one{{count} карточка повторена} few{{count} карточки повторено} many{{count} карточек повторено} other{{count} карточки повторено}}'**
  String reviewCompletedMessage(int count);

  /// Кнопка завершения сессии.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get reviewDone;

  /// Кнопка оценки Again (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'Не знаю'**
  String get ratingAgain;

  /// Кнопка оценки Hard (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'Сложно'**
  String get ratingHard;

  /// Кнопка оценки Good (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'Знаю'**
  String get ratingGood;

  /// Кнопка оценки Easy (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'Легко'**
  String get ratingEasy;

  /// Прогноз интервала: меньше минуты (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'<1 мин'**
  String get reviewIntervalLessThanMinute;

  /// Прогноз интервала в минутах (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'{count} мин'**
  String reviewIntervalMinutes(int count);

  /// Прогноз интервала в часах (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'{count} ч'**
  String reviewIntervalHours(int count);

  /// Прогноз интервала в днях (SPEC A7.2).
  ///
  /// In ru, this message translates to:
  /// **'{count} д'**
  String reviewIntervalDays(int count);

  /// Заголовок формы создания карточки (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Новая карточка'**
  String get cardFormTitleNew;

  /// Заголовок формы редактирования карточки (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Редактировать карточку'**
  String get cardFormTitleEdit;

  /// Подпись поля front в форме карточки.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос'**
  String get cardFormFrontLabel;

  /// Подпись поля back в форме карточки.
  ///
  /// In ru, this message translates to:
  /// **'Ответ'**
  String get cardFormBackLabel;

  /// Подпись необязательного поля hint.
  ///
  /// In ru, this message translates to:
  /// **'Подсказка (необязательно)'**
  String get cardFormHintLabel;

  /// Подпись поля тегов; больше трёх тегов запрещено (SPEC A8.4).
  ///
  /// In ru, this message translates to:
  /// **'Теги через запятую (необязательно)'**
  String get cardFormTagsLabel;

  /// Подпись необязательного поля source_excerpt (SPEC A5).
  ///
  /// In ru, this message translates to:
  /// **'Цитата для кнопки «Почему?» (необязательно)'**
  String get cardFormSourceExcerptLabel;

  /// Подпись выбора типа карточки.
  ///
  /// In ru, this message translates to:
  /// **'Тип карточки'**
  String get cardFormTypeLabel;

  /// Тип карточки basic.
  ///
  /// In ru, this message translates to:
  /// **'Обычная'**
  String get cardTypeBasic;

  /// Тип карточки basic_reversed.
  ///
  /// In ru, this message translates to:
  /// **'Двусторонняя'**
  String get cardTypeBasicReversed;

  /// Тип карточки cloze (разметка — итерация 5).
  ///
  /// In ru, this message translates to:
  /// **'С пропусками'**
  String get cardTypeCloze;

  /// Формат карточки occlusion в предпросмотре генерации (итерация 7.9).
  ///
  /// In ru, this message translates to:
  /// **'Изображение с маской'**
  String get cardTypeOcclusion;

  /// Подсказка при выборе двустороннего типа карточки (SPEC A5).
  ///
  /// In ru, this message translates to:
  /// **'Будет создана вторая карточка с обратным вопросом.'**
  String get cardFormReversedHint;

  /// Пояснение при редактировании: тип карточки не меняется (ADR-009).
  ///
  /// In ru, this message translates to:
  /// **'Тип карточки нельзя изменить после создания.'**
  String get cardFormTypeImmutable;

  /// Ошибка валидации: пустой front (SPEC A8.4).
  ///
  /// In ru, this message translates to:
  /// **'Введите вопрос'**
  String get cardFormFrontEmptyError;

  /// Ошибка валидации: front длиннее 500 символов (SPEC A8.4).
  ///
  /// In ru, this message translates to:
  /// **'Не больше 500 символов'**
  String get cardFormFrontTooLongError;

  /// Ошибка валидации: пустой back у basic/basic_reversed (ADR-009).
  ///
  /// In ru, this message translates to:
  /// **'Введите ответ'**
  String get cardFormBackEmptyError;

  /// Ошибка валидации: back длиннее 2000 символов (SPEC A8.4).
  ///
  /// In ru, this message translates to:
  /// **'Не больше 2000 символов'**
  String get cardFormBackTooLongError;

  /// Ошибка валидации: больше трёх тегов (SPEC A8.4).
  ///
  /// In ru, this message translates to:
  /// **'Не больше 3 тегов'**
  String get cardFormTagsTooManyError;

  /// Ошибка валидации: цитата «Почему?» длиннее 400 символов.
  ///
  /// In ru, this message translates to:
  /// **'Не больше 400 символов'**
  String get cardFormSourceExcerptTooLongError;

  /// Ошибка сохранения карточки (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить карточку. Попробуйте ещё раз.'**
  String get cardFormSaveError;

  /// Ошибка загрузки карточки в форме редактирования.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить карточку.'**
  String get cardFormLoadError;

  /// Ошибка удаления карточки (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось удалить карточку. Попробуйте ещё раз.'**
  String get cardFormDeleteError;

  /// Заголовок диалога подтверждения удаления карточки.
  ///
  /// In ru, this message translates to:
  /// **'Удалить карточку?'**
  String get cardDeleteDialogTitle;

  /// Пояснение в диалоге удаления карточки.
  ///
  /// In ru, this message translates to:
  /// **'Карточка будет удалена без возможности восстановления.'**
  String get cardDeleteDialogMessage;

  /// Подсказка кнопки удаления в форме редактирования.
  ///
  /// In ru, this message translates to:
  /// **'Удалить карточку'**
  String get cardDeleteTooltip;

  /// Сообщение после создания карточки.
  ///
  /// In ru, this message translates to:
  /// **'Карточка создана'**
  String get cardCreatedMessage;

  /// Сообщение после сохранения изменений карточки.
  ///
  /// In ru, this message translates to:
  /// **'Изменения сохранены'**
  String get cardUpdatedMessage;

  /// Сообщение после удаления карточки.
  ///
  /// In ru, this message translates to:
  /// **'Карточка удалена'**
  String get cardDeletedMessage;

  /// Подсказка FAB mini «Добавить» на экране колоды (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Добавить карточку'**
  String get deckAddCardTooltip;

  /// Ошибка парсинга: файл не удалось прочитать (SPEC A8.3).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать файл'**
  String get parserErrorUnreadableFile;

  /// Ошибка парсинга: формат не поддерживается, подсказка конвертировать (ADR-003).
  ///
  /// In ru, this message translates to:
  /// **'Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова'**
  String get parserErrorUnsupportedFormat;

  /// Ошибка парсинга: PDF без текстового слоя, похоже на скан (SPEC A8.3).
  ///
  /// In ru, this message translates to:
  /// **'В файле нет текстового слоя. Похоже, это скан. Загрузите PDF с текстом'**
  String get parserErrorScannedPdf;

  /// Ошибка парсинга: файл больше лимита 25 МБ (SPEC A8.3).
  ///
  /// In ru, this message translates to:
  /// **'Файл больше 25 МБ. Уменьшите файл и попробуйте снова'**
  String get parserErrorFileTooLarge;

  /// Ошибка парсинга: в документе нет извлекаемого текста (Word/пустая форма, итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'В файле нет текста (скан или пустая форма)'**
  String get parserErrorEmptyText;

  /// Ошибка парсинга: текстовый слой PDF состоит из символов замены/битой кодировки (итерация 7.10, ADR-024).
  ///
  /// In ru, this message translates to:
  /// **'PDF содержит нечитаемый текст. Сохраните файл в другом формате и попробуйте снова'**
  String get parserErrorGarbledText;

  /// Генерация: ключ API не задан (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа не задан. Добавьте ключ в настройках'**
  String get generationErrorMissingApiKey;

  /// Генерация: у OpenAI-совместимого сервера не заданы адрес или модель (ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'Сервер не настроен. Укажите адрес и модель в настройках'**
  String get generationErrorProviderNotConfigured;

  /// Генерация: провайдер отверг ключ (HTTP 401/403, SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа недействителен. Проверьте ключ в настройках'**
  String get generationErrorInvalidApiKey;

  /// Генерация: запрос отвергнут (HTTP 400/404/422, SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Запрос отклонён. Проверьте выбранную модель и ключ в настройках'**
  String get generationErrorBadRequest;

  /// Генерация: HTTP 400 с причиной провайдера (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Запрос отклонён: {reason}'**
  String generationErrorBadRequestReason(String reason);

  /// Генерация: картинка, а модель без Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Модель не поддерживает изображения'**
  String get generationErrorVisionUnsupported;

  /// Генерация: скан без текста и модель без Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'В файле нет текста. Модель не поддерживает изображения'**
  String get generationErrorFileWithoutTextAndVision;

  /// Генерация: PDF-скан, протокол не принимает PDF (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'PDF-скан не поддерживается выбранной моделью'**
  String get generationErrorPdfScanUnsupported;

  /// Генерация: PDF-скан отрендерен в страницы, а у модели нет Vision (итерация 7.9).
  ///
  /// In ru, this message translates to:
  /// **'PDF-скан без текста. Выберите модель с поддержкой изображений'**
  String get generationErrorPdfScanVisionRequired;

  /// Генерация: вложение больше inline-лимита 10 МБ (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Файл больше 10 МБ. Уменьшите файл и попробуйте снова'**
  String get generationErrorAttachmentTooLarge;

  /// Генерация: HTTP 429 с Retry-After, пауза в секундах (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Превышен лимит запросов. Повтор через {seconds, plural, one{{seconds} секунду} few{{seconds} секунды} many{{seconds} секунд} other{{seconds} секунды}}'**
  String generationErrorRateLimited(int seconds);

  /// Генерация: HTTP 429 без Retry-After (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Превышен лимит запросов. Попробуйте позже'**
  String get generationErrorRateLimitedNoDelay;

  /// Генерация: HTTP 5xx после всех попыток (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Провайдер временно недоступен. Попробуйте позже'**
  String get generationErrorServerUnavailable;

  /// Генерация: таймаут или сетевая ошибка (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Нет подключения к интернету'**
  String get generationErrorNoConnection;

  /// Генерация: пользователь отменил запрос (SPEC A6.8/A8.5).
  ///
  /// In ru, this message translates to:
  /// **'Генерация отменена'**
  String get generationErrorCancelled;

  /// Генерация: модель вернула пустой контент (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Нейросеть вернула пустой ответ. Попробуйте ещё раз'**
  String get generationErrorEmptyResponse;

  /// Генерация: обрезано/отказ/невалидный ответ модели (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Нейросеть вернула неожиданный ответ. Попробовать снова?'**
  String get generationErrorUnexpectedResponse;

  /// Генерация: прочая ошибка без отдельного кода (SPEC A8.6).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось получить карточки. Попробуйте ещё раз'**
  String get generationErrorGeneric;

  /// Подпись поля base_url OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Адрес сервера'**
  String get settingsServerAddressLabel;

  /// Подпись поля модели OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get settingsModelLabel;

  /// Ошибка сохранения настроек сервера (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить настройки. Попробуйте ещё раз'**
  String get settingsSaveError;

  /// Ошибка загрузки настроек сервера (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить настройки. Попробуйте ещё раз'**
  String get settingsLoadError;

  /// Валидация: адрес OpenAI-совместимого сервера пустой.
  ///
  /// In ru, this message translates to:
  /// **'Укажите адрес сервера'**
  String get settingsAddressEmptyError;

  /// Валидация: адрес сервера не является корректным http/https URL.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте адрес: нужен полный адрес с протоколом'**
  String get settingsAddressInvalidError;

  /// Валидация: имя модели OpenAI-совместимого сервера пустое.
  ///
  /// In ru, this message translates to:
  /// **'Укажите модель'**
  String get settingsModelEmptyError;

  /// Подсказка иконки перехода в настройки генерации.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsOpenTooltip;

  /// Индикатор: ключ облачного провайдера сохранён.
  ///
  /// In ru, this message translates to:
  /// **'Ключ сохранён'**
  String get settingsKeyConfigured;

  /// Индикатор: ключ облачного провайдера не задан.
  ///
  /// In ru, this message translates to:
  /// **'Ключ не задан'**
  String get settingsKeyMissing;

  /// Кнопка удаления сохранённого ключа облачного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Удалить ключ'**
  String get settingsKeyDelete;

  /// Валидация: поле ключа облачного провайдера пустое.
  ///
  /// In ru, this message translates to:
  /// **'Введите ключ'**
  String get settingsKeyEmptyError;

  /// Подпись поля ключа облачного провайдера (OpenAI/Gemini/Anthropic).
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа'**
  String get settingsCloudKeyLabel;

  /// Пункт меню Split-кнопки «Создать»: открыть экран генерации (SPEC A6.2/A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать карточки'**
  String get decksCreateGenerate;

  /// Подсказка пункта меню экрана колоды: генерация карточек в эту колоду (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать карточки'**
  String get deckGenerateTooltip;

  /// Заголовок экрана генерации карточек (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Генерация карточек'**
  String get generationTitle;

  /// Подпись зоны прикрепления файлов (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Перетащите файлы сюда или нажмите, чтобы выбрать. Поддерживаются Word, Excel, PDF, PowerPoint, текст, изображения JPG и PNG'**
  String get generationAttachHint;

  /// Кнопка открытия файлового пикера на экране генерации.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать файлы'**
  String get generationAttachButton;

  /// Пустой список прикреплённых файлов.
  ///
  /// In ru, this message translates to:
  /// **'Файлы не прикреплены (необязательно)'**
  String get generationFilesEmpty;

  /// Подсказка кнопки удаления прикреплённого файла.
  ///
  /// In ru, this message translates to:
  /// **'Убрать файл'**
  String get generationFileRemoveTooltip;

  /// Статус парсинга прикреплённого файла.
  ///
  /// In ru, this message translates to:
  /// **'Читаем файл…'**
  String get generationFileParsing;

  /// Статус файла: локальный разбор завершён (SPEC A8.3).
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get generationFileParsed;

  /// Статус файла: JPG/PNG будет отправлен как изображение (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Изображение'**
  String get generationFileImage;

  /// Статус файла: PDF без текстового слоя, будет отправлен как документ при Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Скан — отправится как изображение'**
  String get generationFileScannedPdf;

  /// Статус файла: PDF-скан отрендерен в PNG-страницы (итерация 7.9).
  ///
  /// In ru, this message translates to:
  /// **'Скан — страницы отправятся как изображения'**
  String get generationFilePdfPages;

  /// Размер прикреплённого файла в байтах.
  ///
  /// In ru, this message translates to:
  /// **'{size} Б'**
  String generationFileSizeBytes(int size);

  /// Размер прикреплённого файла в килобайтах.
  ///
  /// In ru, this message translates to:
  /// **'{size} КБ'**
  String generationFileSizeKb(int size);

  /// Размер прикреплённого файла в мегабайтах.
  ///
  /// In ru, this message translates to:
  /// **'{size} МБ'**
  String generationFileSizeMb(int size);

  /// Подпись необязательного поля пожеланий (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Дополнительные пожелания'**
  String get generationWishesLabel;

  /// Подсказка поля пожеланий (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Необязательно. Например: сделайте акцент на датах, или добавьте больше карточек по теме X'**
  String get generationWishesHint;

  /// Подпись выбора провайдера генерации (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Провайдер'**
  String get generationProviderLabel;

  /// Название провайдера OpenAI (бренд, латиница допустима).
  ///
  /// In ru, this message translates to:
  /// **'OpenAI'**
  String get generationProviderOpenAi;

  /// Подпись выбора модели генерации (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get generationModelLabel;

  /// Подпись необязательного поля имени колоды на экране генерации.
  ///
  /// In ru, this message translates to:
  /// **'Имя колоды (необязательно)'**
  String get generationDeckNameLabel;

  /// Подсказка поля имени колоды: значение по умолчанию из первого файла.
  ///
  /// In ru, this message translates to:
  /// **'Пусто — из имени первого файла'**
  String get generationDeckNameHint;

  /// Пояснение, что генерация дополнит существующую колоду.
  ///
  /// In ru, this message translates to:
  /// **'Карточки будут добавлены в колоду «{name}»'**
  String generationTargetDeck(String name);

  /// Имя колоды по умолчанию, если файлов нет и поле пустое.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерированные карточки'**
  String get generationDeckDefaultName;

  /// Оценка объёма материалов в токенах до отправки (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Примерно {count, plural, one{{count} токен} few{{count} токена} many{{count} токенов} other{{count} токена}}'**
  String generationEstimate(int count);

  /// Предупреждение при большом объёме материалов (SPEC A8.5 шаг 4).
  ///
  /// In ru, this message translates to:
  /// **'Материала много: запрос будет разбит на несколько частей'**
  String get generationEstimateWarning;

  /// Валидация: не прикреплено ни одного файла и не задана тема (итерация 7.10, ADR-024).
  ///
  /// In ru, this message translates to:
  /// **'Напишите тему или описание — файлы не обязательны'**
  String get generationTopicRequired;

  /// Валидация: все прикреплённые файлы не разобраны.
  ///
  /// In ru, this message translates to:
  /// **'Ни один файл не удалось прочитать. Проверьте формат и размер файлов'**
  String get generationNoParsedFilesError;

  /// Валидация: генерация запущена, пока файлы ещё парсятся.
  ///
  /// In ru, this message translates to:
  /// **'Дождитесь окончания чтения файлов'**
  String get generationFilesParsing;

  /// Индикатор: для выбранного облачного провайдера нет ключа (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа не задан'**
  String get generationKeyMissing;

  /// Кнопка перехода в настройки генерации, чтобы добавить ключ.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get generationOpenSettings;

  /// Большая primary-кнопка запуска генерации (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать'**
  String get generationStart;

  /// Индикатор прогресса: чтение файлов (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Читаем файлы…'**
  String get generationProgressReading;

  /// Индикатор прогресса: отправка фрагмента K из M (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Отправляем в нейросеть… (фрагмент {current} из {total})'**
  String generationProgressSending(int current, int total);

  /// Индикатор прогресса: получение и разбор карточек (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Получаем карточки…'**
  String get generationProgressReceiving;

  /// Сообщение после отмены генерации.
  ///
  /// In ru, this message translates to:
  /// **'Генерация отменена'**
  String get generationCancelled;

  /// Генерация: после парсинга нет текста (новый код noMaterials, ADR-015).
  ///
  /// In ru, this message translates to:
  /// **'Нет материалов для генерации: прикрепите файл или напишите тему'**
  String get generationErrorNoMaterials;

  /// Генерация: модель вернула валидный пустой массив cards (правило 13 промпта) — это не ошибка ответа, а материал/тема без фактов (ADR-021, ADR-024).
  ///
  /// In ru, this message translates to:
  /// **'Модель не нашла фактов для карточек. Проверьте текст файлов или уточните тему; если материал есть — смените модель'**
  String get generationNoCardsFound;

  /// Заголовок экрана предпросмотра сгенерированных карточек (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Предпросмотр карточек'**
  String get generationPreviewTitle;

  /// Пустое состояние предпросмотра: карточек нет.
  ///
  /// In ru, this message translates to:
  /// **'Модель не вернула карточки'**
  String get generationPreviewEmpty;

  /// Счётчик выбранных карточек в предпросмотре.
  ///
  /// In ru, this message translates to:
  /// **'Выбрано: {selected} из {total}'**
  String generationPreviewSelected(int selected, int total);

  /// Кнопка импорта всех карточек предпросмотра (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Импортировать все'**
  String get generationPreviewImportAll;

  /// Кнопка импорта выбранных карточек предпросмотра (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Импортировать выбранные'**
  String get generationPreviewImportSelected;

  /// Кнопка отмены предпросмотра (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get generationPreviewCancel;

  /// Валидация: импорт выбранных без выбора.
  ///
  /// In ru, this message translates to:
  /// **'Выберите хотя бы одну карточку'**
  String get generationPreviewNoSelection;

  /// Валидация предпросмотра: у выбранной карточки пустой/слишком длинный текст.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте заполнение выбранных карточек: вопрос и ответ должны быть корректными'**
  String get generationPreviewValidationError;

  /// Пометка A8.4: пустой front у сгенерированной карточки.
  ///
  /// In ru, this message translates to:
  /// **'Пустой вопрос'**
  String get generationIssueEmptyFront;

  /// Пометка A8.4: front длиннее 500 символов.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос длиннее 500 символов'**
  String get generationIssueFrontTooLong;

  /// Пометка A8.4: back длиннее 2000 символов.
  ///
  /// In ru, this message translates to:
  /// **'Ответ длиннее 2000 символов'**
  String get generationIssueBackTooLong;

  /// Пометка A8.4: у cloze нет разметки {{cN::…}}.
  ///
  /// In ru, this message translates to:
  /// **'В карточке cloze нет пропусков'**
  String get generationIssueClozeMissing;

  /// Пометка A8.4: формула не парсится flutter_math_fork.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка разметки формулы'**
  String get generationIssueLatexBroken;

  /// Пометка A8.4: source_excerpt обнулена, карточка остаётся.
  ///
  /// In ru, this message translates to:
  /// **'Цитата не найдена в исходном тексте'**
  String get generationIssueExcerptMismatch;

  /// Пометка A8.4: теги обрезаны/нормализованы.
  ///
  /// In ru, this message translates to:
  /// **'Теги скорректированы'**
  String get generationIssueTagsAdjusted;

  /// Пометка итерации 7.9: occlusion без найденной картинки стала обычной.
  ///
  /// In ru, this message translates to:
  /// **'Нет изображения для карточки с маской'**
  String get generationIssueOcclusionImageMissing;

  /// Пометка карточки, для которой поиск картинки не дал результата (ADR-028).
  ///
  /// In ru, this message translates to:
  /// **'Картинка не найдена'**
  String get generationIssueImageNotFound;

  /// Предупреждение в предпросмотре, что поиск картинок не дал результата (ADR-028, итерация 7.12).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось найти картинку по запросу: {count}. Добавьте её вручную или измените вопрос.'**
  String generationImageSearchFailed(int count);

  /// Пометка fix-gen: image_id модели не найден в каталоге <images>.
  ///
  /// In ru, this message translates to:
  /// **'Изображение не найдено в файлах — карточка без картинки'**
  String get generationIssueImageIdUnknown;

  /// Пометка fix-gen: image_query обнулён (не латиница, длиннее 7 слов, задан image_id).
  ///
  /// In ru, this message translates to:
  /// **'Поисковый запрос картинки скорректирован'**
  String get generationIssueImageQueryAdjusted;

  /// Пометка fix-gen: image_query для аксиомы/закона/теоремы/формулы обнулён.
  ///
  /// In ru, this message translates to:
  /// **'Для абстрактного понятия картинка не ищется'**
  String get generationIssueAbstractImageQuery;

  /// Пометка качества A8.1: back (или формула из него) повторяется во front.
  ///
  /// In ru, this message translates to:
  /// **'Ответ уже содержится в вопросе'**
  String get generationIssueAnswerInFront;

  /// Пометка качества A8.1: во front нет вопроса.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос похож на заголовок'**
  String get generationIssueFrontLooksLikeHeading;

  /// Пометка качества A8.1: back длиннее ~200 символов или трёх предложений.
  ///
  /// In ru, this message translates to:
  /// **'Ответ слишком длинный для карточки'**
  String get generationIssueBackTooVerbose;

  /// Пометка качества A8.1: back — список обозначений без утверждения.
  ///
  /// In ru, this message translates to:
  /// **'Ответ только расшифровывает обозначения'**
  String get generationIssueBackOnlyNotation;

  /// Пометка качества A8.1: индексы/греческие буквы вне $…$.
  ///
  /// In ru, this message translates to:
  /// **'Индексы и греческие буквы вне формул'**
  String get generationIssueUnicodeMath;

  /// Пометка качества A8.1: Markdown-разметка в тексте карточки.
  ///
  /// In ru, this message translates to:
  /// **'В тексте есть разметка выделения'**
  String get generationIssueMarkdownInText;

  /// Сколько карточек отброшено поштучно из-за схемы/структуры (fix-gen).
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} карточка отброшена} few{{count} карточки отброшены} many{{count} карточек отброшено} other{{count} карточки отброшено}}'**
  String generationRejectedCards(int count);

  /// Кнопка предпросмотра: убрать выбранную картинку до импорта.
  ///
  /// In ru, this message translates to:
  /// **'Убрать картинку'**
  String get generationPreviewRemoveImage;

  /// Кнопка предпросмотра: заменить картинку своим файлом.
  ///
  /// In ru, this message translates to:
  /// **'Заменить картинку'**
  String get generationPreviewReplaceImage;

  /// Сообщение после замены картинки в предпросмотре.
  ///
  /// In ru, this message translates to:
  /// **'Картинка заменена'**
  String get generationPreviewImageReplaced;

  /// Ошибка замены картинки в предпросмотре.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать изображение. Нужен JPG или PNG'**
  String get generationPreviewImageReplaceError;

  /// Предпросмотр: невалидные карточки не блокируют импорт (fix-gen, Д6).
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} невалидная карточка пропущена} few{{count} невалидные карточки пропущены} many{{count} невалидных карточек пропущено} other{{count} невалидные карточки пропущены}}'**
  String generationPreviewInvalidSkipped(int count);

  /// Итог импорта, когда часть карточек не прошла валидацию (fix-gen, Д6).
  ///
  /// In ru, this message translates to:
  /// **'Импортировано карточек: {imported}, невалидных пропущено: {skipped}'**
  String generationImportedWithSkipped(int imported, int skipped);

  /// Ошибка фрагмента K из M с понятной причиной (SPEC A6.8, fix-gen).
  ///
  /// In ru, this message translates to:
  /// **'Фрагмент {index} из {total}: {message}'**
  String generationFailureChunkOf(int index, int total, String message);

  /// Причина падения фрагмента: truncated (fix-gen, Д6).
  ///
  /// In ru, this message translates to:
  /// **'ответ модели обрезан по лимиту токенов'**
  String get generationReasonTruncated;

  /// Причина падения фрагмента: refusal.
  ///
  /// In ru, this message translates to:
  /// **'модель отказалась отвечать'**
  String get generationReasonRefusal;

  /// Причина падения фрагмента: safety.
  ///
  /// In ru, this message translates to:
  /// **'ответ заблокирован фильтром безопасности'**
  String get generationReasonSafety;

  /// Причина падения фрагмента: json_parse.
  ///
  /// In ru, this message translates to:
  /// **'ответ модели не разобрался: некорректные обратные слэши в формулах'**
  String get generationReasonJsonParse;

  /// Причина падения фрагмента: schema_invalid.
  ///
  /// In ru, this message translates to:
  /// **'ответ модели не соответствует схеме карточки'**
  String get generationReasonSchemaInvalid;

  /// Причина падения фрагмента: validator_rejected.
  ///
  /// In ru, this message translates to:
  /// **'структура ответа модели непригодна'**
  String get generationReasonValidatorRejected;

  /// Причина падения фрагмента: network.
  ///
  /// In ru, this message translates to:
  /// **'нет сети или истекло время ожидания'**
  String get generationReasonNetwork;

  /// Причина падения фрагмента: http_4xx.
  ///
  /// In ru, this message translates to:
  /// **'провайдер отклонил запрос'**
  String get generationReasonHttpClientError;

  /// Причина падения фрагмента: http_5xx.
  ///
  /// In ru, this message translates to:
  /// **'ошибка на стороне провайдера'**
  String get generationReasonHttpServerError;

  /// Причина падения фрагмента: empty_response.
  ///
  /// In ru, this message translates to:
  /// **'модель вернула пустой ответ'**
  String get generationReasonEmptyResponse;

  /// Причина падения фрагмента: provider_response.
  ///
  /// In ru, this message translates to:
  /// **'провайдер вернул неожиданный ответ'**
  String get generationReasonProviderResponse;

  /// Причина падения фрагмента: cancelled.
  ///
  /// In ru, this message translates to:
  /// **'запрос отменён'**
  String get generationReasonCancelled;

  /// Причина падения фрагмента: unknown.
  ///
  /// In ru, this message translates to:
  /// **'неизвестная ошибка фрагмента'**
  String get generationReasonUnknown;

  /// Сколько дублей отсеяла дедупликация (SPEC A8.5 шаг 9).
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Дубликатов нет} one{{count} дубликат пропущен} few{{count} дубликата пропущено} many{{count} дубликатов пропущено} other{{count} дубликата пропущено}}'**
  String generationDuplicatesRemoved(int count);

  /// Фактический расход токенов после генерации (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Израсходовано токенов: {count}'**
  String generationTokensUsed(int count);

  /// Заголовок списка ошибок фрагментов при частичном успехе (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обработать фрагменты'**
  String get generationFailuresTitle;

  /// Ошибка одного фрагмента генерации.
  ///
  /// In ru, this message translates to:
  /// **'Фрагмент {index}: {message}'**
  String generationFailureChunk(int index, String message);

  /// Кнопка повтора только упавших фрагментов (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Повторить неудавшиеся'**
  String get generationRetryFailed;

  /// Ошибка импорта карточек (без сырых исключений).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось импортировать карточки. Попробуйте ещё раз'**
  String get generationImportError;

  /// Сообщение после импорта сгенерированных карточек.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Карточки не импортированы} one{Импортирована {count} карточка} few{Импортировано {count} карточки} many{Импортировано {count} карточек} other{Импортировано {count} карточки}}'**
  String generationImported(int count);

  /// Ошибка ручной формы: у cloze нет корректного пропуска A7.9.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте хотя бы один пропуск'**
  String get cardFormClozeMissingError;

  /// Заголовок редактора Image Occlusion в форме карточки.
  ///
  /// In ru, this message translates to:
  /// **'Изображение и маски'**
  String get cardFormOcclusionSection;

  /// Заголовок секции изображения карточки любого типа (ADR-028, итерация 7.12).
  ///
  /// In ru, this message translates to:
  /// **'Изображение'**
  String get cardFormImageSection;

  /// Пояснение: изображение не требует масок.
  ///
  /// In ru, this message translates to:
  /// **'Картинка показывается вместе с вопросом и ответом. Маски нужны, только если части изображения надо скрыть.'**
  String get cardFormImageHint;

  /// Кнопка удаления изображения из карточки.
  ///
  /// In ru, this message translates to:
  /// **'Удалить изображение'**
  String get cardFormRemoveImage;

  /// Переключатель масок в форме карточки (ADR-028).
  ///
  /// In ru, this message translates to:
  /// **'Маски изображения'**
  String get cardFormOcclusionToggle;

  /// Пояснение к переключателю масок.
  ///
  /// In ru, this message translates to:
  /// **'Необязательно. Скрывает части изображения на карточке.'**
  String get cardFormOcclusionToggleHint;

  /// Кнопка системного выбора изображения карточки.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать изображение'**
  String get cardFormPickImage;

  /// Кнопка замены изображения карточки.
  ///
  /// In ru, this message translates to:
  /// **'Заменить изображение'**
  String get cardFormChangeImage;

  /// Ошибка picker/чтения изображения без сырого исключения.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить изображение. Выберите другое изображение до 25 МБ.'**
  String get cardFormImageLoadError;

  /// Ошибка occlusion без изображения.
  ///
  /// In ru, this message translates to:
  /// **'Выберите изображение для масок'**
  String get cardFormOcclusionImageMissingError;

  /// Ошибка occlusion с пустым списком масок.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте хотя бы одну маску'**
  String get cardFormOcclusionMasksMissingError;

  /// Ошибка повреждённой разметки occlusion.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте изображение и координаты масок'**
  String get cardFormOcclusionInvalidError;

  /// Форма прямоугольной маски.
  ///
  /// In ru, this message translates to:
  /// **'Прямоугольник'**
  String get occlusionRectangle;

  /// Форма эллиптической маски.
  ///
  /// In ru, this message translates to:
  /// **'Эллипс'**
  String get occlusionEllipse;

  /// Кнопка удаления маски в редакторе.
  ///
  /// In ru, this message translates to:
  /// **'Удалить маску'**
  String get occlusionDeleteMaskTooltip;

  /// Раскрыть все маски изображения.
  ///
  /// In ru, this message translates to:
  /// **'Показать все'**
  String get occlusionShowAll;

  /// Скрыть содержимое всех масок изображения.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть все'**
  String get occlusionHideAll;

  /// Запасное сообщение вместо отсутствующего изображения.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить изображение'**
  String get occlusionImageUnavailable;

  /// Запасное сообщение для повреждённого occlusion_json.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка разметки масок'**
  String get occlusionInvalid;

  /// Раскрыть следующую формулу в пошаговом выводе.
  ///
  /// In ru, this message translates to:
  /// **'Следующий шаг'**
  String get latexNextStep;

  /// Замена скрытого пропуска cloze или следующего шага формулы.
  ///
  /// In ru, this message translates to:
  /// **'…'**
  String get clozeHiddenAnswer;

  /// Подсказка редактора масок Image Occlusion.
  ///
  /// In ru, this message translates to:
  /// **'Проведите по изображению, чтобы добавить маску'**
  String get occlusionDrawHint;

  /// Номер маски в списке редактора.
  ///
  /// In ru, this message translates to:
  /// **'Маска {number}'**
  String occlusionMaskNumber(int number);

  /// Заголовок экрана конструктора сессии (SPEC A6.7).
  ///
  /// In ru, this message translates to:
  /// **'Конструктор сессии'**
  String get constructorTitle;

  /// Пункт листа режимов на экране колоды (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Конструктор'**
  String get constructorAction;

  /// Заголовок блока выбора колод.
  ///
  /// In ru, this message translates to:
  /// **'Колоды'**
  String get constructorDecksSection;

  /// Заголовок блока фильтра по тегам.
  ///
  /// In ru, this message translates to:
  /// **'Теги'**
  String get constructorTagsSection;

  /// Подсказка, если у карточек выбранных колод нет тегов.
  ///
  /// In ru, this message translates to:
  /// **'У выбранных колод нет тегов'**
  String get constructorTagsEmpty;

  /// Подсказка при пустом выборе колод.
  ///
  /// In ru, this message translates to:
  /// **'Выберите колоды, чтобы собрать сессию'**
  String get constructorSelectDecksHint;

  /// Заголовок блока фильтра по типу карточки.
  ///
  /// In ru, this message translates to:
  /// **'Тип карточки'**
  String get constructorTypesSection;

  /// Заголовок блока фильтра по состоянию карточки.
  ///
  /// In ru, this message translates to:
  /// **'Состояние'**
  String get constructorStatesSection;

  /// Фильтр состояния: новые карточки.
  ///
  /// In ru, this message translates to:
  /// **'Новые'**
  String get constructorStateNew;

  /// Фильтр состояния: изучаемые и переизучаемые.
  ///
  /// In ru, this message translates to:
  /// **'В процессе'**
  String get constructorStateInProgress;

  /// Фильтр состояния: в повторении.
  ///
  /// In ru, this message translates to:
  /// **'Повторение'**
  String get constructorStateReview;

  /// Фильтр состояния: 8+ провалов (SPEC A7.17).
  ///
  /// In ru, this message translates to:
  /// **'Пиявки'**
  String get constructorStateLeeches;

  /// Заголовок блока выбора режима сессии.
  ///
  /// In ru, this message translates to:
  /// **'Режим'**
  String get constructorModeSection;

  /// Заголовок блока лимита сессии.
  ///
  /// In ru, this message translates to:
  /// **'Лимит'**
  String get constructorLimitSection;

  /// Лимит по числу карточек.
  ///
  /// In ru, this message translates to:
  /// **'Карточки'**
  String get constructorLimitCards;

  /// Лимит по времени сессии.
  ///
  /// In ru, this message translates to:
  /// **'Минуты'**
  String get constructorLimitMinutes;

  /// Значение лимита по карточкам.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} карточка} few{{count} карточки} many{{count} карточек} other{{count} карточки}}'**
  String constructorLimitCardsValue(int count);

  /// Значение лимита по минутам.
  ///
  /// In ru, this message translates to:
  /// **'{count} мин'**
  String constructorLimitMinutesValue(int count);

  /// Заголовок блока порядка карточек.
  ///
  /// In ru, this message translates to:
  /// **'Порядок'**
  String get constructorOrderSection;

  /// Переключатель случайного порядка карточек.
  ///
  /// In ru, this message translates to:
  /// **'Перемешать'**
  String get constructorShuffle;

  /// Подпись переключателя перемешивания.
  ///
  /// In ru, this message translates to:
  /// **'Случайный порядок карточек'**
  String get constructorShuffleHint;

  /// Переключатель подмешивания карточек из разных колод.
  ///
  /// In ru, this message translates to:
  /// **'Интерливинг'**
  String get constructorInterleave;

  /// Подпись переключателя интерливинга (SPEC A7.19).
  ///
  /// In ru, this message translates to:
  /// **'Подмешивать карточки из разных колод'**
  String get constructorInterleaveHint;

  /// Переключатель разминки (SPEC A7.19).
  ///
  /// In ru, this message translates to:
  /// **'Разминка'**
  String get constructorWarmup;

  /// Подпись переключателя разминки.
  ///
  /// In ru, this message translates to:
  /// **'Первые карточки — самые лёгкие'**
  String get constructorWarmupHint;

  /// Заголовок блока сохранённых пресетов.
  ///
  /// In ru, this message translates to:
  /// **'Пресеты'**
  String get constructorPresetsSection;

  /// Пустое состояние списка пресетов.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённых пресетов нет'**
  String get constructorPresetsEmpty;

  /// Кнопка сохранения текущих параметров как пресета.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить пресет'**
  String get constructorSavePreset;

  /// Заголовок диалога сохранения пресета.
  ///
  /// In ru, this message translates to:
  /// **'Название пресета'**
  String get constructorPresetDialogTitle;

  /// Подпись поля имени пресета.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get constructorPresetNameLabel;

  /// Ошибка пустого имени пресета.
  ///
  /// In ru, this message translates to:
  /// **'Введите название пресета'**
  String get constructorPresetNameEmpty;

  /// Сообщение после сохранения пресета.
  ///
  /// In ru, this message translates to:
  /// **'Пресет сохранён'**
  String get constructorPresetSaved;

  /// Сообщение после удаления пресета.
  ///
  /// In ru, this message translates to:
  /// **'Пресет удалён'**
  String get constructorPresetDeleted;

  /// Подсказка кнопки удаления пресета.
  ///
  /// In ru, this message translates to:
  /// **'Удалить пресет'**
  String get constructorPresetDeleteTooltip;

  /// Счётчик доступных карточек по текущим фильтрам.
  ///
  /// In ru, this message translates to:
  /// **'Доступно карточек: {count}'**
  String constructorAvailableCount(int count);

  /// Пустое состояние конструктора без колод.
  ///
  /// In ru, this message translates to:
  /// **'Нет активных колод. Создайте колоду, чтобы собрать сессию.'**
  String get constructorEmptyDecks;

  /// Ошибка загрузки данных конструктора.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить колоды'**
  String get constructorLoadError;

  /// Подпись ленты для сессии из нескольких колод.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} колода} few{{count} колоды} many{{count} колод} other{{count} колоды}}'**
  String sessionDeckCountLabel(int count);

  /// Заголовок завершения сессии по лимиту минут (SPEC A6.7).
  ///
  /// In ru, this message translates to:
  /// **'Время сессии истекло'**
  String get reviewTimeUpTitle;

  /// Итог сессии, завершённой по лимиту времени.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Ни одной карточки} one{Повторена {count} карточка} few{Повторено {count} карточки} many{Повторено {count} карточек} other{Повторено {count} карточки}}'**
  String reviewTimeUpMessage(int count);

  /// Состояние сессии без переданного плана конструктора.
  ///
  /// In ru, this message translates to:
  /// **'Сессия не найдена'**
  String get reviewPlanMissingTitle;

  /// Пояснение к состоянию «сессия не найдена».
  ///
  /// In ru, this message translates to:
  /// **'Откройте конструктор и соберите сессию заново.'**
  String get reviewPlanMissingMessage;

  /// Пункт оболочки: список колод (SPEC A6.1).
  ///
  /// In ru, this message translates to:
  /// **'Колоды'**
  String get navDecks;

  /// Пункт оболочки: статистика (SPEC A6.1).
  ///
  /// In ru, this message translates to:
  /// **'Статистика'**
  String get navStatistics;

  /// Пункт оболочки: настройки (SPEC A6.1).
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get navSettings;

  /// Заголовок экрана статистики (SPEC A6.5).
  ///
  /// In ru, this message translates to:
  /// **'Статистика'**
  String get statisticsTitle;

  /// Заголовок блока удержания.
  ///
  /// In ru, this message translates to:
  /// **'Удержание за 30 дней'**
  String get statisticsRetentionTitle;

  /// Процент удержания.
  ///
  /// In ru, this message translates to:
  /// **'{percent}%'**
  String statisticsRetentionValue(int percent);

  /// Удержание без данных за окно.
  ///
  /// In ru, this message translates to:
  /// **'Нет повторений за 30 дней'**
  String get statisticsRetentionNoData;

  /// Заголовок годовой тепловой карты.
  ///
  /// In ru, this message translates to:
  /// **'Календарь повторений'**
  String get statisticsHeatmapTitle;

  /// Семантика годовой карты повторений.
  ///
  /// In ru, this message translates to:
  /// **'Повторений за год: {count}'**
  String statisticsChartSemantics(int count);

  /// Заголовок недельного прогресса.
  ///
  /// In ru, this message translates to:
  /// **'Недельный прогресс'**
  String get statisticsWeekTitle;

  /// Семантика недельного прогресса.
  ///
  /// In ru, this message translates to:
  /// **'Повторений за неделю: {count}'**
  String statisticsWeekSemantics(int count);

  /// Заголовок списка слабых тем.
  ///
  /// In ru, this message translates to:
  /// **'Слабые темы'**
  String get statisticsWeakTopicsTitle;

  /// Слабых тем не набралось по порогам.
  ///
  /// In ru, this message translates to:
  /// **'Слабых тем пока нет'**
  String get statisticsWeakTopicsEmpty;

  /// Статистика по слабому тегу.
  ///
  /// In ru, this message translates to:
  /// **'{errors} из {reviews} с ошибкой'**
  String statisticsWeakTopicStats(int errors, int reviews);

  /// Кнопка перехода в конструктор с фильтром тега.
  ///
  /// In ru, this message translates to:
  /// **'Тренировать'**
  String get statisticsWeakTopicTrain;

  /// Заголовок прогноза.
  ///
  /// In ru, this message translates to:
  /// **'Прогноз нагрузки на 7 дней'**
  String get statisticsForecastTitle;

  /// Подпись первого дня прогноза.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня'**
  String get statisticsForecastToday;

  /// Подпись второго дня прогноза.
  ///
  /// In ru, this message translates to:
  /// **'Завтра'**
  String get statisticsForecastTomorrow;

  /// Сколько карточек к повторению в день прогноза.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =0{Нет карточек} one{{count} карточка} few{{count} карточки} many{{count} карточек} other{{count} карточки}}'**
  String statisticsForecastCount(int count);

  /// Семантика столбца прогноза.
  ///
  /// In ru, this message translates to:
  /// **'{day}: {count}'**
  String statisticsForecastSemantics(String day, int count);

  /// Ошибка загрузки статистики.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить статистику'**
  String get statisticsErrorTitle;

  /// Пустое состояние статистики.
  ///
  /// In ru, this message translates to:
  /// **'Статистика появится после первых повторений'**
  String get statisticsEmptyTitle;

  /// Пояснение к пустому состоянию статистики.
  ///
  /// In ru, this message translates to:
  /// **'Повторите карточки — здесь появятся удержание, календарь, слабые темы и прогноз.'**
  String get statisticsEmptyMessage;

  /// Заголовок экрана настроек (SPEC A6.6).
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsScreenTitle;

  /// Блок внешнего вида.
  ///
  /// In ru, this message translates to:
  /// **'Внешний вид'**
  String get settingsAppearanceTitle;

  /// Подпись выбора темы.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get settingsThemeTitle;

  /// Светлая тема.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get settingsThemeLight;

  /// Тёмная тема.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get settingsThemeDark;

  /// Системная тема.
  ///
  /// In ru, this message translates to:
  /// **'Системная'**
  String get settingsThemeSystem;

  /// Переключатель dynamic color.
  ///
  /// In ru, this message translates to:
  /// **'Динамические цвета'**
  String get settingsDynamicColor;

  /// Пояснение dynamic color.
  ///
  /// In ru, this message translates to:
  /// **'Цвета системы, если платформа их поддерживает'**
  String get settingsDynamicColorHint;

  /// Подпись выбора профиля анимации.
  ///
  /// In ru, this message translates to:
  /// **'Анимация'**
  String get settingsMotionTitle;

  /// Выразительная анимация.
  ///
  /// In ru, this message translates to:
  /// **'Выразительная'**
  String get settingsMotionExpressive;

  /// Стандартная анимация.
  ///
  /// In ru, this message translates to:
  /// **'Стандартная'**
  String get settingsMotionStandard;

  /// Переключатель шрифта OpenDyslexic.
  ///
  /// In ru, this message translates to:
  /// **'Шрифт для дислексии'**
  String get settingsDyslexiaFont;

  /// Ползунок размера шрифта.
  ///
  /// In ru, this message translates to:
  /// **'Размер шрифта'**
  String get settingsTextScaleTitle;

  /// Размер шрифта в процентах.
  ///
  /// In ru, this message translates to:
  /// **'{percent}%'**
  String settingsTextScaleValue(int percent);

  /// Переключатель контраста.
  ///
  /// In ru, this message translates to:
  /// **'Повышенный контраст'**
  String get settingsHighContrast;

  /// Блок обучения.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get settingsLearningTitle;

  /// Ползунок desiredRetention.
  ///
  /// In ru, this message translates to:
  /// **'Желаемое удержание'**
  String get settingsRetentionTitle;

  /// Желаемое удержание в процентах.
  ///
  /// In ru, this message translates to:
  /// **'{percent}%'**
  String settingsRetentionValue(int percent);

  /// Список шагов обучения.
  ///
  /// In ru, this message translates to:
  /// **'Шаги обучения'**
  String get settingsLearningStepsTitle;

  /// Длительность шага обучения.
  ///
  /// In ru, this message translates to:
  /// **'{minutes} мин'**
  String settingsLearningStepValue(int minutes);

  /// Кнопка добавления шага обучения.
  ///
  /// In ru, this message translates to:
  /// **'Добавить шаг'**
  String get settingsLearningStepAdd;

  /// Подсказка удаления шага обучения.
  ///
  /// In ru, this message translates to:
  /// **'Удалить шаг'**
  String get settingsLearningStepDeleteTooltip;

  /// Заголовок диалога шага обучения.
  ///
  /// In ru, this message translates to:
  /// **'Новый шаг обучения'**
  String get settingsLearningStepDialogTitle;

  /// Поле длительности шага.
  ///
  /// In ru, this message translates to:
  /// **'Длительность, мин'**
  String get settingsLearningStepDialogLabel;

  /// Ошибка длительности шага.
  ///
  /// In ru, this message translates to:
  /// **'Введите число от 1 до 60'**
  String get settingsLearningStepInvalid;

  /// Ошибка превышения числа шагов.
  ///
  /// In ru, this message translates to:
  /// **'Не больше 5 шагов'**
  String get settingsLearningStepLimit;

  /// Дневной лимит новых карточек.
  ///
  /// In ru, this message translates to:
  /// **'Новых в день'**
  String get settingsDailyNewLimitTitle;

  /// Дневной лимит повторных карточек.
  ///
  /// In ru, this message translates to:
  /// **'Повторных в день'**
  String get settingsDailyReviewLimitTitle;

  /// Пояснение нулевого дневного лимита.
  ///
  /// In ru, this message translates to:
  /// **'0 — без ограничения'**
  String get settingsDailyLimitZeroHint;

  /// Блок доступности.
  ///
  /// In ru, this message translates to:
  /// **'Доступность'**
  String get settingsAccessibilityTitle;

  /// Переключатель haptics.
  ///
  /// In ru, this message translates to:
  /// **'Тактильная отдача'**
  String get settingsHapticsTitle;

  /// Пояснение haptics.
  ///
  /// In ru, this message translates to:
  /// **'Вибрация при оценке карточек'**
  String get settingsHapticsHint;

  /// Блок API (SPEC A6.6).
  ///
  /// In ru, this message translates to:
  /// **'API'**
  String get settingsApiTitle;

  /// Заголовок списка провайдеров.
  ///
  /// In ru, this message translates to:
  /// **'Провайдеры'**
  String get settingsApiProvidersTitle;

  /// Проверка без сохранённого ключа.
  ///
  /// In ru, this message translates to:
  /// **'Сначала добавьте ключ'**
  String get settingsApiCheckMissing;

  /// Проверка ключа без сети.
  ///
  /// In ru, this message translates to:
  /// **'Нет подключения к интернету'**
  String get settingsApiCheckNoConnection;

  /// Проверка ключа при 429.
  ///
  /// In ru, this message translates to:
  /// **'Превышен лимит запросов. Попробуйте позже'**
  String get settingsApiCheckRateLimited;

  /// Проверка ключа без адреса/модели OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не настроен. Укажите адрес и модель'**
  String get settingsApiCheckNotConfigured;

  /// Прочие ошибки проверки ключа.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить ключ. Попробуйте ещё раз'**
  String get settingsApiCheckUnexpected;

  /// Расход токенов за неделю.
  ///
  /// In ru, this message translates to:
  /// **'Токенов за неделю: {count}'**
  String settingsApiTokensWeek(int count);

  /// Переход к экрану провайдеров (ADR-020).
  ///
  /// In ru, this message translates to:
  /// **'Провайдеры и ключи'**
  String get settingsApiOpenGeneration;

  /// Заголовок экрана настройки провайдеров (ADR-020).
  ///
  /// In ru, this message translates to:
  /// **'Провайдеры'**
  String get providersTitle;

  /// Пояснение на экране провайдеров.
  ///
  /// In ru, this message translates to:
  /// **'Ключи хранятся в защищённом хранилище устройства и не показываются. Генерация использует основного провайдера'**
  String get providersDescription;

  /// Пустой список провайдеров.
  ///
  /// In ru, this message translates to:
  /// **'Провайдеры не настроены'**
  String get providersEmptyTitle;

  /// Пустой список провайдеров: подсказка.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте провайдера, чтобы генерировать карточки'**
  String get providersEmptyDescription;

  /// Кнопка добавления провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Добавить провайдера'**
  String get providersAdd;

  /// Первый путь добавления: каталог.
  ///
  /// In ru, this message translates to:
  /// **'Сторонний поставщик'**
  String get providersAddPreset;

  /// Подпись первого пути добавления.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать из каталога'**
  String get providersAddPresetSubtitle;

  /// Второй путь добавления и подпись безымянного пользовательского аккаунта.
  ///
  /// In ru, this message translates to:
  /// **'Пользовательская модель API'**
  String get providersAddCustom;

  /// Подпись второго пути добавления.
  ///
  /// In ru, this message translates to:
  /// **'Свой адрес, протокол и имя модели'**
  String get providersAddCustomSubtitle;

  /// Заголовок диалога изменения.
  ///
  /// In ru, this message translates to:
  /// **'Изменить провайдера'**
  String get providersEditTitle;

  /// Поле выбора пресета в диалоге.
  ///
  /// In ru, this message translates to:
  /// **'Поставщик'**
  String get providersPresetLabel;

  /// Поле выбора протокола в диалоге.
  ///
  /// In ru, this message translates to:
  /// **'Протокол'**
  String get providersProtocolLabel;

  /// Поле названия пользовательского провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get providersNameLabel;

  /// Ошибка пустого названия.
  ///
  /// In ru, this message translates to:
  /// **'Укажите название'**
  String get providersNameEmptyError;

  /// Подсказка поля модели.
  ///
  /// In ru, this message translates to:
  /// **'Имя модели на сервере'**
  String get providersModelHint;

  /// Переключатель Vision пользовательской модели (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Модель принимает изображения'**
  String get providersVisionLabel;

  /// Пояснение к переключателю Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Включайте, если модель понимает картинки и сканы'**
  String get providersVisionHint;

  /// Подпись модели/аккаунта с поддержкой Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Принимает изображения'**
  String get providersVisionSupported;

  /// Подпись модели/аккаунта без Vision (итерация 7.8).
  ///
  /// In ru, this message translates to:
  /// **'Только текст'**
  String get providersVisionNotSupported;

  /// Подсказка поля адреса.
  ///
  /// In ru, this message translates to:
  /// **'Полный адрес; версию укажите в пути, если сервер её требует'**
  String get providersBaseUrlHint;

  /// Неполный аккаунт (нет адреса/модели).
  ///
  /// In ru, this message translates to:
  /// **'Заполните адрес и модель, чтобы пользоваться провайдером'**
  String get providersIncompleteHint;

  /// Статус ключа локального провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Ключ не требуется'**
  String get providersKeyNotRequired;

  /// Подсказка поля ключа.
  ///
  /// In ru, this message translates to:
  /// **'Ключ хранится в защищённом хранилище и не показывается'**
  String get providersKeyHelper;

  /// Подсказка при изменении аккаунта.
  ///
  /// In ru, this message translates to:
  /// **'Оставьте пустым, чтобы не менять сохранённый ключ'**
  String get providersKeyKeep;

  /// Подсказка для пользовательского провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Можно не заполнять: провайдер работает без ключа'**
  String get providersKeyOptionalHint;

  /// Отмена удаления ключа в диалоге.
  ///
  /// In ru, this message translates to:
  /// **'Оставить сохранённый ключ'**
  String get providersKeyUndoDelete;

  /// Основной провайдер выбран.
  ///
  /// In ru, this message translates to:
  /// **'Основной провайдер: {name}'**
  String providersActiveSaved(String name);

  /// Отметка основного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Основной'**
  String get providersActive;

  /// Кнопка выбора основного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Сделать основным'**
  String get providersMakeActive;

  /// Кнопка проверки подключения.
  ///
  /// In ru, this message translates to:
  /// **'Проверить подключение'**
  String get providersCheck;

  /// Успешная проверка подключения.
  ///
  /// In ru, this message translates to:
  /// **'Подключение работает'**
  String get providersCheckValid;

  /// Неверный ключ при проверке подключения.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка ключа. Проверьте ключ доступа'**
  String get providersCheckInvalid;

  /// Кнопка изменения провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get providersEdit;

  /// Кнопка удаления провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get providersDelete;

  /// Заголовок подтверждения удаления.
  ///
  /// In ru, this message translates to:
  /// **'Удалить провайдера?'**
  String get providersDeleteTitle;

  /// Текст подтверждения удаления.
  ///
  /// In ru, this message translates to:
  /// **'Настройки провайдера и сохранённый ключ будут удалены'**
  String get providersDeleteBody;

  /// Провайдер удалён.
  ///
  /// In ru, this message translates to:
  /// **'Провайдер удалён'**
  String get providersDeleted;

  /// Провайдер сохранён.
  ///
  /// In ru, this message translates to:
  /// **'Провайдер сохранён'**
  String get providersSaved;

  /// Ошибка сохранения провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить провайдера. Попробуйте ещё раз'**
  String get providersSaveError;

  /// Ключ не подтверждён после записи.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить ключ в защищённом хранилище. Попробуйте ещё раз'**
  String get providersKeyStoreError;

  /// Подпись протокола Chat Completions.
  ///
  /// In ru, this message translates to:
  /// **'OpenAI-совместимый'**
  String get providersProtocolOpenAi;

  /// Подпись протокола Messages.
  ///
  /// In ru, this message translates to:
  /// **'Anthropic (сообщения)'**
  String get providersProtocolAnthropic;

  /// Подпись протокола Gemini.
  ///
  /// In ru, this message translates to:
  /// **'Gemini'**
  String get providersProtocolGemini;

  /// Подсказка модели на экране генерации.
  ///
  /// In ru, this message translates to:
  /// **'Модель задаётся в настройках провайдера'**
  String get generationModelProviderHint;

  /// Блок «О приложении».
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get settingsAboutTitle;

  /// Версия приложения.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String settingsAboutVersion(String version);

  /// Пункт лицензий.
  ///
  /// In ru, this message translates to:
  /// **'Лицензии'**
  String get settingsAboutLicenses;

  /// Пункт политики приватности.
  ///
  /// In ru, this message translates to:
  /// **'Политика приватности'**
  String get settingsAboutPrivacy;

  /// Ошибка открытия внешней ссылки.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть ссылку'**
  String get settingsAboutLinkError;

  /// Подпись изображения карточки для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Изображение карточки'**
  String get cardImageSemantics;

  /// Подпись заглушки изображения карточки для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Временная картинка карточки'**
  String get cardImagePlaceholderSemantics;

  /// Заголовок полноэкранного просмотра картинки.
  ///
  /// In ru, this message translates to:
  /// **'Изображение'**
  String get cardImageFullscreenTitle;

  /// Кнопка закрытия полноэкранного просмотра картинки.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get cardImageFullscreenClose;

  /// Атрибуция изображения: автор и лицензия.
  ///
  /// In ru, this message translates to:
  /// **'Источник: {attribution}'**
  String cardImageAttribution(String attribution);

  /// Ссылка на источник изображения.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка: {url}'**
  String cardImageSourceUrl(String url);

  /// Действие повторного поиска картинки для карточки.
  ///
  /// In ru, this message translates to:
  /// **'Найти картинку заново'**
  String get cardImageRetryAction;

  /// Повторный поиск картинки удался.
  ///
  /// In ru, this message translates to:
  /// **'Картинка обновлена'**
  String get cardImageRetrySuccess;

  /// Повторный поиск картинки не дал результата.
  ///
  /// In ru, this message translates to:
  /// **'Картинку не нашли — осталась прежняя'**
  String get cardImageRetryNotFound;

  /// Повторный поиск невозможен: запрос модели не сохранён.
  ///
  /// In ru, this message translates to:
  /// **'Нет сохранённого запроса для поиска'**
  String get cardImageRetryNoQuery;

  /// Ошибка повторного поиска картинки.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить картинку'**
  String get cardImageRetryError;

  /// Заголовок списка карточек, появляющихся во время генерации.
  ///
  /// In ru, this message translates to:
  /// **'Карточки готовы: {count}'**
  String generationLiveCardsTitle(int count);

  /// Поиск картинок продолжается во время генерации.
  ///
  /// In ru, this message translates to:
  /// **'Догружаем картинки…'**
  String get generationLiveImagesPending;

  /// Режим «Тест» с четырьмя вариантами ответа.
  ///
  /// In ru, this message translates to:
  /// **'Тест'**
  String get reviewModeTest;

  /// Режим «Ввод ответа».
  ///
  /// In ru, this message translates to:
  /// **'Ввод ответа'**
  String get reviewModeTyping;

  /// Подпись режима Тест в листе режимов.
  ///
  /// In ru, this message translates to:
  /// **'Четыре варианта ответа'**
  String get studyModeTestSubtitle;

  /// Подпись режима Ввод ответа в листе режимов.
  ///
  /// In ru, this message translates to:
  /// **'Вспомни и введи ответ'**
  String get studyModeTypingSubtitle;

  /// Сколько карточек подходит для режима.
  ///
  /// In ru, this message translates to:
  /// **'Доступно карточек: {count}'**
  String studyModeAvailableCount(int count);

  /// Режим недоступен: недостаточно подходящих карточек.
  ///
  /// In ru, this message translates to:
  /// **'Мало подходящих карточек'**
  String get studyModeNotEnough;

  /// Подпись прогресса Теста для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос {current} из {total}'**
  String testProgressSemantics(int current, int total);

  /// Кнопка перехода к следующему вопросу.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get testNext;

  /// Заголовок итогов Теста.
  ///
  /// In ru, this message translates to:
  /// **'Тест завершён'**
  String get testResultsTitle;

  /// Точность ответов в Тесте.
  ///
  /// In ru, this message translates to:
  /// **'Точность: {percent}%'**
  String testAccuracy(int percent);

  /// Сколько ошибок в Тесте.
  ///
  /// In ru, this message translates to:
  /// **'Ошибок: {count}'**
  String testErrorsCount(int count);

  /// Кнопка повтора только ошибочных карточек.
  ///
  /// In ru, this message translates to:
  /// **'Повторить ошибки'**
  String get testRepeatMistakes;

  /// Пустое состояние Теста.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек для теста'**
  String get testEmptyTitle;

  /// Пояснение пустого состояния Теста.
  ///
  /// In ru, this message translates to:
  /// **'Для теста нужны карточки с коротким ответом и хотя бы четырьмя подходящими вариантами в колоде.'**
  String get testEmptyMessage;

  /// Подпись варианта ответа для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Вариант {index}: {answer}'**
  String testOptionLabel(int index, String answer);

  /// Подпись вопроса в Тесте для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос'**
  String get testQuestionLabel;

  /// Заголовок режима Ввод ответа.
  ///
  /// In ru, this message translates to:
  /// **'Ввод ответа'**
  String get typingTitle;

  /// Подпись поля ввода ответа.
  ///
  /// In ru, this message translates to:
  /// **'Введите ответ'**
  String get typingInputLabel;

  /// Кнопка проверки введённого ответа.
  ///
  /// In ru, this message translates to:
  /// **'Проверить'**
  String get typingCheck;

  /// Введённый ответ верный.
  ///
  /// In ru, this message translates to:
  /// **'Верно'**
  String get typingCorrect;

  /// Ответ с опечаткой.
  ///
  /// In ru, this message translates to:
  /// **'Почти! Проверь написание'**
  String get typingAlmost;

  /// Введённый ответ неверный.
  ///
  /// In ru, this message translates to:
  /// **'Неверно'**
  String get typingWrong;

  /// Показ правильного ответа после ошибки.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ: {answer}'**
  String typingRightAnswer(String answer);

  /// Кнопка «Я был прав» после неверного ответа или опечатки.
  ///
  /// In ru, this message translates to:
  /// **'Я был прав'**
  String get typingIWasRight;

  /// Сдаться и показать правильный ответ.
  ///
  /// In ru, this message translates to:
  /// **'Показать ответ'**
  String get typingShowAnswer;

  /// Переход к следующей карточке после проверки.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get typingNext;

  /// Подпись поля ввода для screen reader.
  ///
  /// In ru, this message translates to:
  /// **'Поле ввода ответа'**
  String get typingInputSemantics;

  /// Пустое состояние режима Ввод ответа.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек для ввода ответа'**
  String get typingEmptyTitle;

  /// Пояснение пустого состояния режима Ввод ответа.
  ///
  /// In ru, this message translates to:
  /// **'Нужны карточки с коротким ответом (до 60 символов, без формул и переносов строк).'**
  String get typingEmptyMessage;

  /// Итог: сколько ответов верно.
  ///
  /// In ru, this message translates to:
  /// **'Верно: {correct} из {total}'**
  String studyResultsScore(int total, int correct);

  /// Заголовок списка ошибочных карточек.
  ///
  /// In ru, this message translates to:
  /// **'Ошибки'**
  String get studyWrongListTitle;

  /// Режим «Подбор пар» (7.16).
  ///
  /// In ru, this message translates to:
  /// **'Подбор пар'**
  String get reviewModeMatch;

  /// Режим «Верно/Неверно» (7.16).
  ///
  /// In ru, this message translates to:
  /// **'Верно/Неверно'**
  String get reviewModeTrueFalse;

  /// Подпись режима Подбор пар.
  ///
  /// In ru, this message translates to:
  /// **'Найди пары вопрос-ответ'**
  String get studyModeMatchSubtitle;

  /// Подпись режима Верно/Неверно.
  ///
  /// In ru, this message translates to:
  /// **'Ответ верный или нет?'**
  String get studyModeTrueFalseSubtitle;

  /// Режим Подбор пар недоступен.
  ///
  /// In ru, this message translates to:
  /// **'Нужно минимум 6 карточек с вопросом и ответом'**
  String get studyModeMatchNotEnough;

  /// Режим Верно/Неверно недоступен.
  ///
  /// In ru, this message translates to:
  /// **'Нужен хотя бы один другой ответ в колоде'**
  String get studyModeTrueFalseNotEnough;

  /// Заголовок игры.
  ///
  /// In ru, this message translates to:
  /// **'Подбор пар'**
  String get matchTitle;

  /// Таймер игры, время строкой.
  ///
  /// In ru, this message translates to:
  /// **'Время: {time}'**
  String matchTimer(String time);

  /// Лучший результат по колоде.
  ///
  /// In ru, this message translates to:
  /// **'Лучшее время: {time}'**
  String matchBest(String time);

  /// Число ходов в игре.
  ///
  /// In ru, this message translates to:
  /// **'Ходов: {count}'**
  String matchMoves(int count);

  /// Заголовок итога игры.
  ///
  /// In ru, this message translates to:
  /// **'Все пары найдены'**
  String get matchCompletedTitle;

  /// Кнопка новой игры.
  ///
  /// In ru, this message translates to:
  /// **'Ещё раз'**
  String get matchRestart;

  /// Кнопка выхода после игры.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get matchDone;

  /// Пустое состояние игры.
  ///
  /// In ru, this message translates to:
  /// **'Мало карточек для пар'**
  String get matchEmptyTitle;

  /// Пояснение пустого состояния.
  ///
  /// In ru, this message translates to:
  /// **'Нужно минимум 6 карточек с непустым вопросом и ответом.'**
  String get matchEmptyMessage;

  /// Заголовок режима.
  ///
  /// In ru, this message translates to:
  /// **'Верно/Неверно'**
  String get trueFalseTitle;

  /// Показанное утверждение.
  ///
  /// In ru, this message translates to:
  /// **'Ответ: {answer}'**
  String trueFalseStatement(String answer);

  /// Кнопка «верно».
  ///
  /// In ru, this message translates to:
  /// **'Верно'**
  String get trueFalseTrueAction;

  /// Кнопка «неверно».
  ///
  /// In ru, this message translates to:
  /// **'Неверно'**
  String get trueFalseFalseAction;

  /// Ответ игрока правильный.
  ///
  /// In ru, this message translates to:
  /// **'Верно!'**
  String get trueFalseCorrect;

  /// Ответ игрока неправильный.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get trueFalseWrong;

  /// Показ правильного ответа после ошибки.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ: {answer}'**
  String trueFalseExplanation(String answer);

  /// Подсказка жестов.
  ///
  /// In ru, this message translates to:
  /// **'Свайп вправо — верно, влево — неверно'**
  String get trueFalseSwipeHint;

  /// Переход к следующему утверждению.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get trueFalseNext;

  /// Пустое состояние режима.
  ///
  /// In ru, this message translates to:
  /// **'Нет карточек для режима'**
  String get trueFalseEmptyTitle;

  /// Пояснение пустого состояния.
  ///
  /// In ru, this message translates to:
  /// **'Нужны карточки с ответом и хотя бы один другой ответ в колоде.'**
  String get trueFalseEmptyMessage;

  /// Семантика ожидания: спиннер, скелетон, проверка ключа.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка'**
  String get commonLoading;

  /// Закрыть лист, диалог, меню, полноэкранный просмотр.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get commonClose;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
