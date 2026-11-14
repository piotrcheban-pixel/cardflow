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
  String get reviewModeFeed => 'Лента';

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
  String get feedPause => 'Пауза';

  @override
  String get feedResume => 'Продолжить';

  @override
  String feedSeconds(int count) {
    return '$count с';
  }

  @override
  String get feedAutoAdvanceTooltip => 'Авто-продвижение';

  @override
  String feedCounter(int position, int total) {
    return '$position из $total';
  }

  @override
  String get feedRatedLabel => 'Оценено';

  @override
  String feedProgressSemantics(int rated, int total) {
    return 'Оценено $rated из $total';
  }

  @override
  String get feedSwipeHint => 'Свайп вправо — «Знаю», влево — «Не знаю»';

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
  String get generationErrorProviderNotConfigured =>
      'Сервер не настроен. Укажите адрес и модель в настройках';

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

  @override
  String get settingsTitle => 'Настройки генерации';

  @override
  String get settingsOpenAiCompatibleTitle => 'OpenAI-совместимый сервер';

  @override
  String get settingsOpenAiCompatibleDescription =>
      'Подходит для облачных и локальных серверов, совместимых с OpenAI';

  @override
  String get settingsServerAddressLabel => 'Адрес сервера';

  @override
  String get settingsServerAddressHint =>
      'Полный адрес; версию укажите в пути, если сервер её требует';

  @override
  String get settingsModelLabel => 'Модель';

  @override
  String get settingsModelHint => 'Имя модели на сервере';

  @override
  String get settingsApiKeyLabel => 'Ключ доступа (необязательно)';

  @override
  String get settingsApiKeyHelper =>
      'Ключ хранится в защищённом хранилище и не показывается. Введите новый ключ, чтобы заменить, или оставьте поле пустым, чтобы удалить';

  @override
  String get settingsApiKeyConfigured => 'Ключ доступа сохранён';

  @override
  String get settingsSaved => 'Настройки сервера сохранены';

  @override
  String get settingsSaveError =>
      'Не удалось сохранить настройки. Попробуйте ещё раз';

  @override
  String get settingsLoadError =>
      'Не удалось загрузить настройки. Попробуйте ещё раз';

  @override
  String get settingsAddressEmptyError => 'Укажите адрес сервера';

  @override
  String get settingsAddressInvalidError =>
      'Проверьте адрес: нужен полный адрес с протоколом';

  @override
  String get settingsModelEmptyError => 'Укажите модель';

  @override
  String get settingsOpenTooltip => 'Настройки генерации';

  @override
  String get settingsApiKeysTitle => 'Ключи API';

  @override
  String get settingsApiKeysDescription =>
      'Ключи хранятся в защищённом хранилище и не показываются. Введите новый ключ, чтобы заменить сохранённый';

  @override
  String get settingsKeyConfigured => 'Ключ сохранён';

  @override
  String get settingsKeyMissing => 'Ключ не задан';

  @override
  String get settingsKeySave => 'Сохранить ключ';

  @override
  String get settingsKeyDelete => 'Удалить ключ';

  @override
  String get settingsKeySaved => 'Ключ сохранён';

  @override
  String get settingsKeyDeleted => 'Ключ удалён';

  @override
  String get settingsKeyEmptyError => 'Введите ключ';

  @override
  String get settingsCloudKeyLabel => 'Ключ доступа';

  @override
  String get decksCreateGenerate => 'Сгенерировать карточки';

  @override
  String get deckGenerateTooltip => 'Сгенерировать карточки';

  @override
  String get generationTitle => 'Генерация карточек';

  @override
  String get generationAttachHint =>
      'Перетащите файлы сюда или нажмите, чтобы выбрать. Поддерживаются Word, Excel, PDF, PowerPoint, текст и другие';

  @override
  String get generationAttachButton => 'Выбрать файлы';

  @override
  String get generationFilesEmpty => 'Файлы не прикреплены';

  @override
  String get generationFileRemoveTooltip => 'Убрать файл';

  @override
  String get generationFileParsing => 'Читаем файл…';

  @override
  String get generationFileParsed => 'Готово';

  @override
  String generationFileSizeBytes(int size) {
    return '$size Б';
  }

  @override
  String generationFileSizeKb(int size) {
    return '$size КБ';
  }

  @override
  String generationFileSizeMb(int size) {
    return '$size МБ';
  }

  @override
  String get generationWishesLabel => 'Дополнительные пожелания';

  @override
  String get generationWishesHint =>
      'Необязательно. Например: сделайте акцент на датах, или добавьте больше карточек по теме X';

  @override
  String get generationProviderLabel => 'Провайдер';

  @override
  String get generationProviderOpenAi => 'OpenAI';

  @override
  String get generationProviderGemini => 'Gemini';

  @override
  String get generationProviderAnthropic => 'Anthropic';

  @override
  String get generationProviderOpenAiCompatible => 'OpenAI-совместимый';

  @override
  String get generationModelLabel => 'Модель';

  @override
  String get generationModelCompatibleHint =>
      'Модель задаётся в настройках сервера';

  @override
  String get generationDeckNameLabel => 'Имя колоды (необязательно)';

  @override
  String get generationDeckNameHint => 'Пусто — из имени первого файла';

  @override
  String generationTargetDeck(String name) {
    return 'Карточки будут добавлены в колоду «$name»';
  }

  @override
  String get generationDeckDefaultName => 'Сгенерированные карточки';

  @override
  String generationEstimate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count токена',
      many: '$count токенов',
      few: '$count токена',
      one: '$count токен',
    );
    return 'Примерно $_temp0';
  }

  @override
  String get generationEstimateWarning =>
      'Материала много: запрос будет разбит на несколько частей';

  @override
  String get generationNoFilesError => 'Прикрепите хотя бы один файл';

  @override
  String get generationNoParsedFilesError =>
      'Ни один файл не удалось прочитать. Проверьте формат и размер файлов';

  @override
  String get generationFilesParsing => 'Дождитесь окончания чтения файлов';

  @override
  String get generationKeyMissing => 'Ключ доступа не задан';

  @override
  String get generationOpenSettings => 'Открыть настройки';

  @override
  String get generationStart => 'Сгенерировать';

  @override
  String get generationProgressReading => 'Читаем файлы…';

  @override
  String generationProgressSending(int current, int total) {
    return 'Отправляем в нейросеть… (фрагмент $current из $total)';
  }

  @override
  String get generationProgressReceiving => 'Получаем карточки…';

  @override
  String get generationCancelled => 'Генерация отменена';

  @override
  String get generationErrorNoMaterials =>
      'Нет текста для генерации. Добавьте файл с текстом';

  @override
  String get generationPreviewTitle => 'Предпросмотр карточек';

  @override
  String get generationPreviewEmpty => 'Модель не вернула карточки';

  @override
  String generationPreviewSelected(int selected, int total) {
    return 'Выбрано: $selected из $total';
  }

  @override
  String get generationPreviewImportAll => 'Импортировать все';

  @override
  String get generationPreviewImportSelected => 'Импортировать выбранные';

  @override
  String get generationPreviewCancel => 'Отмена';

  @override
  String get generationPreviewNoSelection => 'Выберите хотя бы одну карточку';

  @override
  String get generationPreviewValidationError =>
      'Проверьте заполнение выбранных карточек: вопрос и ответ должны быть корректными';

  @override
  String get generationIssueEmptyFront => 'Пустой вопрос';

  @override
  String get generationIssueFrontTooLong => 'Вопрос длиннее 500 символов';

  @override
  String get generationIssueBackTooLong => 'Ответ длиннее 2000 символов';

  @override
  String get generationIssueClozeMissing => 'В карточке cloze нет пропусков';

  @override
  String get generationIssueLatexBroken => 'Ошибка разметки формулы';

  @override
  String get generationIssueExcerptMismatch =>
      'Цитата не найдена в исходном тексте';

  @override
  String get generationIssueTagsAdjusted => 'Теги скорректированы';

  @override
  String generationDuplicatesRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дубликата пропущено',
      many: '$count дубликатов пропущено',
      few: '$count дубликата пропущено',
      one: '$count дубликат пропущен',
      zero: 'Дубликатов нет',
    );
    return '$_temp0';
  }

  @override
  String generationTokensUsed(int count) {
    return 'Израсходовано токенов: $count';
  }

  @override
  String get generationFailuresTitle => 'Не удалось обработать фрагменты';

  @override
  String generationFailureChunk(int index, String message) {
    return 'Фрагмент $index: $message';
  }

  @override
  String get generationRetryFailed => 'Повторить неудавшиеся';

  @override
  String get generationImportError =>
      'Не удалось импортировать карточки. Попробуйте ещё раз';

  @override
  String generationImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Импортировано $count карточки',
      many: 'Импортировано $count карточек',
      few: 'Импортировано $count карточки',
      one: 'Импортирована $count карточка',
      zero: 'Карточки не импортированы',
    );
    return '$_temp0';
  }

  @override
  String get cardFormClozeMissingError => 'Добавьте хотя бы один пропуск';

  @override
  String get cardFormOcclusionSection => 'Изображение и маски';

  @override
  String get cardFormPickImage => 'Выбрать изображение';

  @override
  String get cardFormChangeImage => 'Заменить изображение';

  @override
  String get cardFormImageLoadError =>
      'Не удалось загрузить изображение. Выберите другое изображение до 25 МБ.';

  @override
  String get cardFormOcclusionImageMissingError =>
      'Выберите изображение для масок';

  @override
  String get cardFormOcclusionMasksMissingError =>
      'Добавьте хотя бы одну маску';

  @override
  String get cardFormOcclusionInvalidError =>
      'Проверьте изображение и координаты масок';

  @override
  String get occlusionRectangle => 'Прямоугольник';

  @override
  String get occlusionEllipse => 'Эллипс';

  @override
  String get occlusionDeleteMaskTooltip => 'Удалить маску';

  @override
  String get occlusionShowAll => 'Показать все';

  @override
  String get occlusionHideAll => 'Скрыть все';

  @override
  String get occlusionImageUnavailable => 'Не удалось загрузить изображение';

  @override
  String get occlusionInvalid => 'Ошибка разметки масок';

  @override
  String get latexNextStep => 'Следующий шаг';

  @override
  String get clozeHiddenAnswer => '…';

  @override
  String get occlusionDrawHint =>
      'Проведите по изображению, чтобы добавить маску';

  @override
  String occlusionMaskNumber(int number) {
    return 'Маска $number';
  }

  @override
  String get constructorTitle => 'Конструктор сессии';

  @override
  String get constructorAction => 'Конструктор';

  @override
  String get constructorDecksSection => 'Колоды';

  @override
  String get constructorTagsSection => 'Теги';

  @override
  String get constructorTagsEmpty => 'У выбранных колод нет тегов';

  @override
  String get constructorSelectDecksHint =>
      'Выберите колоды, чтобы собрать сессию';

  @override
  String get constructorTypesSection => 'Тип карточки';

  @override
  String get constructorStatesSection => 'Состояние';

  @override
  String get constructorStateNew => 'Новые';

  @override
  String get constructorStateInProgress => 'В процессе';

  @override
  String get constructorStateReview => 'Повторение';

  @override
  String get constructorStateLeeches => 'Пиявки';

  @override
  String get constructorModeSection => 'Режим';

  @override
  String get constructorLimitSection => 'Лимит';

  @override
  String get constructorLimitCards => 'Карточки';

  @override
  String get constructorLimitMinutes => 'Минуты';

  @override
  String constructorLimitCardsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки',
      many: '$count карточек',
      few: '$count карточки',
      one: '$count карточка',
    );
    return '$_temp0';
  }

  @override
  String constructorLimitMinutesValue(int count) {
    return '$count мин';
  }

  @override
  String get constructorOrderSection => 'Порядок';

  @override
  String get constructorShuffle => 'Перемешать';

  @override
  String get constructorShuffleHint => 'Случайный порядок карточек';

  @override
  String get constructorInterleave => 'Интерливинг';

  @override
  String get constructorInterleaveHint =>
      'Подмешивать карточки из разных колод';

  @override
  String get constructorWarmup => 'Разминка';

  @override
  String get constructorWarmupHint => 'Первые карточки — самые лёгкие';

  @override
  String get constructorPresetsSection => 'Пресеты';

  @override
  String get constructorPresetsEmpty => 'Сохранённых пресетов нет';

  @override
  String get constructorSavePreset => 'Сохранить пресет';

  @override
  String get constructorPresetDialogTitle => 'Название пресета';

  @override
  String get constructorPresetNameLabel => 'Название';

  @override
  String get constructorPresetNameEmpty => 'Введите название пресета';

  @override
  String get constructorPresetSaved => 'Пресет сохранён';

  @override
  String get constructorPresetDeleted => 'Пресет удалён';

  @override
  String get constructorPresetDeleteTooltip => 'Удалить пресет';

  @override
  String constructorAvailableCount(int count) {
    return 'Доступно карточек: $count';
  }

  @override
  String get constructorEmptyDecks =>
      'Нет активных колод. Создайте колоду, чтобы собрать сессию.';

  @override
  String get constructorLoadError => 'Не удалось загрузить колоды';

  @override
  String sessionDeckCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count колоды',
      many: '$count колод',
      few: '$count колоды',
      one: '$count колода',
    );
    return '$_temp0';
  }

  @override
  String get reviewTimeUpTitle => 'Время сессии истекло';

  @override
  String reviewTimeUpMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Повторено $count карточки',
      many: 'Повторено $count карточек',
      few: 'Повторено $count карточки',
      one: 'Повторена $count карточка',
      zero: 'Ни одной карточки',
    );
    return '$_temp0';
  }

  @override
  String get reviewPlanMissingTitle => 'Сессия не найдена';

  @override
  String get reviewPlanMissingMessage =>
      'Откройте конструктор и соберите сессию заново.';
}
