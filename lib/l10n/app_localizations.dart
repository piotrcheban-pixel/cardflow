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
  /// **'Архив слишком большой для импорта.'**
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
