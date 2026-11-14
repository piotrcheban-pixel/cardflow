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

  /// Заголовок bottom sheet выбора режима сессии (SPEC A6.3).
  ///
  /// In ru, this message translates to:
  /// **'Выберите режим'**
  String get reviewSessionModeTitle;

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

  /// Ошибка парсинга: в документе нет извлекаемого текста.
  ///
  /// In ru, this message translates to:
  /// **'В файле нет текста'**
  String get parserErrorEmptyText;

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

  /// Заголовок экрана настроек генерации (A6.6, API-блок; ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'Настройки генерации'**
  String get settingsTitle;

  /// Название провайдера OpenAI-compatible на экране настроек (ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'OpenAI-совместимый сервер'**
  String get settingsOpenAiCompatibleTitle;

  /// Пояснение к провайдеру OpenAI-compatible: DeepSeek, Ollama, LM Studio и другие (ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'Подходит для облачных и локальных серверов, совместимых с OpenAI'**
  String get settingsOpenAiCompatibleDescription;

  /// Подпись поля base_url OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Адрес сервера'**
  String get settingsServerAddressLabel;

  /// Подсказка поля base_url: например /v1 для локальных серверов.
  ///
  /// In ru, this message translates to:
  /// **'Полный адрес; версию укажите в пути, если сервер её требует'**
  String get settingsServerAddressHint;

  /// Подпись поля модели OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get settingsModelLabel;

  /// Подсказка поля модели OpenAI-совместимого сервера.
  ///
  /// In ru, this message translates to:
  /// **'Имя модели на сервере'**
  String get settingsModelHint;

  /// Подпись поля ключа OpenAI-совместимого сервера (локальным серверам ключ не нужен).
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа (необязательно)'**
  String get settingsApiKeyLabel;

  /// Пояснение к полю ключа: ключ не отображается, пустое поле = удалить сохранённый ключ.
  ///
  /// In ru, this message translates to:
  /// **'Ключ хранится в защищённом хранилище и не показывается. Введите новый ключ, чтобы заменить, или оставьте поле пустым, чтобы удалить'**
  String get settingsApiKeyHelper;

  /// Индикатор: для OpenAI-совместимого сервера сохранён ключ доступа.
  ///
  /// In ru, this message translates to:
  /// **'Ключ доступа сохранён'**
  String get settingsApiKeyConfigured;

  /// Снекбар после сохранения настроек сервера.
  ///
  /// In ru, this message translates to:
  /// **'Настройки сервера сохранены'**
  String get settingsSaved;

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
  /// **'Настройки генерации'**
  String get settingsOpenTooltip;

  /// Заголовок блока ключей облачных провайдеров на экране настроек генерации (A6.6/A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Ключи API'**
  String get settingsApiKeysTitle;

  /// Пояснение к блоку ключей API (SPEC 3.4).
  ///
  /// In ru, this message translates to:
  /// **'Ключи хранятся в защищённом хранилище и не показываются. Введите новый ключ, чтобы заменить сохранённый'**
  String get settingsApiKeysDescription;

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

  /// Кнопка сохранения ключа облачного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить ключ'**
  String get settingsKeySave;

  /// Кнопка удаления сохранённого ключа облачного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Удалить ключ'**
  String get settingsKeyDelete;

  /// Снекбар после сохранения ключа облачного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Ключ сохранён'**
  String get settingsKeySaved;

  /// Снекбар после удаления ключа облачного провайдера.
  ///
  /// In ru, this message translates to:
  /// **'Ключ удалён'**
  String get settingsKeyDeleted;

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
  /// **'Перетащите файлы сюда или нажмите, чтобы выбрать. Поддерживаются Word, Excel, PDF, PowerPoint, текст и другие'**
  String get generationAttachHint;

  /// Кнопка открытия файлового пикера на экране генерации.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать файлы'**
  String get generationAttachButton;

  /// Пустой список прикреплённых файлов.
  ///
  /// In ru, this message translates to:
  /// **'Файлы не прикреплены'**
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

  /// Статус успешного парсинга прикреплённого файла.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get generationFileParsed;

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

  /// Название провайдера Gemini (бренд, латиница допустима).
  ///
  /// In ru, this message translates to:
  /// **'Gemini'**
  String get generationProviderGemini;

  /// Название провайдера Anthropic (бренд, латиница допустима).
  ///
  /// In ru, this message translates to:
  /// **'Anthropic'**
  String get generationProviderAnthropic;

  /// Название OpenAI-совместимого провайдера (ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'OpenAI-совместимый'**
  String get generationProviderOpenAiCompatible;

  /// Подпись выбора модели генерации (SPEC A6.8).
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get generationModelLabel;

  /// Пояснение для OpenAI-совместимого провайдера: модель из настроек (ADR-013).
  ///
  /// In ru, this message translates to:
  /// **'Модель задаётся в настройках сервера'**
  String get generationModelCompatibleHint;

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

  /// Валидация: генерация без прикреплённых файлов.
  ///
  /// In ru, this message translates to:
  /// **'Прикрепите хотя бы один файл'**
  String get generationNoFilesError;

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
  /// **'Нет текста для генерации. Добавьте файл с текстом'**
  String get generationErrorNoMaterials;

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
