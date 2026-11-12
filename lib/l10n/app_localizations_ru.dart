// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'CardFlow';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get delete => 'Удалить';

  @override
  String get undo => 'Отменить';

  @override
  String get retry => 'Повторить';

  @override
  String get genericError =>
      'Не удалось выполнить действие. Попробуйте ещё раз.';

  @override
  String get decksTitle => 'Мои колоды';

  @override
  String get decksSearchTooltip => 'Поиск';

  @override
  String get decksFilterTooltip => 'Фильтр';

  @override
  String get decksSearchHint => 'Поиск колод';

  @override
  String get decksSearchClearTooltip => 'Очистить поиск';

  @override
  String get deckFilterAll => 'Все';

  @override
  String get deckFilterNew => 'Новые';

  @override
  String get deckFilterInProgress => 'В процессе';

  @override
  String get deckFilterDue => 'Просроченные';

  @override
  String get decksEmptyTitle => 'Пока нет колод';

  @override
  String get decksEmptyMessage =>
      'Создайте колоду вручную или импортируйте её из ZIP-архива.';

  @override
  String get decksNoResults => 'Ничего не найдено';

  @override
  String get decksErrorTitle => 'Не удалось загрузить колоды';

  @override
  String get decksCreateButton => 'Создать';

  @override
  String get decksCreateDeckFab => 'Создать колоду';

  @override
  String get decksCreateManual => 'Вручную';

  @override
  String get decksImportZip => 'Импорт ZIP';

  @override
  String get decksMenuTooltip => 'Действия с колодой';

  @override
  String get deckRename => 'Переименовать';

  @override
  String get deckExport => 'Экспорт';

  @override
  String get deckActionArchive => 'Архивировать';

  @override
  String get decksCreateMenuTooltip => 'Другие способы создания';

  @override
  String deckCardCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки',
      many: '$count карточек',
      few: '$count карточки',
      one: '$count карточка',
      zero: 'Нет карточек',
    );
    return '$_temp0';
  }

  @override
  String deckDueCount(int count) {
    return 'К повторению: $count';
  }

  @override
  String deckNewCount(int count) {
    return 'Новые: $count';
  }

  @override
  String deckInProgressCount(int count) {
    return 'В процессе: $count';
  }

  @override
  String get deckCreateDialogTitle => 'Новая колода';

  @override
  String get deckRenameDialogTitle => 'Переименовать колоду';

  @override
  String get deckNameLabel => 'Название колоды';

  @override
  String get deckNameEmptyError => 'Введите название колоды';

  @override
  String get deckDeleteDialogTitle => 'Удалить колоду?';

  @override
  String deckDeleteDialogMessage(String name) {
    return 'Колода «$name» и все её карточки будут удалены без возможности восстановления.';
  }

  @override
  String get deckArchivedMessage => 'Колода в архиве';

  @override
  String get deckExportSuccess => 'Колода экспортирована';

  @override
  String get deckImportSuccess => 'Колода импортирована';

  @override
  String get deckDefaultFileName => 'Колода';

  @override
  String get deckNotFound => 'Колода не найдена';

  @override
  String get deckErrorTitle => 'Не удалось загрузить колоду';

  @override
  String get deckCardsEmpty => 'В колоде пока нет карточек';

  @override
  String get deckCardsEmptyHint =>
      'Карточки появятся после создания, генерации или импорта.';

  @override
  String cardTagsLine(String tags) {
    return 'Теги: $tags';
  }

  @override
  String get cardStateNew => 'Новая';

  @override
  String get cardStateLearning => 'Изучается';

  @override
  String get cardStateReview => 'В повторении';

  @override
  String get cardStateRelearning => 'Переизучается';

  @override
  String get importPreviewTitle => 'Импорт колоды';

  @override
  String importPreviewDeckName(String name) {
    return 'Колода: $name';
  }

  @override
  String importPreviewFormatVersion(int version) {
    return 'Версия формата: $version';
  }

  @override
  String importPreviewCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки',
      many: '$count карточек',
      few: '$count карточки',
      one: '$count карточка',
      zero: 'Карточек нет',
    );
    return '$_temp0';
  }

  @override
  String importPreviewDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дубликата',
      many: '$count дубликатов',
      few: '$count дубликата',
      one: '$count дубликат',
      zero: 'Дубликатов нет',
    );
    return '$_temp0';
  }

  @override
  String importPreviewMedia(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count медиафайла',
      many: '$count медиафайлов',
      few: '$count медиафайла',
      one: '$count медиафайл',
      zero: 'Без медиафайлов',
    );
    return '$_temp0';
  }

  @override
  String get importConfirm => 'Импортировать';

  @override
  String get archiveErrorUnsupportedVersion =>
      'Версия архива не поддерживается. Обновите CardFlow.';

  @override
  String get archiveErrorCorruptZip =>
      'Не удалось прочитать архив: файл повреждён.';

  @override
  String get archiveErrorMissingEntry => 'В архиве нет обязательных файлов.';

  @override
  String get archiveErrorInvalidMeta => 'Метаданные архива повреждены.';

  @override
  String get archiveErrorInvalidCards => 'Карточки в архиве повреждены.';

  @override
  String get archiveErrorTooLarge => 'Архив слишком большой.';

  @override
  String get archiveErrorMediaMissing => 'В архиве не хватает медиафайлов.';

  @override
  String get archiveErrorDeckNotFound => 'Колода не найдена в архиве.';

  @override
  String get archiveErrorInvalidEntryName => 'В архиве недопустимое имя файла.';

  @override
  String get archiveErrorUnknown =>
      'Не удалось выполнить операцию с архивом. Попробуйте ещё раз.';

  @override
  String get databaseOpenError =>
      'Не удалось открыть базу данных. Перезапустите приложение.';
}
