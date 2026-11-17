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
  String decksSummary(Object decks, Object due) {
    return 'К повторению: $due · колод: $decks';
  }

  @override
  String get decksNoResultsHint => 'Попробуйте изменить запрос или фильтр.';

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
  String get reviewModeSheetTitle => 'Режим сессии';

  @override
  String deckCardsSection(Object count) {
    return 'КАРТОЧКИ · $count';
  }

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
  String cardFormSyntaxHint(Object cloze, Object latex) {
    return 'Синтаксис: $cloze — пропуск, $latex — формула';
  }

  @override
  String get cardFormPreview => 'Предпросмотр';

  @override
  String get cardFormPreviewToggle => 'Свернуть или развернуть предпросмотр';

  @override
  String get cardFormTagsPreview => 'Теги';

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
  String get parserErrorEmptyText =>
      'В файле нет текста (скан или пустая форма)';

  @override
  String get parserErrorGarbledText =>
      'PDF содержит нечитаемый текст. Сохраните файл в другом формате и попробуйте снова';

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
      'Файл больше 10 МБ. Уменьшите файл и попробуйте снова';

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
  String get settingsOpenTooltip => 'Настройки';

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
  String get generationTitle => 'Генерация карточек';

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
      'Картинка показывается вместе с вопросом и ответом. Маски нужны, только если части изображения надо скрыть.';

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
  String get settingsLearningTitle => 'Обучение';

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
  String get settingsApiProvidersTitle => 'Провайдеры';

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
  String settingsApiTokensWeek(int count) {
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
  String get cardImagePlaceholderSemantics => 'Временная картинка карточки';

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
    return 'Время: $time';
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
    return 'Ответ: $answer';
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
  String get commonLoading => 'Загрузка';

  @override
  String get commonClose => 'Закрыть';
}
