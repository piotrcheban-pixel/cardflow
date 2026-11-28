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
  String get decksMenuTooltip => 'Действия с колодой';

  @override
  String get deckRename => 'Переименовать';

  @override
  String get deckExport => 'Экспорт';

  @override
  String get deckActionArchive => 'Архивировать';

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
  String get archiveErrorWriteDenied =>
      'Нет прав на запись в эту папку. Выберите другую.';

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
  String get reviewModePractice => 'Тренировка';

  @override
  String get practiceTitle => 'Тренировка';

  @override
  String get practiceSubtitle =>
      'Карточки идут без учёта интервалов: FSRS не меняется.';

  @override
  String get practiceEmptyTitle => 'Нет карточек для тренировки';

  @override
  String get practiceEmptyMessage =>
      'Добавьте карточки в колоду или снимите приостановку.';

  @override
  String get practiceCompletedTitle => 'Тренировка завершена';

  @override
  String practiceCompletedMessage(int count) {
    return 'Пройдено карточек: $count.';
  }

  @override
  String practiceRatedLabel(int count, int total) {
    return 'Пройдено $count из $total';
  }

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
  String get reviewDailyLimitTitle => 'Дневной лимит исчерпан';

  @override
  String get reviewDailyLimitMessage =>
      'Дневной лимит на сегодня исчерпан. Можно продолжить без лимита или пройти карточки в режиме «Тренировка» — интервалы FSRS не изменятся.';

  @override
  String get reviewDailyLimitContinueAction => 'Продолжить без лимита';

  @override
  String get reviewDailyLimitContinueMessage =>
      'Дневной лимит на сегодня исчерпан. Продолжить изучение без лимита или пройти карточки в режиме «Тренировка» — интервалы FSRS не изменятся.';

  @override
  String get practiceStartAction => 'Тренировать';

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
      'Текущая карточка останется неоценённой и появится в следующий раз.';

  @override
  String get reviewExitContinue => 'Продолжить';

  @override
  String get reviewExitConfirm => 'Выйти';

  @override
  String get reviewWhyTooltip => 'Почему?';

  @override
  String get reviewWhySheetTitle => 'Почему эта карточка?';

  @override
  String get feedBrowseBadge => 'Просмотр';

  @override
  String get feedBrowseHint => 'Нажмите на карточку, чтобы увидеть ответ';

  @override
  String get feedNavHint => '↑↓ / колесо мыши / стрелки — листать';

  @override
  String feedProgressSemantics(int position, int total) {
    return 'Карточка $position из $total';
  }

  @override
  String get feedSwipeHint => 'Свайп вверх или вниз переключает карточки';

  @override
  String get feedEmptyTitle => 'В колоде пока нет карточек';

  @override
  String get feedEmptyMessage =>
      'Добавьте карточки или сгенерируйте их — лента покажет весь материал колоды.';

  @override
  String get feedReadFullText => 'Открыть полностью';

  @override
  String get feedFullTextTitle => 'Карточка целиком';

  @override
  String get feedPreviousTooltip => 'Предыдущая карточка';

  @override
  String get feedNextTooltip => 'Следующая карточка';

  @override
  String feedTimeUpMessage(int count) {
    return 'Просмотрено карточек: $count. Расписание повторений не изменилось.';
  }

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
  String get ratingHard => 'Затрудняюсь';

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
  String get cardFormTitleEditShort => 'Редактирование';

  @override
  String get cardFormFrontLabel => 'Вопрос';

  @override
  String get cardFormBackLabel => 'Ответ';

  @override
  String get cardFormHintLabel => 'Подсказка (необязательно)';

  @override
  String get cardFormTagsLabel => 'Теги';

  @override
  String get cardFormSourceExcerptLabel => 'Цитата источника';

  @override
  String get cardFormTypeLabel => 'Тип карточки';

  @override
  String get cardTypeBasic => 'Обычная';

  @override
  String get cardTypeBasicReversed => 'Двусторонняя';

  @override
  String get cardTypeCloze => 'С пропусками';

  @override
  String get cardTypeOcclusion => 'Изображение с маской';

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
  String get parserErrorEmptyText =>
      'В файле нет текста (скан или пустая форма)';

  @override
  String get parserErrorGarbledText =>
      'PDF содержит нечитаемый текст. Сохраните файл в другом формате и попробуйте снова';

  @override
  String get parserErrorDocNotSupported =>
      'Формат .doc не поддерживается. Сохраните файл как .docx и попробуйте снова';

  @override
  String get parserErrorPptNotSupported =>
      'Формат .ppt не поддерживается. Сохраните файл как .pptx и попробуйте снова';

  @override
  String get parserErrorFileAccessDenied =>
      'Нет доступа к выбранному файлу. Скопируйте файл в память устройства и попробуйте снова';

  @override
  String get parserErrorCorruptFile =>
      'Файл повреждён или не является документом этого формата';

  @override
  String get parserErrorPasswordProtected =>
      'PDF защищён паролем. Снимите защиту и попробуйте снова';

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
  String get generationErrorInsufficientBalance =>
      'Недостаточно средств на балансе провайдера. Проверьте баланс или ключ API';

  @override
  String get generationErrorBadRequest =>
      'Запрос отклонён. Проверьте выбранную модель и ключ в настройках';

  @override
  String generationErrorBadRequestReason(String reason) {
    return 'Запрос отклонён: $reason';
  }

  @override
  String get generationErrorVisionUnsupported =>
      'Модель не поддерживает изображения';

  @override
  String get generationErrorFileWithoutTextAndVision =>
      'В файле нет текста. Модель не поддерживает изображения';

  @override
  String get generationErrorPdfScanUnsupported =>
      'PDF-скан не поддерживается выбранной моделью';

  @override
  String get generationErrorPdfScanVisionRequired =>
      'PDF-скан без текста. Выберите модель с поддержкой изображений';

  @override
  String get generationErrorAttachmentTooLarge =>
      'Файл больше допустимого размера. Уменьшите файл и попробуйте снова';

  @override
  String get generationErrorContextOverflow =>
      'Материала слишком много для выбранной модели. Уменьшите объём или выберите модель с большим контекстом';

  @override
  String get generationErrorPayloadTooLarge =>
      'Запрос слишком большой для выбранной модели. Уменьшите объём материалов или изображений';

  @override
  String get generationErrorStorageUnavailable =>
      'Не удалось сохранить данные генерации: хранилище недоступно. Проверьте свободное место и права доступа к папке данных приложения';

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
  String get settingsServerAddressLabel => 'Адрес сервера';

  @override
  String get settingsModelLabel => 'Модель';

  @override
  String get settingsSaveError =>
      'Не удалось сохранить настройки. Попробуйте ещё раз';

  @override
  String get settingsSavePermissionError =>
      'Не удалось записать настройки: папка данных приложения недоступна для записи. Проверьте права доступа к папке и перезапустите CardFlow';

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
  String get settingsKeyConfigured => 'Ключ сохранён';

  @override
  String get settingsKeyMissing => 'Ключ не задан';

  @override
  String get settingsKeyDelete => 'Удалить ключ';

  @override
  String get settingsKeyEmptyError => 'Введите ключ';

  @override
  String get settingsCloudKeyLabel => 'Ключ доступа';

  @override
  String get decksCreateGenerate => 'Сгенерировать карточки';

  @override
  String get deckGenerateTooltip => 'Сгенерировать карточки';

  @override
  String get generationAttachHint =>
      'Перетащите файлы сюда или нажмите, чтобы выбрать. Поддерживаются Word, Excel, PDF, PowerPoint, текст, изображения JPG и PNG';

  @override
  String get generationAttachButton => 'Выбрать файлы';

  @override
  String get generationFilesEmpty => 'Файлы не прикреплены (необязательно)';

  @override
  String get generationFileRemoveTooltip => 'Убрать файл';

  @override
  String get generationFileParsing => 'Читаем файл…';

  @override
  String get generationFileParsed => 'Готово';

  @override
  String get generationFileImage => 'Изображение';

  @override
  String get generationFileScannedPdf => 'Скан — отправится как изображение';

  @override
  String get generationFilePdfPages =>
      'Скан — страницы отправятся как изображения';

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
  String get generationModelLabel => 'Модель';

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
  String get generationTopicRequired =>
      'Напишите тему или описание — файлы не обязательны';

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
  String generationProgressCardsCount(int accepted, int requested) {
    return 'Принято карточек: $accepted из $requested';
  }

  @override
  String generationProgressCardsRemaining(int remaining) {
    return 'Осталось добрать: $remaining';
  }

  @override
  String get generationCancelled => 'Генерация отменена';

  @override
  String get generationErrorNoMaterials =>
      'Нет материалов для генерации: прикрепите файл или напишите тему';

  @override
  String get generationNoCardsFound =>
      'Модель не нашла фактов для карточек. Проверьте текст файлов или уточните тему; если материал есть — смените модель';

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
  String get generationIssueOcclusionImageMissing =>
      'Нет изображения для карточки с маской';

  @override
  String get generationIssueImageNotFound => 'Картинка не найдена';

  @override
  String generationImageSearchFailed(int count) {
    return 'Не удалось найти картинку по запросу: $count. Добавьте её вручную или измените вопрос.';
  }

  @override
  String get generationIssueImageDuplicatedSide =>
      'Одно изображение указано на обеих сторонах — оставлено у вопроса';

  @override
  String get generationIssueImageInvalid =>
      'Изображение повреждено и не сохранено';

  @override
  String get generationIssuePossibleDuplicate => 'Возможный дубль';

  @override
  String get generationMarkReverseSide => 'Обратная сторона';

  @override
  String generationMarkWarning(int count) {
    return 'Предупреждение: $count';
  }

  @override
  String get generationMarkNoSource => 'Без источника';

  @override
  String get generationStageTitle => 'Этапы генерации';

  @override
  String get generationStageAnalysis => 'Анализ материала';

  @override
  String get generationStagePlanning => 'План';

  @override
  String get generationStageGenerating => 'Генерация';

  @override
  String get generationStageValidation => 'Проверка';

  @override
  String get generationShortfallReasonsTitle => 'Причины недобора';

  @override
  String get generationShortfallProviderError => 'запрос к модели не удался';

  @override
  String get generationShortfallTruncated =>
      'ответ модели обрезан по лимиту вывода';

  @override
  String get generationShortfallExhaustedMaterial => 'материал исчерпан';

  @override
  String get generationShortfallValidationRejects =>
      'часть карточек отброшена проверкой';

  @override
  String get generationShortfallDuplicates =>
      'часть карточек оказалась дублями уже в колоде';

  @override
  String get generationShortfallCancelled => 'генерация отменена';

  @override
  String get generationShortfallNoCards => 'модель не вернула карточки';

  @override
  String get generationPreviewTopicUntitled => 'Без темы';

  @override
  String generationPreviewTopicTitle(String topic) {
    return 'Тема: $topic';
  }

  @override
  String generationWhySourceSection(String section) {
    return 'Раздел: $section';
  }

  @override
  String generationVerdictPartial(int accepted, int requested) {
    return 'Принято $accepted из $requested: заказ не закрыт';
  }

  @override
  String generationVerdictDone(int accepted, int requested) {
    return 'Заказ закрыт: принято $accepted из $requested';
  }

  @override
  String generationVerdictAuto(int accepted) {
    return 'Создано карточек: $accepted';
  }

  @override
  String generationReportShortfall(String reason, int count) {
    return '$reason: $count';
  }

  @override
  String generationReportCoverage(int covered, int total) {
    return 'Покрыто единиц знания: $covered из $total';
  }

  @override
  String generationReportTokens(int tokens) {
    return 'Израсходовано токенов: $tokens';
  }

  @override
  String generationReportMaterialCapacity(int capacity) {
    return 'Материала примерно на $capacity карточек';
  }

  @override
  String get generationUnderstandingNoText =>
      'В материале нет текстового слоя — понимание невозможно';

  @override
  String generationUnderstandingFailed(int count) {
    return 'Часть материала не удалось понять: фрагментов $count';
  }

  @override
  String get settingsGenerationPipelineV3Title => 'Путь генерации';

  @override
  String get settingsGenerationPipelineV3Hint =>
      'Авто выбирает путь по объёму материала. Пока данных для порога нет, авто — прежний путь.';

  @override
  String get settingsGenerationPathAuto => 'Авто';

  @override
  String get settingsGenerationPathV3 => 'Новый путь';

  @override
  String get settingsGenerationPathLegacy => 'Прежний путь';

  @override
  String get generationIssueImageIdUnknown =>
      'Изображение не найдено в файлах — карточка без картинки';

  @override
  String get generationIssueImageQueryAdjusted =>
      'Поисковый запрос картинки скорректирован';

  @override
  String get generationIssueAbstractImageQuery =>
      'Для абстрактного понятия картинка не ищется';

  @override
  String get generationIssueAnswerInFront => 'Ответ уже содержится в вопросе';

  @override
  String get generationIssueFrontLooksLikeHeading =>
      'Вопрос похож на заголовок';

  @override
  String get generationIssueBackTooVerbose =>
      'Ответ слишком длинный для карточки';

  @override
  String get generationIssueBackOnlyNotation =>
      'Ответ только расшифровывает обозначения';

  @override
  String get generationIssueUnicodeMath =>
      'Индексы и греческие буквы вне формул';

  @override
  String get generationIssueMarkdownInText =>
      'В тексте есть разметка выделения';

  @override
  String get generationReasonNotAtomic => 'Не атомарна: больше трёх пунктов';

  @override
  String get generationReasonQuestionNotSelfContained =>
      'Вопрос несамостоятелен: непонятен без материала';

  @override
  String get generationReasonQuoteNotLiteral => 'Цитата совпала не дословно';

  @override
  String get generationReasonQuoteOutOfRange => 'Цитата вне материала';

  @override
  String get generationReasonWrongLanguage => 'Текст не на русском';

  @override
  String get generationReasonEmptyAfterNormalization =>
      'После нормализации не осталось текста';

  @override
  String get generationReasonClozeMeaningless => 'Пропуск cloze бессмысленный';

  @override
  String get generationReasonSectionUnknown => 'Раздел не из материала';

  @override
  String get generationReasonUnitUnknown => 'Единица знания не из плана';

  @override
  String get generationReasonPossibleDuplicate =>
      'Возможный смысловой дубль: карточка похожа на другую';

  @override
  String generationReasonWarningMark(String reason) {
    return 'Предупреждение: $reason';
  }

  @override
  String generationRejectedCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки отброшено',
      many: '$count карточек отброшено',
      few: '$count карточки отброшены',
      one: '$count карточка отброшена',
    );
    return '$_temp0';
  }

  @override
  String get generationPreviewRemoveImage => 'Убрать картинку';

  @override
  String get generationPreviewReplaceImage => 'Заменить картинку';

  @override
  String get generationPreviewImageReplaced => 'Картинка заменена';

  @override
  String get generationPreviewImageReplaceError =>
      'Не удалось прочитать изображение. Нужен JPG или PNG';

  @override
  String generationPreviewInvalidSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count невалидные карточки пропущены',
      many: '$count невалидных карточек пропущено',
      few: '$count невалидные карточки пропущены',
      one: '$count невалидная карточка пропущена',
    );
    return '$_temp0';
  }

  @override
  String generationImportedWithSkipped(int imported, int skipped) {
    return 'Импортировано карточек: $imported, невалидных пропущено: $skipped';
  }

  @override
  String generationFailureChunkOf(int index, int total, String message) {
    return 'Фрагмент $index из $total: $message';
  }

  @override
  String get generationReasonTruncated =>
      'ответ модели обрезан по лимиту токенов';

  @override
  String get generationReasonRefusal => 'модель отказалась отвечать';

  @override
  String get generationReasonSafety =>
      'ответ заблокирован фильтром безопасности';

  @override
  String get generationReasonJsonParse =>
      'ответ модели не разобрался: некорректные обратные слэши в формулах';

  @override
  String get generationReasonSchemaInvalid =>
      'ответ модели не соответствует схеме карточки';

  @override
  String get generationReasonValidatorRejected =>
      'структура ответа модели непригодна';

  @override
  String get generationReasonNetwork => 'нет сети или истекло время ожидания';

  @override
  String get generationReasonHttpClientError => 'провайдер отклонил запрос';

  @override
  String get generationReasonHttpServerError => 'ошибка на стороне провайдера';

  @override
  String get generationReasonEmptyResponse => 'модель вернула пустой ответ';

  @override
  String get generationReasonProviderResponse =>
      'провайдер вернул неожиданный ответ';

  @override
  String get generationReasonCancelled => 'запрос отменён';

  @override
  String get generationReasonUnknown => 'неизвестная ошибка фрагмента';

  @override
  String get generationReasonStorage => 'хранилище данных недоступно';

  @override
  String get generationReasonContextOverflow => 'переполнение контекста модели';

  @override
  String get generationReasonPayloadTooLarge =>
      'слишком большой размер запроса';

  @override
  String get generationReasonUnsupportedModality =>
      'модель не поддерживает тип вложения';

  @override
  String generationPlanRequestedAboveAchievable(int requested, int achievable) {
    return 'Запрошено $requested карточек, план может выдать $achievable: в материалах нет содержательных разделов, из которых можно сделать карточки. Добавьте текст или выберите другой файл.';
  }

  @override
  String generationPlanMaterialCapacityBelowRequested(
    int capacity,
    int requested,
  ) {
    return 'Материала хватает примерно на $capacity карточек из $requested. Заказ сохранён полностью: план запросит все карточки партиями, а если материал закончится раньше, оставшиеся партии будут остановлены, а не выдуманы.';
  }

  @override
  String generationPlanRequestedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Запрошено: $count карточки',
      many: 'Запрошено: $count карточек',
      few: 'Запрошено: $count карточки',
      one: 'Запрошено: $count карточка',
    );
    return '$_temp0';
  }

  @override
  String generationPlanAchievableAboveRequested(int requested, int achievable) {
    return 'Запрошено $requested карточек, но материалы не удалось укрупнить до меньшего числа фрагментов: план может выдать до $achievable. Уменьшите объём материалов или число карточек.';
  }

  @override
  String generationPlanOmittedUnits(int count) {
    return 'Часть материалов не вошла в план: $count единиц. Уменьшите объём или выберите модель с большим контекстом.';
  }

  @override
  String get generationCardsCountLabel => 'Сколько карточек';

  @override
  String get generationCardsCountHint => 'Авто: по материалу и бюджету модели';

  @override
  String get generationCardsCountInvalid => 'Укажите целое число больше нуля';

  @override
  String get generationCardsCountTooLarge => 'Слишком большое число';

  @override
  String generationPlanPreview(
    int chunks,
    int requests,
    int requested,
    int achievable,
  ) {
    return 'План: частей входа — $chunks, партий — $requests; запрошено — $requested, в плане — $achievable';
  }

  @override
  String generationPlanPreviewAuto(int chunks, int requests, int achievable) {
    return 'План: фрагментов — $chunks, запросов — $requests; будет создано до $achievable карточек';
  }

  @override
  String get generationPlanUnknownCapabilities =>
      'Возможности модели известны не полностью: часть лимитов — консервативные допущения приложения, а не факты провайдера.';

  @override
  String get generationPlanAssumedImageLimits =>
      'Лимит изображений модели не подтверждён — используется консервативное значение приложения.';

  @override
  String generationPlanCatalogOnlyImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count изображения останутся только в каталоге',
      many: '$count изображений останутся только в каталоге',
      few: '$count изображения останутся только в каталоге',
      one: '$count изображение останется только в каталоге',
    );
    return '$_temp0';
  }

  @override
  String generationPlanNoVisionImages(int count) {
    return 'Модель не принимает изображения: $count изображений будут только в каталоге, без передачи модели.';
  }

  @override
  String get generationPlanVisionUnconfirmed =>
      'Совместимость изображений с моделью не подтверждена: изображения будут отправлены, но провайдер может их отклонить.';

  @override
  String get generationPlanContextUnconfirmed =>
      'Окно контекста модели не подтверждено — используются консервативные допущения приложения.';

  @override
  String get generationPlanPayloadLimited =>
      'Запрос ограничен допустимым размером тела: часть вложений не отправлена.';

  @override
  String generationPlanInvalid(String reason) {
    return 'План невыполним: $reason';
  }

  @override
  String get generationPlanReasonContextWindow =>
      'материала слишком много для бюджета модели — уменьшите объём или выберите модель с большим контекстом';

  @override
  String get generationPlanReasonUnitTooLarge =>
      'часть материала не помещается в бюджет модели даже после дробления';

  @override
  String get generationPlanReasonPayloadTooLarge =>
      'запрос больше допустимого размера — уменьшите вложения';

  @override
  String get generationPlanReasonImagesWithoutVision =>
      'приложены изображения, а выбранная модель не поддерживает изображения';

  @override
  String get generationPlanReasonTooManyChunks =>
      'заказ слишком велик для одного запуска — уменьшите число карточек';

  @override
  String get generationPlanDetails => 'Подробнее';

  @override
  String get generationPlanDetailsUnknownValue => 'неизвестно';

  @override
  String get generationPlanDetailsModel => 'Модель';

  @override
  String get generationPlanDetailsContext => 'Контекст';

  @override
  String get generationPlanDetailsInputTokens => 'Вход';

  @override
  String generationPlanDetailsInputExact(int tokens) {
    return 'нативный подсчёт: $tokens токенов';
  }

  @override
  String generationPlanDetailsInputEstimated(int tokens) {
    return 'приблизительно: $tokens токенов (оценка)';
  }

  @override
  String generationPlanDetailsInputMixed(int native, int estimated) {
    return 'смешанный: нативно $native, оценка $estimated';
  }

  @override
  String generationPlanDetailsInputEstimatedExtra(
    int tokens,
    String components,
  ) {
    return 'оценено дополнительно: $tokens токенов ($components)';
  }

  @override
  String generationPlanDetailsInputMargin(int tokens) {
    return 'резерв безопасности: $tokens токенов';
  }

  @override
  String generationPlanDetailsInputBudget(int tokens) {
    return 'плановый бюджет: $tokens токенов';
  }

  @override
  String get generationPlanDetailsNativeCountLabel => 'Число провайдера';

  @override
  String get generationPlanDetailsEstimatedExtraLabel => 'Оценка добавки';

  @override
  String get generationPlanDetailsMarginLabel => 'Резерв бюджета';

  @override
  String get generationPlanDetailsBudgetLabel => 'Плановый бюджет';

  @override
  String get generationPlanDetailsComponentResponseSchema => 'схема ответа';

  @override
  String get generationPlanDetailsComponentImages => 'изображения';

  @override
  String get generationPlanDetailsStrategy => 'Стратегия';

  @override
  String get generationPlanDetailsStrategyWhole =>
      'весь документ в одном запросе';

  @override
  String get generationPlanDetailsStrategyFragmented =>
      'документ делится на части';

  @override
  String get generationPlanDetailsStrategyPromptOnly => 'генерация по теме';

  @override
  String get generationPlanDetailsParts => 'Частей входа';

  @override
  String get generationPlanDetailsBatches => 'Партий (запросов)';

  @override
  String get generationPlanDetailsCardsRequested => 'Запрошено карточек';

  @override
  String get generationPlanDetailsCardsPlanned => 'Всего карточек в плане';

  @override
  String get generationPlanDetailsCardsPerBatch => 'Максимум в одной партии';

  @override
  String get generationPlanDetailsBatchSizes => 'Распределение по партиям';

  @override
  String generationPlanDetailsBatchSizesOverflow(String sizes, int rest) {
    return '$sizes и ещё $rest партий';
  }

  @override
  String get generationPlanDetailsMaterialCapacity =>
      'Ёмкость материала (оценка)';

  @override
  String get generationPlanDetailsMaterialCapacityUnknown => 'не ограничена';

  @override
  String generationPlanDetailsMaterialCapacityValue(int capacity) {
    return 'примерно $capacity карточек';
  }

  @override
  String get generationPlanDetailsRequests => 'Запросов (+на повторы)';

  @override
  String get generationPlanDetailsImagesLabel => 'Изображения';

  @override
  String generationPlanDetailsImages(
    int sent,
    int catalog,
    int unsupported,
    int omitted,
  ) {
    return 'передано $sent, только каталог $catalog, без поддержки $unsupported, исключено $omitted';
  }

  @override
  String get generationPlanDetailsTokensLabel => 'Оценка токенов';

  @override
  String get generationPlanDetailsCatalogTokens => 'Каталог изображений';

  @override
  String get generationPlanDetailsReasoningReserve => 'Резерв на рассуждение';

  @override
  String get generationPlanDetailsCostLabel => 'Стоимость';

  @override
  String generationPlanDetailsCost(String value) {
    return '$value';
  }

  @override
  String get generationPlanDetailsCostUnknown =>
      'неизвестна (тариф не подтверждён)';

  @override
  String get generationPlanDetailsSourcesLabel => 'Источники лимитов';

  @override
  String get generationPlanDetailsUnknownLimitsLabel => 'Неизвестные лимиты';

  @override
  String get generationPlanDetailsWarningsLabel => 'Предупреждения плана';

  @override
  String get generationPlanDetailsNote =>
      'Числа построены тем же планом, что исполняет генерация; второй оценки нет. Неизвестные значения не подменяются типовыми.';

  @override
  String generationPreviewPartial(int processed, int failed) {
    return 'Частичный результат: обработано фрагментов — $processed, с ошибкой — $failed. Импортируйте полученное или повторите неудавшиеся.';
  }

  @override
  String generationPreviewMaterialExhausted(int created, int requested) {
    return 'Материал исчерпан: создано $created карточек из $requested. Оставшиеся партии остановлены — карточки не выдумывались.';
  }

  @override
  String generationPreviewShortfall(int created, int requested) {
    return 'Создано $created карточек из $requested: цель не достигнута, но материал ещё не исчерпан. Можно повторить генерацию, чтобы добрать оставшиеся.';
  }

  @override
  String generationPreviewTrimmed(int count) {
    return 'Лишние карточек сверх заказа не добавлено: $count.';
  }

  @override
  String generationPreviewTruncated(int chunks, int cards) {
    return 'Ответ модели обрывался по лимиту вывода $chunks раз(а): из обрывов сохранено $cards карточек. Недостающие карточки запрашивались отдельно.';
  }

  @override
  String get generationShortfallTitle => 'Создано меньше, чем запрошено';

  @override
  String generationShortfallContext(int requested, int created) {
    return 'Запрошено $requested карточек, сгенерировано $created: модель обрывала ответ по лимиту контекста. Продолжить?';
  }

  @override
  String generationShortfallMaterial(int requested, int created) {
    return 'Запрошено $requested карточек, создано $created: материал исчерпан, лишние карточки не выдумывались. Продолжить?';
  }

  @override
  String generationShortfallGeneric(int requested, int created) {
    return 'Запрошено $requested карточек, создано $created. Продолжить?';
  }

  @override
  String get generationShortfallContinue => 'Продолжить';

  @override
  String generationPreviewCoverage(int empty, int total) {
    return 'Разделов без единой карточки: $empty из $total. Проверьте покрытие материала.';
  }

  @override
  String generationPreviewFatal(String message) {
    return 'Генерация остановлена: $message';
  }

  @override
  String generationPreviewImageSummary(
    int sent,
    int catalog,
    int unsupported,
    int omitted,
  ) {
    return 'Изображения: передано модели — $sent, только в каталоге — $catalog, без поддержки изображений — $unsupported, исключено — $omitted.';
  }

  @override
  String generationPreviewTokenComparison(int estimated, int actual) {
    return 'Оценка входа: ≈$estimated токенов · фактически: $actual';
  }

  @override
  String generationPreviewRecovery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дополнительных запросов — $count',
      many: 'дополнительных запросов — $count',
      few: 'дополнительных запроса — $count',
      one: 'дополнительный запрос — $count',
    );
    return 'Восстановление: $_temp0';
  }

  @override
  String generationFailureRetryAfter(int seconds) {
    return 'повторите через $seconds с';
  }

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
  String get cardFormImageSection => 'Изображение';

  @override
  String get cardFormImageHint =>
      'Изображения вопроса видны до переворота, изображения ответа — только после. Маски нужны, только если части изображения надо скрыть.';

  @override
  String get cardFormQuestionImages => 'Изображения вопроса';

  @override
  String get cardFormAnswerImages => 'Изображения ответа';

  @override
  String get cardFormAddQuestionImage => 'Добавить к вопросу';

  @override
  String get cardFormAddAnswerImage => 'Добавить к ответу';

  @override
  String get cardFormMoveToAnswer => 'На сторону ответа';

  @override
  String get cardFormMoveToQuestion => 'На сторону вопроса';

  @override
  String get cardFormMoveImageUp => 'Выше';

  @override
  String get cardFormMoveImageDown => 'Ниже';

  @override
  String get cardFormEmptyQuestionImages => 'Нет изображений вопроса';

  @override
  String get cardFormEmptyAnswerImages => 'Нет изображений ответа';

  @override
  String get cardFormRemoveImage => 'Удалить изображение';

  @override
  String get cardFormOcclusionToggle => 'Маски изображения';

  @override
  String get cardFormOcclusionToggleHint =>
      'Необязательно. Скрывает части изображения на карточке.';

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

  @override
  String get navDecks => 'Колоды';

  @override
  String get navStatistics => 'Статистика';

  @override
  String get navSettings => 'Настройки';

  @override
  String get statisticsTitle => 'Статистика';

  @override
  String get statisticsRetentionTitle => 'Удержание за 30 дней';

  @override
  String statisticsRetentionValue(int percent) {
    return '$percent%';
  }

  @override
  String get statisticsRetentionNoData => 'Нет повторений за 30 дней';

  @override
  String get statisticsHeatmapTitle => 'Календарь повторений';

  @override
  String statisticsChartSemantics(int count) {
    return 'Повторений за год: $count';
  }

  @override
  String get statisticsWeekTitle => 'Недельный прогресс';

  @override
  String statisticsWeekSemantics(int count) {
    return 'Повторений за неделю: $count';
  }

  @override
  String get statisticsWeakTopicsTitle => 'Слабые темы';

  @override
  String get statisticsWeakTopicsEmpty => 'Слабых тем пока нет';

  @override
  String statisticsWeakTopicStats(int errors, int reviews) {
    return '$errors из $reviews с ошибкой';
  }

  @override
  String get statisticsWeakTopicTrain => 'Тренировать';

  @override
  String get statisticsForecastTitle => 'Прогноз нагрузки на 7 дней';

  @override
  String get statisticsForecastToday => 'Сегодня';

  @override
  String get statisticsForecastTomorrow => 'Завтра';

  @override
  String statisticsForecastCount(int count) {
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
  String statisticsForecastSemantics(String day, int count) {
    return '$day: $count';
  }

  @override
  String get statisticsErrorTitle => 'Не удалось загрузить статистику';

  @override
  String get statisticsEmptyTitle =>
      'Статистика появится после первых повторений';

  @override
  String get statisticsEmptyMessage =>
      'Повторите карточки — здесь появятся удержание, календарь, слабые темы и прогноз.';

  @override
  String get settingsScreenTitle => 'Настройки';

  @override
  String get settingsAppearanceTitle => 'Внешний вид';

  @override
  String get settingsThemeTitle => 'Тема';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeSystem => 'Системная';

  @override
  String get settingsDynamicColor => 'Динамические цвета';

  @override
  String get settingsDynamicColorHint =>
      'Цвета системы, если платформа их поддерживает';

  @override
  String get settingsMotionTitle => 'Анимация';

  @override
  String get settingsMotionExpressive => 'Выразительная';

  @override
  String get settingsMotionStandard => 'Стандартная';

  @override
  String get settingsDyslexiaFont => 'Шрифт для дислексии';

  @override
  String get settingsTextScaleTitle => 'Размер шрифта';

  @override
  String settingsTextScaleValue(int percent) {
    return '$percent%';
  }

  @override
  String get settingsHighContrast => 'Повышенный контраст';

  @override
  String get settingsRetentionTitle => 'Желаемое удержание';

  @override
  String settingsRetentionValue(int percent) {
    return '$percent%';
  }

  @override
  String get settingsLearningStepsTitle => 'Шаги обучения';

  @override
  String settingsLearningStepValue(int minutes) {
    return '$minutes мин';
  }

  @override
  String get settingsLearningStepAdd => 'Добавить шаг';

  @override
  String get settingsLearningStepDeleteTooltip => 'Удалить шаг';

  @override
  String get settingsLearningStepDialogTitle => 'Новый шаг обучения';

  @override
  String get settingsLearningStepDialogLabel => 'Длительность, мин';

  @override
  String get settingsLearningStepInvalid => 'Введите число от 1 до 60';

  @override
  String get settingsLearningStepLimit => 'Не больше 5 шагов';

  @override
  String get settingsDailyNewLimitTitle => 'Новых в день';

  @override
  String get settingsDailyReviewLimitTitle => 'Повторных в день';

  @override
  String get settingsDailyLimitZeroHint => '0 — без ограничения';

  @override
  String get settingsAccessibilityTitle => 'Доступность';

  @override
  String get settingsHapticsTitle => 'Тактильная отдача';

  @override
  String get settingsHapticsHint => 'Вибрация при оценке карточек';

  @override
  String get settingsApiTitle => 'API';

  @override
  String get settingsApiCheckMissing => 'Сначала добавьте ключ';

  @override
  String get settingsApiCheckNoConnection => 'Нет подключения к интернету';

  @override
  String get settingsApiCheckRateLimited =>
      'Превышен лимит запросов. Попробуйте позже';

  @override
  String get settingsApiCheckNotConfigured =>
      'Сервер не настроен. Укажите адрес и модель';

  @override
  String get settingsApiCheckUnexpected =>
      'Не удалось проверить ключ. Попробуйте ещё раз';

  @override
  String settingsApiTokensWeek(String count) {
    return 'Токенов за неделю: $count';
  }

  @override
  String get settingsApiOpenGeneration => 'Провайдеры и ключи';

  @override
  String get providersTitle => 'Провайдеры';

  @override
  String get providersDescription =>
      'Ключи хранятся в защищённом хранилище устройства и не показываются. Генерация использует основного провайдера';

  @override
  String get providersEmptyTitle => 'Провайдеры не настроены';

  @override
  String get providersEmptyDescription =>
      'Добавьте провайдера, чтобы генерировать карточки';

  @override
  String get providersAdd => 'Добавить провайдера';

  @override
  String get providersAddPreset => 'Сторонний поставщик';

  @override
  String get providersAddPresetSubtitle => 'Выбрать из каталога';

  @override
  String get providersAddCustom => 'Пользовательская модель API';

  @override
  String get providersAddCustomSubtitle => 'Свой адрес, протокол и имя модели';

  @override
  String get providersEditTitle => 'Изменить провайдера';

  @override
  String get providersPresetLabel => 'Поставщик';

  @override
  String get providersProtocolLabel => 'Протокол';

  @override
  String get providersNameLabel => 'Название';

  @override
  String get providersNameEmptyError => 'Укажите название';

  @override
  String get providersModelHint => 'Имя модели на сервере';

  @override
  String get providersVisionLabel => 'Модель принимает изображения';

  @override
  String get providersVisionHint =>
      'Включайте, если модель понимает картинки и сканы';

  @override
  String get providersVisionSupported => 'Принимает изображения';

  @override
  String get providersVisionNotSupported => 'Только текст';

  @override
  String get providersBaseUrlHint =>
      'Полный адрес; версию укажите в пути, если сервер её требует';

  @override
  String get providersIncompleteHint =>
      'Заполните адрес и модель, чтобы пользоваться провайдером';

  @override
  String get providersKeyNotRequired => 'Ключ не требуется';

  @override
  String get providersKeyHelper =>
      'Ключ хранится в защищённом хранилище и не показывается';

  @override
  String get providersKeyKeep =>
      'Оставьте пустым, чтобы не менять сохранённый ключ';

  @override
  String get providersKeyOptionalHint =>
      'Можно не заполнять: провайдер работает без ключа';

  @override
  String get providersKeyUndoDelete => 'Оставить сохранённый ключ';

  @override
  String providersActiveSaved(String name) {
    return 'Основной провайдер: $name';
  }

  @override
  String get providersActive => 'Основной';

  @override
  String get providersMakeActive => 'Сделать основным';

  @override
  String get providersCheck => 'Проверить подключение';

  @override
  String get providersCheckValid => 'Подключение работает';

  @override
  String get providersCheckInvalid => 'Ошибка ключа. Проверьте ключ доступа';

  @override
  String get providersEdit => 'Изменить';

  @override
  String get providersDelete => 'Удалить';

  @override
  String get providersDeleteTitle => 'Удалить провайдера?';

  @override
  String get providersDeleteBody =>
      'Настройки провайдера и сохранённый ключ будут удалены';

  @override
  String get providersDeleted => 'Провайдер удалён';

  @override
  String get providersSaved => 'Провайдер сохранён';

  @override
  String get providersSaveError =>
      'Не удалось сохранить провайдера. Попробуйте ещё раз';

  @override
  String get providersKeyStoreError =>
      'Не удалось сохранить ключ в защищённом хранилище. Попробуйте ещё раз';

  @override
  String get providersProtocolOpenAi => 'OpenAI-совместимый';

  @override
  String get providersProtocolAnthropic => 'Anthropic (сообщения)';

  @override
  String get providersProtocolGemini => 'Gemini';

  @override
  String get generationModelProviderHint =>
      'Модель задаётся в настройках провайдера';

  @override
  String get settingsAboutTitle => 'О приложении';

  @override
  String settingsAboutVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get settingsAboutLicenses => 'Лицензии';

  @override
  String get settingsAboutPrivacy => 'Политика приватности';

  @override
  String get settingsAboutLinkError => 'Не удалось открыть ссылку';

  @override
  String get cardImageSemantics => 'Изображение карточки';

  @override
  String get cardImageUnavailable => 'Изображение недоступно';

  @override
  String get cardImageLoadFailed => 'Не удалось показать изображение';

  @override
  String get cardImageFullscreenTitle => 'Изображение';

  @override
  String get cardImageFullscreenClose => 'Закрыть';

  @override
  String cardImageAttribution(String attribution) {
    return 'Источник: $attribution';
  }

  @override
  String cardImageSourceUrl(String url) {
    return 'Ссылка: $url';
  }

  @override
  String get cardImageRetryAction => 'Найти картинку заново';

  @override
  String get cardImageRetrySuccess => 'Картинка обновлена';

  @override
  String get cardImageRetryNotFound => 'Картинку не нашли — осталась прежняя';

  @override
  String get cardImageRetryNoQuery => 'Нет сохранённого запроса для поиска';

  @override
  String get cardImageRetryError => 'Не удалось обновить картинку';

  @override
  String generationLiveCardsTitle(int count) {
    return 'Карточки готовы: $count';
  }

  @override
  String get generationLiveImagesPending => 'Догружаем картинки…';

  @override
  String get reviewModeTest => 'Тест';

  @override
  String get reviewModeTyping => 'Ввод ответа';

  @override
  String get studyModeTestSubtitle => 'Четыре варианта ответа';

  @override
  String get studyModeTypingSubtitle => 'Вспомни и введи ответ';

  @override
  String studyModeAvailableCount(int count) {
    return 'Доступно карточек: $count';
  }

  @override
  String get studyModeNotEnough => 'Мало подходящих карточек';

  @override
  String testProgressSemantics(int current, int total) {
    return 'Вопрос $current из $total';
  }

  @override
  String get testNext => 'Далее';

  @override
  String get testResultsTitle => 'Тест завершён';

  @override
  String testAccuracy(int percent) {
    return 'Точность: $percent%';
  }

  @override
  String testErrorsCount(int count) {
    return 'Ошибок: $count';
  }

  @override
  String get testRepeatMistakes => 'Повторить ошибки';

  @override
  String get testEmptyTitle => 'Нет карточек для теста';

  @override
  String get testEmptyMessage =>
      'Для теста нужны карточки с коротким ответом и хотя бы четырьмя подходящими вариантами в колоде.';

  @override
  String testOptionLabel(int index, String answer) {
    return 'Вариант $index: $answer';
  }

  @override
  String get testQuestionLabel => 'Вопрос';

  @override
  String get typingTitle => 'Ввод ответа';

  @override
  String get typingInputLabel => 'Введите ответ';

  @override
  String get typingCheck => 'Проверить';

  @override
  String get typingCorrect => 'Верно';

  @override
  String get typingAlmost => 'Почти! Проверь написание';

  @override
  String get typingWrong => 'Неверно';

  @override
  String typingRightAnswer(String answer) {
    return 'Правильный ответ: $answer';
  }

  @override
  String get typingIWasRight => 'Я был прав';

  @override
  String get typingShowAnswer => 'Показать ответ';

  @override
  String get typingNext => 'Далее';

  @override
  String get typingInputSemantics => 'Поле ввода ответа';

  @override
  String get typingEmptyTitle => 'Нет карточек для ввода ответа';

  @override
  String get typingEmptyMessage =>
      'Нужны карточки с коротким ответом (до 60 символов, без формул и переносов строк).';

  @override
  String studyResultsScore(int total, int correct) {
    return 'Верно: $correct из $total';
  }

  @override
  String get studyWrongListTitle => 'Ошибки';

  @override
  String get reviewModeMatch => 'Подбор пар';

  @override
  String get reviewModeTrueFalse => 'Верно/Неверно';

  @override
  String get studyModeMatchSubtitle => 'Найди пары вопрос-ответ';

  @override
  String get studyModeTrueFalseSubtitle => 'Ответ верный или нет?';

  @override
  String get studyModeMatchNotEnough =>
      'Нужно минимум 6 карточек с вопросом и ответом';

  @override
  String get studyModeTrueFalseNotEnough =>
      'Нужен хотя бы один другой ответ в колоде';

  @override
  String get matchTitle => 'Подбор пар';

  @override
  String matchTimer(String time) {
    return 'Время: $time с';
  }

  @override
  String matchBest(String time) {
    return 'Лучшее время: $time';
  }

  @override
  String matchMoves(int count) {
    return 'Ходов: $count';
  }

  @override
  String get matchCompletedTitle => 'Все пары найдены';

  @override
  String get matchRestart => 'Ещё раз';

  @override
  String get matchDone => 'Готово';

  @override
  String get matchEmptyTitle => 'Мало карточек для пар';

  @override
  String get matchEmptyMessage =>
      'Нужно минимум 6 карточек с непустым вопросом и ответом.';

  @override
  String get trueFalseTitle => 'Верно/Неверно';

  @override
  String trueFalseStatement(String answer) {
    return 'Утверждение: $answer';
  }

  @override
  String get trueFalseTrueAction => 'Верно';

  @override
  String get trueFalseFalseAction => 'Неверно';

  @override
  String get trueFalseCorrect => 'Верно!';

  @override
  String get trueFalseWrong => 'Ошибка';

  @override
  String trueFalseExplanation(String answer) {
    return 'Правильный ответ: $answer';
  }

  @override
  String get trueFalseSwipeHint => 'Свайп вправо — верно, влево — неверно';

  @override
  String get trueFalseNext => 'Далее';

  @override
  String get trueFalseEmptyTitle => 'Нет карточек для режима';

  @override
  String get trueFalseEmptyMessage =>
      'Нужны карточки с ответом и хотя бы один другой ответ в колоде.';

  @override
  String get navAi => 'ИИ-генерация';

  @override
  String get navConstructor => 'Конструктор';

  @override
  String get shellSearchHint => 'Поиск карточек...';

  @override
  String get shellNavSection => 'Навигация';

  @override
  String shellBreadcrumb(String section) {
    return 'Рабочее пространство / $section';
  }

  @override
  String get shellNewCard => 'Новая карточка';

  @override
  String shellDueToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count карточки к повторению',
      many: '$count карточек к повторению',
      few: '$count карточки к повторению',
      one: '$count карточка к повторению',
      zero: 'Нет карточек к повторению',
    );
    return '$_temp0';
  }

  @override
  String get shellDueLabel => 'К повторению';

  @override
  String shellVersion(String version) {
    return '$version';
  }

  @override
  String get shellOpenNavTooltip => 'Открыть навигацию';

  @override
  String get shellCloseNavTooltip => 'Закрыть навигацию';

  @override
  String get shellOpenSettingsTooltip => 'Открыть настройки';

  @override
  String get shellSearchTooltip => 'Найти колоду или карточку';

  @override
  String get shellNewCardSheetTitle => 'Новая карточка';

  @override
  String get shellNewCardSheetSubtitle =>
      'Выберите колоду, в которую добавить карточку';

  @override
  String get shellNewCardNoDecks => 'Сначала создайте колоду';

  @override
  String get decksOverline => 'Интервальное повторение';

  @override
  String decksSubtitle(int decks, int due) {
    String _temp0 = intl.Intl.pluralLogic(
      decks,
      locale: localeName,
      other: '$decks активные колоды',
      many: '$decks активных колод',
      few: '$decks активные колоды',
      one: '$decks активная колода',
    );
    String _temp1 = intl.Intl.pluralLogic(
      due,
      locale: localeName,
      other: '$due карточки',
      many: '$due карточек',
      few: '$due карточки',
      one: '$due карточка',
    );
    return '$_temp0 · $_temp1 на повторение сегодня';
  }

  @override
  String decksSubtitleDecks(int decks) {
    String _temp0 = intl.Intl.pluralLogic(
      decks,
      locale: localeName,
      other: '$decks колоды',
      many: '$decks колод',
      few: '$decks колоды',
      one: '$decks колода',
    );
    return '$_temp0 в работе';
  }

  @override
  String get decksMetricTotal => 'Всего карточек';

  @override
  String get decksMetricDue => 'К повторению сегодня';

  @override
  String get decksMetricStudied => 'Изучено';

  @override
  String get decksMetricDecks => 'Колод';

  @override
  String get decksProgressLabel => 'Изучено';

  @override
  String get decksImportButton => 'Импорт';

  @override
  String get decksSortTooltip => 'Сортировка';

  @override
  String get decksSortName => 'По названию';

  @override
  String get decksSortProgress => 'По прогрессу';

  @override
  String get decksSortCards => 'По объёму';

  @override
  String get decksSortDue => 'По срочности';

  @override
  String get decksViewGrid => 'Сетка';

  @override
  String get decksViewList => 'Список';

  @override
  String get decksNewDeck => 'Новая колода';

  @override
  String get decksFilterAll => 'Все';

  @override
  String get decksFilterNew => 'Новые';

  @override
  String get decksFilterInProgress => 'В процессе';

  @override
  String get decksFilterDue => 'Срок наступил';

  @override
  String decksFilterMenuItem(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get deckNewBadge => 'Новая колода';

  @override
  String get deckAllReviewed => 'Все повторено';

  @override
  String get deckStudyAction => 'Учить';

  @override
  String get deckStartAction => 'Начать';

  @override
  String get deckReviewAction => 'Просмотр';

  @override
  String deckUpdated(String date) {
    return 'Обновлена $date';
  }

  @override
  String get deckOverline => 'Колода';

  @override
  String get deckCardsTitle => 'Карточки';

  @override
  String get deckStudyModesTitle => 'Режимы обучения';

  @override
  String get deckAddCard => 'Добавить карточку';

  @override
  String get deckProgressTitle => 'Прогресс изучения';

  @override
  String deckCreated(String date) {
    return 'Создана $date';
  }

  @override
  String get deckMoreActions => 'Действия';

  @override
  String reviewCardCounter(int current, int total) {
    return 'Карточка $current из $total';
  }

  @override
  String reviewRatedCount(int count) {
    return 'Оценено: $count';
  }

  @override
  String get reviewRevealAction => 'Показать ответ';

  @override
  String get reviewFsrsBadge => 'FSRS';

  @override
  String get generationPageTitle => 'Генерация карточек с помощью ИИ';

  @override
  String get generationOverline => 'Нейросетевой модуль';

  @override
  String get generationSubtitle =>
      'Превратите лекции, конспекты или статьи в готовые колоды с интервальным повторением';

  @override
  String get generationSectionMaterials => '1. Загрузка исходных материалов';

  @override
  String get generationSectionParameters => '2. Параметры колоды';

  @override
  String get generationSectionModel => '3. Модель и параметры';

  @override
  String generationFilesCount(int count) {
    return 'Всего файлов: $count';
  }

  @override
  String get generationBackTooltip => 'Назад';

  @override
  String get statisticsOverline => 'Аналитический центр';

  @override
  String get statisticsSubtitle =>
      'Отслеживание прогресса, эффективности интервального повторения и темпа обучения';

  @override
  String get statisticsKpiStreak => 'Текущая серия';

  @override
  String statisticsDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дня',
      many: '$count дней',
      few: '$count дня',
      one: '$count день',
    );
    return '$_temp0';
  }

  @override
  String get statisticsKpiRetention => 'Удержание';

  @override
  String get statisticsRetentionWindow => 'за 30 дней';

  @override
  String get statisticsKpiReviews => 'Повторений за год';

  @override
  String get statisticsKpiActiveDays => 'Дней активности';

  @override
  String statisticsActiveDaysValue(int done, int total) {
    return '$done из $total';
  }

  @override
  String statisticsGoal(int percent) {
    return 'Цель: $percent%';
  }

  @override
  String statisticsHeatmapSummary(int active, int total) {
    return '$active дней активности из $total';
  }

  @override
  String get statisticsLegendLess => 'Меньше';

  @override
  String get statisticsLegendMore => 'Больше';

  @override
  String get statisticsWeakTopicsSubtitle => 'Темы с высокой долей ошибок';

  @override
  String get statisticsForecastSubtitle =>
      'Запланированные повторения на основе расписания FSRS';

  @override
  String get settingsOverline => 'Конфигурация';

  @override
  String get settingsSubtitle =>
      'Управление алгоритмом интервального повторения, внешним видом и параметрами генерации';

  @override
  String get settingsNavLearning => 'Обучение и FSRS';

  @override
  String get settingsNavAppearance => 'Оформление';

  @override
  String get settingsNavAccessibility => 'Доступность';

  @override
  String get settingsNavAi => 'ИИ и модели';

  @override
  String get settingsNavAbout => 'О приложении';

  @override
  String get settingsFsrsTitle => 'Алгоритм интервального повторения (FSRS)';

  @override
  String get settingsLearningSubtitle =>
      'Модель интервалов памяти на основе FSRS';

  @override
  String get settingsRetentionHint =>
      'Рекомендуется 85–92% для баланса времени и прочности';

  @override
  String get settingsLearningStepsHint => 'Интервалы первого изучения карточки';

  @override
  String get settingsDailyLimitsTitle => 'Дневные лимиты';

  @override
  String get settingsDailyNewLimitHint =>
      'Сколько новых карточек показывать за день';

  @override
  String get settingsDailyReviewLimitHint =>
      'Сколько повторений показывать за день';

  @override
  String get settingsAppearanceSubtitle =>
      'Настройка темы оформления, типографики и плотности интерфейса';

  @override
  String get settingsThemeHint => 'Светлая, тёмная или системная тема';

  @override
  String get settingsMotionHint => 'Характер анимаций интерфейса';

  @override
  String get settingsAccessibilitySubtitle =>
      'Отклик, контраст и шрифт для чтения';

  @override
  String get settingsTextScaleHint =>
      'Размер интерфейса относительно системного';

  @override
  String get settingsAiSubtitle => 'Аккаунты провайдеров и расход токенов';

  @override
  String get settingsAboutSubtitle => 'Версия, лицензии и политика приватности';

  @override
  String get settingsCapabilitiesTitle => 'Характеристики модели';

  @override
  String get settingsCapabilitiesDescription =>
      'Лимиты с источником и датой проверки. «Изменить» задаёт значения вручную; «Обновить» запрашивает данные у провайдера; «Сбросить» возвращает автоматические значения каталога.';

  @override
  String get settingsCapabilitiesContext => 'Контекст';

  @override
  String get settingsCapabilitiesOutput => 'Лимит вывода';

  @override
  String get settingsCapabilitiesInput => 'Лимит входа';

  @override
  String get settingsCapabilitiesEdit => 'Изменить';

  @override
  String get settingsCapabilitiesEditTitle => 'Характеристики модели';

  @override
  String get settingsCapabilitiesEditHelp =>
      'Пустое поле — автоматическое значение (каталог или API) либо «неизвестно». Ручные значения имеют приоритет и сохраняются в аккаунте.';

  @override
  String get settingsCapabilitiesSave => 'Сохранить';

  @override
  String get settingsCapabilitiesCancel => 'Отмена';

  @override
  String get settingsCapabilitiesSaved => 'Характеристики сохранены.';

  @override
  String get settingsCapabilitiesInvalid =>
      'Введите положительное целое число или оставьте поле пустым.';

  @override
  String get settingsCapabilitiesImages => 'Изображений в запросе';

  @override
  String get settingsCapabilitiesImageInput => 'Вход изображений';

  @override
  String get settingsCapabilitiesImageInputYes => 'поддерживается';

  @override
  String get settingsCapabilitiesImageInputNo => 'не поддерживается';

  @override
  String get settingsCapabilitiesUnknown => 'неизвестно';

  @override
  String get settingsCapabilitiesLoadFailed =>
      'Не удалось прочитать характеристики модели.';

  @override
  String get settingsCapabilitiesSourceUser => 'задано вручную';

  @override
  String get settingsCapabilitiesSourceApi => 'из API провайдера';

  @override
  String get settingsCapabilitiesSourceCatalog => 'каталог приложения';

  @override
  String get settingsCapabilitiesSourceAssumption => 'допущение приложения';

  @override
  String get settingsCapabilitiesRefresh => 'Обновить характеристики';

  @override
  String get settingsCapabilitiesRefreshDone => 'Характеристики обновлены.';

  @override
  String get settingsCapabilitiesRefreshFailed =>
      'Не удалось обновить характеристики.';

  @override
  String get settingsCapabilitiesReset => 'Сбросить к автоматическому';

  @override
  String get settingsCapabilitiesResetDone =>
      'Значения сброшены к автоматическим.';

  @override
  String settingsCapabilitiesCheckedAt(String date) {
    return 'проверено $date';
  }

  @override
  String get reviewRevealRequiredHint => 'Оценки откроются после показа ответа';

  @override
  String get reviewQuestionLabel => 'Вопрос';

  @override
  String get reviewAnswerLabel => 'Ответ';

  @override
  String get reviewKeyboardHints => '1–4 — оценка · ← — отменить';

  @override
  String get reviewKeyboardHintsRating => '1–4 — оценка';

  @override
  String get reviewHomeTooltip => 'Мои колоды';

  @override
  String get sessionNoticeDismiss => 'Скрыть сообщение';

  @override
  String get cardFormUnsavedTitle => 'Выйти без сохранения?';

  @override
  String get cardFormUnsavedMessage => 'Изменения в карточке не сохранены.';

  @override
  String get cardFormUnsavedSave => 'Сохранить и выйти';

  @override
  String get cardFormUnsavedDiscard => 'Не сохранять';

  @override
  String get cardFormValidationSummary =>
      'Проверьте отмеченные поля: есть ошибки.';

  @override
  String get cardFormPreviewTitle => 'Предпросмотр';

  @override
  String cardFormClozeHint(String example) {
    return 'Пометьте пропуск в тексте: $example — часть в скобках скроется до показа ответа. Номер можно не указывать.';
  }

  @override
  String get deckStartNeedsCards => 'Сначала добавьте карточки';

  @override
  String get deckEmptySnack => 'В колоде нет карточек';

  @override
  String get deckDailyLimitNotice =>
      'Дневной лимит на сегодня исчерпан. Карточки откроются завтра, либо продолжите без лимита.';

  @override
  String get deckCountersNote =>
      '«В процессе» — все начатые карточки, включая «К повторению».';

  @override
  String decksNoResultsForQuery(String query) {
    return 'Ничего не найдено по запросу «$query»';
  }

  @override
  String get decksSearchResetAction => 'Сбросить поиск';

  @override
  String get decksFilterEmptyHint => 'Измените запрос или сбросьте фильтр.';

  @override
  String get deckImportPickerTitle => 'Выберите ZIP-архив колоды';

  @override
  String get deckExportPickerTitle => 'Сохранить ZIP-архив колоды';

  @override
  String get deckImportCancelled => 'Импорт отменён';

  @override
  String get deckSearchCardsHint => 'Поиск по карточкам';

  @override
  String get deckFilterAll => 'Все';

  @override
  String get deckFilterDue => 'К повторению';

  @override
  String get deckFilterNew => 'Новые';

  @override
  String get deckFilterLearning => 'В процессе';

  @override
  String get deckCardsNoMatches => 'Нет карточек, подходящих под фильтр';

  @override
  String get deckCardMenuTooltip => 'Действия с карточкой';

  @override
  String get deckCardEdit => 'Изменить';

  @override
  String get deckCardDelete => 'Удалить карточку';

  @override
  String get deckCardDeleteTitle => 'Удалить карточку?';

  @override
  String get deckCardDeleteMessage =>
      'Карточка будет удалена без возможности восстановления.';

  @override
  String get reviewModeClassicSubtitle =>
      'По расписанию FSRS: вопрос, ответ и прогноз интервала';

  @override
  String get reviewModeFeedSubtitle =>
      'Свободный просмотр: вертикальная лента без оценки и влияния на расписание';

  @override
  String studyModeTestNotEnough(int count) {
    return 'Нужна хотя бы одна карточка с вариантами ответа, сейчас $count';
  }

  @override
  String studyModeTypingNotEnough(int count) {
    return 'Нужна хотя бы одна карточка с коротким ответом, сейчас $count';
  }

  @override
  String statisticsRetentionLowSample(int count) {
    return 'Мало данных: повторений за 30 дней — $count';
  }

  @override
  String statisticsRetentionBasedOn(int count) {
    return 'на основе $count повторений за 30 дней';
  }

  @override
  String get statisticsRetentionThreshold =>
      'Процент показывается от 20 повторений за 30 дней';

  @override
  String get statisticsForecastEmpty =>
      'На ближайшие 7 дней повторений не запланировано';

  @override
  String get statisticsWeekEmpty => 'За эту неделю повторений ещё не было';

  @override
  String statisticsWeekTotal(int count) {
    return 'Всего за неделю: $count';
  }

  @override
  String statisticsChartBarSemantics(String label, int count) {
    return '$label: $count';
  }

  @override
  String get settingsProvidersPrimaryBroken =>
      'Основной провайдер не настроен: укажите адрес и модель.';

  @override
  String get settingsProvidersFixAction => 'Исправить';

  @override
  String get settingsProvidersCannotBePrimary =>
      'Сначала заполните адрес и модель — такой провайдер не может быть основным.';

  @override
  String get generationExitRunningTitle => 'Остановить генерацию?';

  @override
  String get generationExitRunningMessage =>
      'Карточки ещё генерируются. Если выйти сейчас, несохранённые карточки пропадут.';

  @override
  String get generationExitRunningConfirm => 'Остановить и выйти';

  @override
  String get generationExitRunningStay => 'Продолжить генерацию';

  @override
  String get generationDiscardTitle => 'Выйти без сохранения?';

  @override
  String get generationDiscardMessage =>
      'Введённые материалы и пожелания не сохранены.';

  @override
  String get generationDiscardStay => 'Продолжить';

  @override
  String get generationDiscardExit => 'Выйти';

  @override
  String generationModelFromSettings(String model) {
    return 'Модель: $model';
  }

  @override
  String get generationModelChange => 'Изменить';

  @override
  String get shellSearchAction => 'Найти колоду';

  @override
  String get shellSearchActionHint => 'Откроет поиск в списке колод';

  @override
  String get deckModesGroupReview => 'Повторение';

  @override
  String get deckModesGroupCheck => 'Проверка';

  @override
  String get deckModesGroupCustom => 'Настройка';

  @override
  String get constructorSubtitle => 'Свои колоды, фильтры и лимит сессии';

  @override
  String statisticsDaysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дня',
      many: 'дней',
      few: 'дня',
      one: 'день',
    );
    return '$_temp0';
  }

  @override
  String get reviewKeyboardHintsFront => 'Пробел — показать ответ';

  @override
  String constructorTagsMore(int count) {
    return 'Ещё $count';
  }

  @override
  String get sessionExitFeedMessage =>
      'Выйти из просмотра? Прогресс просмотра не сохраняется, расписание повторений остаётся прежним.';

  @override
  String get sessionExitPracticeMessage =>
      'Выйти из тренировки? Поставленные оценки уже сохранены, расписание не изменилось.';

  @override
  String get sessionExitStudyMessage =>
      'Выйти из проверки? Ответы уже сохранены.';

  @override
  String get reviewSummaryTitle => 'Итог сессии';

  @override
  String reviewSummaryDuration(String duration) {
    return 'Время: $duration';
  }

  @override
  String reviewSummaryAccuracy(int percent) {
    return 'Без ошибок: $percent %';
  }

  @override
  String get reviewAgainAction => 'Ещё раз';

  @override
  String get reviewToDeckAction => 'К карточкам';

  @override
  String get feedNavHintTouch => 'Свайп ↑↓ — листать карточки';

  @override
  String get feedBrowseBadgeV2 => 'Лента';

  @override
  String decksMetricDecksLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'колоды',
      many: 'колод',
      few: 'колоды',
      one: 'колода',
    );
    return '$_temp0';
  }

  @override
  String get decksWelcomeTitle => 'Добро пожаловать в CardFlow';

  @override
  String get decksWelcomeMessage =>
      'Создайте первую колоду, импортируйте готовую или сгенерируйте карточки из конспекта.';

  @override
  String get decksWelcomeAiNote =>
      'ИИ не настроен — карточки можно создавать вручную. Провайдер подключается в любой момент.';

  @override
  String get decksWelcomeAiAction => 'Настроить ИИ';

  @override
  String deckProgressCounts(int studied, int total) {
    return '$studied из $total изучено';
  }

  @override
  String get deckSearchClear => 'Сбросить поиск';

  @override
  String get generationCardsCountHelper =>
      'Пусто — авто: столько, сколько позволяет материал. Большие заказы идут партиями.';

  @override
  String generationCardsCountPreset(int count) {
    return '$count';
  }

  @override
  String get generationSelectCard => 'Выбрать карточку';

  @override
  String get generationImagesAutoTitle => 'Изображения подобраны автоматически';

  @override
  String get generationImagesAutoMessage =>
      'Проверьте, подходят ли иллюстрации к карточкам: поиск работает по описанию и может ошибаться.';

  @override
  String get generationRemoveAllImages => 'Убрать все изображения';

  @override
  String get generationImagesRemoved => 'Изображения убраны';

  @override
  String generationFilesAttached(int count) {
    return 'Прикреплено файлов: $count';
  }

  @override
  String get providersCheckInlineOk => 'Подключение работает';

  @override
  String get providersCheckInlineFail => 'Подключиться не удалось';

  @override
  String get providersDeleteKey => 'Удалить ключ';

  @override
  String get providersSheetSubtitle =>
      'Пресет подставит адрес и модели, кастомный профиль — свои.';

  @override
  String get settingsHapticsDesktopHint => 'Вибрация есть только на телефоне';

  @override
  String get settingsDyslexiaHint =>
      'Шрифт для дислексии применяется ко всему интерфейсу';

  @override
  String statisticsCalendarYearShare(int percent) {
    return '$percent % года';
  }

  @override
  String statisticsDayTooltip(String date, int count) {
    return '$date · повторений: $count';
  }

  @override
  String get studyChooseOne => 'Выберите один ответ';

  @override
  String get studyFeedbackCorrect => 'Верно';

  @override
  String get studyFeedbackIncorrect => 'Неверно';

  @override
  String get studyCorrectAnswerLabel => 'Правильный ответ';

  @override
  String matchTimeSeconds(String seconds) {
    return 'Время: $seconds с';
  }

  @override
  String matchTimeMinutes(int minutes, String seconds) {
    return 'Время: $minutes мин $seconds с';
  }

  @override
  String matchProgress(int done, int total) {
    return 'Пары: $done из $total';
  }

  @override
  String get matchExitTitle => 'Выйти из подбора пар?';

  @override
  String get matchExitMessage =>
      'Прогресс игры не сохранится, карточки останутся в колоде.';

  @override
  String get generationPreviewRemoveShort => 'Удалить';

  @override
  String get generationPreviewReplaceShort => 'Заменить';

  @override
  String generationPreviewImageNumber(int index) {
    return 'Изображение $index';
  }

  @override
  String get reviewFsrsTooltip => 'Интервальное повторение по алгоритму FSRS';

  @override
  String get appInfoClose => 'Понятно';

  @override
  String get appInfoTooltip => 'Подробнее';

  @override
  String get cardFormMoreSection => 'Дополнительно';

  @override
  String get cardFormMoreSectionHint => 'Подсказка, теги и источник';

  @override
  String get cardFormImageInfoTitle => 'Изображения на карточке';

  @override
  String get cardFormTypeInfoTitle => 'Тип карточки';

  @override
  String get practiceInfoTooltip => 'Без FSRS';

  @override
  String reviewCardCounterShort(int current, int total) {
    return '$current / $total';
  }

  @override
  String get feedEndTitle => 'Лента пройдена';

  @override
  String feedEndMessage(int count) {
    return 'Просмотрено карточек: $count. Расписание повторений не изменилось.';
  }

  @override
  String get feedAnswerNavHint => 'Свайп ↑↓ · тап — вопрос';
}
