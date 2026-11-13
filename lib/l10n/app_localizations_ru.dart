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

  @override
  String get reviewTitle => 'Повторение';

  @override
  String get reviewModeClassic => 'Классический';

  @override
  String get reviewSessionModeTitle => 'Выберите режим';

  @override
  String get reviewStartSession => 'Начать сессию';

  @override
  String get reviewStartEmptyMessage => 'Нет карточек к повторению';

  @override
  String get reviewEmptyTitle => 'Нет карточек к повторению';

  @override
  String get reviewEmptyMessage =>
      'Все карточки на сегодня повторены. Возвращайтесь позже или добавьте новые.';

  @override
  String get reviewBack => 'Назад';

  @override
  String get reviewLoadError => 'Не удалось загрузить карточки сессии.';

  @override
  String get reviewUndoTooltip => 'Отменить последнюю оценку';

  @override
  String get reviewUndoneMessage => 'Оценка отменена';

  @override
  String get reviewSaveError =>
      'Не удалось сохранить оценку. Попробуйте ещё раз.';

  @override
  String get reviewUndoError =>
      'Не удалось отменить оценку. Попробуйте ещё раз.';

  @override
  String get reviewCloseTooltip => 'Выйти из сессии';

  @override
  String get reviewExitDialogTitle => 'Выйти из сессии?';

  @override
  String get reviewExitDialogMessage =>
      'Оценки сохраняются сразу, прогресс не потеряется.';

  @override
  String get reviewExitContinue => 'Продолжить';

  @override
  String get reviewExitConfirm => 'Выйти';

  @override
  String get reviewWhyTooltip => 'Почему?';

  @override
  String get reviewWhySheetTitle => 'Почему эта карточка?';

  @override
  String get reviewProgressLabel => 'Прогресс сессии';

  @override
  String get reviewCompletedTitle => 'Сессия завершена';

  @override
  String reviewCompletedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки повторено',
      many: '$count карточек повторено',
      few: '$count карточки повторено',
      one: '$count карточка повторена',
      zero: 'Нет оценённых карточек',
    );
    return '$_temp0';
  }

  @override
  String get reviewDone => 'Готово';

  @override
  String get ratingAgain => 'Не знаю';

  @override
  String get ratingHard => 'Сложно';

  @override
  String get ratingGood => 'Знаю';

  @override
  String get ratingEasy => 'Легко';

  @override
  String get reviewIntervalLessThanMinute => '<1 мин';

  @override
  String reviewIntervalMinutes(int count) {
    return '$count мин';
  }

  @override
  String reviewIntervalHours(int count) {
    return '$count ч';
  }

  @override
  String reviewIntervalDays(int count) {
    return '$count д';
  }

  @override
  String get cardFormTitleNew => 'Новая карточка';

  @override
  String get cardFormTitleEdit => 'Редактировать карточку';

  @override
  String get cardFormFrontLabel => 'Вопрос';

  @override
  String get cardFormBackLabel => 'Ответ';

  @override
  String get cardFormHintLabel => 'Подсказка (необязательно)';

  @override
  String get cardFormTagsLabel => 'Теги через запятую (необязательно)';

  @override
  String get cardFormSourceExcerptLabel =>
      'Цитата для кнопки «Почему?» (необязательно)';

  @override
  String get cardFormTypeLabel => 'Тип карточки';

  @override
  String get cardTypeBasic => 'Обычная';

  @override
  String get cardTypeBasicReversed => 'Двусторонняя';

  @override
  String get cardTypeCloze => 'С пропусками';

  @override
  String get cardFormReversedHint =>
      'Будет создана вторая карточка с обратным вопросом.';

  @override
  String get cardFormTypeImmutable =>
      'Тип карточки нельзя изменить после создания.';

  @override
  String get cardFormFrontEmptyError => 'Введите вопрос';

  @override
  String get cardFormFrontTooLongError => 'Не больше 500 символов';

  @override
  String get cardFormBackEmptyError => 'Введите ответ';

  @override
  String get cardFormBackTooLongError => 'Не больше 2000 символов';

  @override
  String get cardFormTagsTooManyError => 'Не больше 3 тегов';

  @override
  String get cardFormSourceExcerptTooLongError => 'Не больше 400 символов';

  @override
  String get cardFormSaveError =>
      'Не удалось сохранить карточку. Попробуйте ещё раз.';

  @override
  String get cardFormLoadError => 'Не удалось загрузить карточку.';

  @override
  String get cardFormDeleteError =>
      'Не удалось удалить карточку. Попробуйте ещё раз.';

  @override
  String get cardDeleteDialogTitle => 'Удалить карточку?';

  @override
  String get cardDeleteDialogMessage =>
      'Карточка будет удалена без возможности восстановления.';

  @override
  String get cardDeleteTooltip => 'Удалить карточку';

  @override
  String get cardCreatedMessage => 'Карточка создана';

  @override
  String get cardUpdatedMessage => 'Изменения сохранены';

  @override
  String get cardDeletedMessage => 'Карточка удалена';

  @override
  String get deckAddCardTooltip => 'Добавить карточку';

  @override
  String get parserErrorUnreadableFile => 'Не удалось прочитать файл';

  @override
  String get parserErrorUnsupportedFormat =>
      'Формат не поддерживается. Сохраните файл как DOCX или XLSX и попробуйте снова';

  @override
  String get parserErrorScannedPdf =>
      'В файле нет текстового слоя. Похоже, это скан. Загрузите PDF с текстом';

  @override
  String get parserErrorFileTooLarge =>
      'Файл больше 25 МБ. Уменьшите файл и попробуйте снова';

  @override
  String get parserErrorEmptyText => 'В файле нет текста';

  @override
  String get generationErrorMissingApiKey =>
      'Ключ доступа не задан. Добавьте ключ в настройках';

  @override
  String get generationErrorInvalidApiKey =>
      'Ключ доступа недействителен. Проверьте ключ в настройках';

  @override
  String get generationErrorBadRequest =>
      'Запрос отклонён. Проверьте выбранную модель и ключ в настройках';

  @override
  String generationErrorRateLimited(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds секунды',
      many: '$seconds секунд',
      few: '$seconds секунды',
      one: '$seconds секунду',
    );
    return 'Превышен лимит запросов. Повтор через $_temp0';
  }

  @override
  String get generationErrorRateLimitedNoDelay =>
      'Превышен лимит запросов. Попробуйте позже';

  @override
  String get generationErrorServerUnavailable =>
      'Провайдер временно недоступен. Попробуйте позже';

  @override
  String get generationErrorNoConnection => 'Нет подключения к интернету';

  @override
  String get generationErrorCancelled => 'Генерация отменена';

  @override
  String get generationErrorEmptyResponse =>
      'Нейросеть вернула пустой ответ. Попробуйте ещё раз';

  @override
  String get generationErrorUnexpectedResponse =>
      'Нейросеть вернула неожиданный ответ. Попробовать снова?';

  @override
  String get generationErrorGeneric =>
      'Не удалось получить карточки. Попробуйте ещё раз';
}
