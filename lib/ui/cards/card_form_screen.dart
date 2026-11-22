import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_image_refresh_result.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/cards/occlusion_mask_editor.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Результат работы формы карточки (для сообщений на экране колоды).
enum CardFormResult {
  /// Карточка создана.
  created,

  /// Изменения сохранены.
  updated,

  /// Карточка удалена.
  deleted,
}

/// Одно изображение в редакторе: существующее медиа или новый файл.
///
/// Итерация 7.19 (ADR-042): изображения вопроса и ответа — независимые
/// упорядоченные списки; элемент помнит своё место и может быть перенесён.
class _MediaItem {
  _MediaItem.stored(String this.mediaId) : upload = null, uploadSequence = null;

  _MediaItem.upload(CardImageUpload this.upload)
    : mediaId = null,
      uploadSequence = ++_uploadCounter;

  static int _uploadCounter = 0;

  /// `media.id` существующего изображения; `null` — новый файл.
  final String? mediaId;

  /// Новый файл, который сохранит репозиторий.
  final CardImageUpload? upload;

  /// Номер новой загрузки в рамках экрана (для стабильного ключа).
  final int? uploadSequence;

  /// Прочитанные байты; `null` — файл недоступен (явное состояние, не подмена).
  Uint8List? bytes;

  /// Метаданные атрибуции существующего изображения.
  MediaMetadata? metadata;

  /// Стабильный ключ элемента в дереве (id или номер загрузки).
  String get key => mediaId ?? 'upload-${uploadSequence ?? 0}';

  /// Запрос модели для «Найти картинку заново».
  String? get query => metadata?.query;

  bool get isStored => mediaId != null;

  Uint8List? get uploadBytes => upload?.bytes;
}

/// Выбор при выходе с несохранёнными правками (находка N2).
enum _UnsavedChoice {
  /// Сохранить правки и выйти.
  save,

  /// Выйти без сохранения.
  discard,
}

/// Экран создания/редактирования карточки (SPEC A6.3, ADR-009).
///
/// Поля: front (обязателен, ≤500), back (обязателен, ≤2000), hint, теги (≤3),
/// тип (`basic`/`basic_reversed`/`cloze`, при редактировании неизменяем),
/// `source_excerpt` для кнопки «Почему?», независимые изображения вопроса и
/// ответа и (необязательно) маски Image Occlusion.
///
/// ADR-028: изображение можно привязать к карточке любого типа. ADR-042:
/// стороны независимы — добавление, удаление, замена, порядок, перенос.
class CardFormScreen extends ConsumerStatefulWidget {
  /// Создаёт форму; [cardId] == null — создание новой карточки.
  const CardFormScreen({required this.deckId, this.cardId, super.key});

  /// Колода-владелец.
  final String deckId;

  /// Карточка при редактировании; `null` — создание.
  final String? cardId;

  @override
  ConsumerState<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends ConsumerState<CardFormScreen> {
  final TextEditingController _front = TextEditingController();
  final TextEditingController _back = TextEditingController();
  final TextEditingController _hint = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _sourceExcerpt = TextEditingController();

  Card? _card;
  bool _loading = false;
  bool _loadFailed = false;
  bool _saving = false;
  bool _imageLoading = false;
  bool _showValidationSummary = false;
  String _initialSignature = '';
  List<_MediaItem> _questionImages = <_MediaItem>[];
  List<_MediaItem> _answerImages = <_MediaItem>[];
  OcclusionDocument? _occlusion;
  bool _useOcclusion = false;
  CardType _cardType = CardType.basic;
  Map<CardDraftField, CardValidationError> _errors =
      const <CardDraftField, CardValidationError>{};

  /// Ключи полей для прокрутки к первой ошибке валидации (находка F3).
  final Map<CardDraftField, GlobalKey> _fieldAnchors =
      <CardDraftField, GlobalKey>{
        for (final CardDraftField field in <CardDraftField>[
          CardDraftField.front,
          CardDraftField.back,
          CardDraftField.tags,
          CardDraftField.sourceExcerpt,
        ])
          field: GlobalKey(),
      };

  bool get _isEditing => widget.cardId != null;

  @override
  void initState() {
    super.initState();
    // Подпись «пустой» формы: правки нового пользователя сразу считаются
    // несохранёнными (находка N2).
    _initialSignature = _draftSignature();
    if (_isEditing) {
      _loading = true;
      _loadCard();
    }
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _hint.dispose();
    _tags.dispose();
    _sourceExcerpt.dispose();
    super.dispose();
  }

  Future<void> _loadCard() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final Card? card = await ref
          .read(cardRepositoryProvider)
          .cardById(widget.cardId!);
      if (!mounted) return;
      if (card == null) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
        return;
      }
      _front.text = card.front;
      _back.text = card.back;
      _hint.text = card.hint ?? '';
      _tags.text = card.tags.join(', ');
      _sourceExcerpt.text = card.sourceExcerpt ?? '';
      final List<_MediaItem> question = <_MediaItem>[
        for (final String id in card.questionMediaIds) _MediaItem.stored(id),
      ];
      final List<_MediaItem> answer = <_MediaItem>[
        for (final String id in card.answerMediaIds) _MediaItem.stored(id),
      ];
      await _readStoredImages(<_MediaItem>[...question, ...answer]);
      if (!mounted) return;
      setState(() {
        _card = card;
        _cardType = card.cardType;
        _questionImages = question;
        _answerImages = answer;
        _occlusion = OcclusionDocument.tryParse(card.occlusionJson);
        // Старая occlusion-карточка открывается с включёнными масками; обычная
        // карточка с иллюстрацией — с выключенными (ADR-028).
        _useOcclusion = _occlusion != null;
        _loading = false;
        _initialSignature = _draftSignature();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Читает байты и метаданные существующих изображений (обе стороны).
  Future<void> _readStoredImages(List<_MediaItem> items) async {
    final List<String> ids = <String>[
      for (final _MediaItem item in items)
        if (item.mediaId != null) item.mediaId!,
    ];
    if (ids.isEmpty) return;
    final repository = ref.read(cardMediaRepositoryProvider);
    Map<String, Uint8List> bytes = const <String, Uint8List>{};
    Map<String, MediaMetadata> metadata = const <String, MediaMetadata>{};
    try {
      bytes = await repository.readMedia(ids);
      metadata = await repository.readMetadata(ids);
    } on Object {
      // Файлы не прочитались: элемент покажет явное состояние «недоступно»,
      // изображение не подменяется (7.19).
    }
    for (final _MediaItem item in items) {
      final String? id = item.mediaId;
      if (id == null) continue;
      item.bytes = bytes[id];
      item.metadata = metadata[id];
    }
  }

  /// Выбирает файл и добавляет его на [side] (вопрос = true).
  Future<void> _addImage({required bool question}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _imageLoading = true);
    try {
      final CardImageUpload? upload = await ref
          .read(imageGatewayProvider)
          .pickImage();
      if (!mounted || upload == null) return;
      setState(() {
        final _MediaItem item = _MediaItem.upload(upload);
        if (question) {
          _questionImages = <_MediaItem>[..._questionImages, item];
        } else {
          _answerImages = <_MediaItem>[..._answerImages, item];
        }
        if (question && _useOcclusion) _occlusion = const OcclusionDocument();
        _clearOcclusionError();
      });
    } on Object {
      if (mounted) showAppMessage(context, l10n.cardFormImageLoadError);
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  /// Заменяет изображение [index] на [side] новым файлом (позиция сохраняется).
  Future<void> _replaceImage({
    required bool question,
    required int index,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _imageLoading = true);
    try {
      final CardImageUpload? upload = await ref
          .read(imageGatewayProvider)
          .pickImage();
      if (!mounted || upload == null) return;
      setState(() {
        final List<_MediaItem> target = question
            ? <_MediaItem>[..._questionImages]
            : <_MediaItem>[..._answerImages];
        target[index] = _MediaItem.upload(upload);
        if (question) {
          _questionImages = target;
          if (_useOcclusion) _occlusion = const OcclusionDocument();
        } else {
          _answerImages = target;
        }
        _clearOcclusionError();
      });
    } on Object {
      if (mounted) showAppMessage(context, l10n.cardFormImageLoadError);
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  /// Удаляет изображение [index] со стороны.
  void _removeImage({required bool question, required int index}) {
    setState(() {
      if (question) {
        final List<_MediaItem> next = <_MediaItem>[..._questionImages]
          ..removeAt(index);
        _questionImages = next;
      } else {
        final List<_MediaItem> next = <_MediaItem>[..._answerImages]
          ..removeAt(index);
        _answerImages = next;
      }
      _clearOcclusionError();
    });
  }

  /// Переносит изображение между сторонами (в конец целевого списка).
  void _moveImage({required bool question, required int index}) {
    setState(() {
      if (question) {
        final List<_MediaItem> source = <_MediaItem>[..._questionImages];
        final _MediaItem item = source.removeAt(index);
        _questionImages = source;
        _answerImages = <_MediaItem>[..._answerImages, item];
      } else {
        final List<_MediaItem> source = <_MediaItem>[..._answerImages];
        final _MediaItem item = source.removeAt(index);
        _answerImages = source;
        _questionImages = <_MediaItem>[..._questionImages, item];
      }
      _clearOcclusionError();
    });
  }

  /// Меняет порядок изображения [index] на стороне ([delta] = ±1).
  void _moveImageBy({
    required bool question,
    required int index,
    required int delta,
  }) {
    final List<_MediaItem> source = question
        ? <_MediaItem>[..._questionImages]
        : <_MediaItem>[..._answerImages];
    final int next = index + delta;
    if (next < 0 || next >= source.length) return;
    setState(() {
      final _MediaItem item = source.removeAt(index);
      source.insert(next, item);
      if (question) {
        _questionImages = source;
      } else {
        _answerImages = source;
      }
    });
  }

  /// Ищет картинку заново по сохранённому запросу модели (7.14).
  Future<void> _refreshImage(_MediaItem item) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? mediaId = item.mediaId;
    if (mediaId == null) return;
    setState(() => _imageLoading = true);
    try {
      final CardImageRefreshResult result = await ref
          .read(cardImageRefresherProvider)
          .refreshMedia(mediaId);
      if (!mounted) return;
      switch (result) {
        case CardImageRefreshResult.updated:
          await _reloadImage(item);
          if (mounted) showAppMessage(context, l10n.cardImageRetrySuccess);
        case CardImageRefreshResult.notFound:
          showAppMessage(context, l10n.cardImageRetryNotFound);
        case CardImageRefreshResult.noQuery:
          showAppMessage(context, l10n.cardImageRetryNoQuery);
        case CardImageRefreshResult.missing:
          showAppMessage(context, l10n.genericError);
      }
    } on Object {
      if (mounted) showAppMessage(context, l10n.cardImageRetryError);
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  /// Перечитывает байты и метаданные одного изображения после обновления.
  Future<void> _reloadImage(_MediaItem item) async {
    final String? mediaId = item.mediaId;
    if (mediaId == null) return;
    try {
      final repository = ref.read(cardMediaRepositoryProvider);
      final Map<String, Uint8List> bytes = await repository.readMedia(<String>[
        mediaId,
      ]);
      final Map<String, MediaMetadata> metadata = await repository.readMetadata(
        <String>[mediaId],
      );
      if (!mounted) return;
      setState(() {
        item.bytes = bytes[mediaId];
        item.metadata = metadata[mediaId];
      });
    } on Object {
      // Байты не прочитались — элемент покажет явное состояние «недоступно».
    }
  }

  /// Включает/выключает маски Image Occlusion (только `basic`).
  void _toggleOcclusion(bool enabled) {
    setState(() {
      _useOcclusion = enabled;
      if (enabled && _occlusion == null) {
        _occlusion = const OcclusionDocument();
      }
      _clearOcclusionError();
    });
  }

  void _clearOcclusionError() {
    _errors = <CardDraftField, CardValidationError>{
      for (final entry in _errors.entries)
        if (entry.key != CardDraftField.occlusion) entry.key: entry.value,
    };
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool useOcclusion = _useOcclusion && _cardType == CardType.basic;
    final CardDraft draft = CardDraft(
      front: _front.text,
      back: _back.text,
      hint: _hint.text,
      tags: CardDraft.parseTags(_tags.text),
      cardType: _cardType,
      sourceExcerpt: _sourceExcerpt.text,
      questionMediaIds: _storedIdsOf(_questionImages),
      answerMediaIds: _storedIdsOf(_answerImages),
      questionUploads: _uploadsOf(_questionImages),
      answerUploads: _uploadsOf(_answerImages),
      questionMediaOrder: _orderOf(_questionImages),
      answerMediaOrder: _orderOf(_answerImages),
      occlusionJson: useOcclusion
          ? (_occlusion ?? const OcclusionDocument()).encode()
          : null,
    );
    final Map<CardDraftField, CardValidationError> errors = draft.validate();
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        // Находка F3: сводка видна всегда, а не только при прокрутке вверх.
        _showValidationSummary = true;
      });
      _scrollToFirstError(errors);
      return;
    }
    setState(() {
      _errors = const <CardDraftField, CardValidationError>{};
      _saving = true;
    });
    final CardDraft normalized = draft.normalized();
    try {
      final CardRepository repository = ref.read(cardRepositoryProvider);
      final DateTime now = DateTime.now();
      if (_isEditing) {
        await repository.updateCard(card: _card!, draft: normalized, now: now);
      } else {
        await repository.createCards(
          deckId: widget.deckId,
          draft: normalized,
          now: now,
        );
      }
      if (!mounted) return;
      context.pop(_isEditing ? CardFormResult.updated : CardFormResult.created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, l10n.cardFormSaveError);
    }
  }

  static List<String> _storedIdsOf(List<_MediaItem> items) => <String>[
    for (final _MediaItem item in items)
      if (item.mediaId != null) item.mediaId!,
  ];

  /// Отпечаток текущего содержимого формы: по нему определяется, есть ли
  /// несохранённые правки (находка N2 аудита).
  String _draftSignature() => <String>[
    _front.text,
    _back.text,
    _hint.text,
    _tags.text,
    _sourceExcerpt.text,
    _cardType.name,
    _useOcclusion ? (_occlusion?.encode() ?? '') : '',
    for (final _MediaItem item in _questionImages) 'q:${item.key}',
    for (final _MediaItem item in _answerImages) 'a:${item.key}',
  ].join('\u0000');

  /// Есть ли правки относительно загруженного/пустого состояния.
  bool get _isDirty => _draftSignature() != _initialSignature;

  /// Прокручивает форму к первому невалидному полю (находка F3).
  void _scrollToFirstError(Map<CardDraftField, CardValidationError> errors) {
    const List<CardDraftField> order = <CardDraftField>[
      CardDraftField.front,
      CardDraftField.back,
      CardDraftField.tags,
      CardDraftField.sourceExcerpt,
      CardDraftField.occlusion,
    ];
    final CardDraftField field = order.firstWhere(
      errors.containsKey,
      orElse: () => CardDraftField.front,
    );
    final BuildContext? anchor = _fieldAnchors[field]?.currentContext;
    if (anchor == null) return;
    unawaited(
      Scrollable.ensureVisible(
        anchor,
        alignment: 0.08,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Выход с проверкой несохранённых правок (находка N2).
  ///
  /// Молчаливой потери данных больше нет: «Сохранить и выйти», «Не сохранять»
  /// или «Отмена». `Esc`, системный back и стрелка в шапке идут сюда же.
  Future<void> _confirmExit() async {
    if (_saving) return;
    if (!_isDirty) {
      _leave();
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _UnsavedChoice? choice = await showAppDialog<_UnsavedChoice>(
      context: context,
      title: l10n.cardFormUnsavedTitle,
      subtitle: l10n.cardFormUnsavedMessage,
      closeLabel: l10n.cancel,
      bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          key: const ValueKey<String>('card-form-discard'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UnsavedChoice.discard),
          child: Text(l10n.cardFormUnsavedDiscard),
        ),
        FilledButton(
          key: const ValueKey<String>('card-form-save-exit'),
          onPressed: () => Navigator.of(dialogContext).pop(_UnsavedChoice.save),
          child: Text(l10n.cardFormUnsavedSave),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case null:
        return;
      case _UnsavedChoice.save:
        await _save();
      case _UnsavedChoice.discard:
        _leave();
    }
  }

  void _leave() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  static List<CardImageUpload> _uploadsOf(List<_MediaItem> items) =>
      <CardImageUpload>[
        for (final _MediaItem item in items)
          if (item.upload != null) item.upload!,
      ];

  Future<void> _confirmDelete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool confirmed =
        (await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.cardDeleteDialogTitle),
            content: Text(l10n.cardDeleteDialogMessage),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('card-delete-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey<String>('card-delete-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        )) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref.read(cardRepositoryProvider).deleteCard(widget.cardId!);
      if (!mounted) return;
      context.pop(CardFormResult.deleted);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(context, l10n.cardFormDeleteError);
    }
  }

  /// Порядок стороны: хранимые id и токены `upload:<index>` вперемешку.
  static List<String> _orderOf(List<_MediaItem> items) {
    final List<CardImageUpload> uploads = _uploadsOf(items);
    final List<String> order = <String>[];
    for (final _MediaItem item in items) {
      final String? id = item.mediaId;
      if (id != null) {
        order.add(id);
        continue;
      }
      final CardImageUpload? upload = item.upload;
      if (upload == null) continue;
      final int index = uploads.indexOf(upload);
      if (index >= 0) order.add(uploadMediaToken(index));
    }
    return List<String>.unmodifiable(order);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopScope(
      // Находка N2: «назад», Esc и системный back не теряют правки молча.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing ? l10n.cardFormTitleEdit : l10n.cardFormTitleNew,
          ),
          actions: _isEditing && _card != null
              ? <Widget>[
                  IconButton(
                    key: const ValueKey<String>('card-form-delete'),
                    tooltip: l10n.cardDeleteTooltip,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _saving ? null : _confirmDelete,
                  ),
                ]
              : null,
        ),
        body: _buildBody(context, l10n),
        bottomNavigationBar:
            _loading || _loadFailed || (_isEditing && _card == null)
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSizes.formMaxWidth,
                        ),
                        child: FilledButton(
                          key: const ValueKey<String>('card-form-save'),
                          onPressed: _saving ? null : _save,
                          child: Text(l10n.save),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed || (_isEditing && _card == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.dialogMaxWidth,
            ),
            child: AppErrorState(
              message: l10n.cardFormLoadError,
              retryLabel: l10n.retry,
              onRetry: _loadCard,
            ),
          ),
        ),
      );
    }
    return AppContentWidth(
      maxWidth: AppSizes.formMaxWidth,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        // Находка D12: плавающая подпись первого поля не должна срезаться
        // верхней границей области прокрутки.
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_showValidationSummary) ...<Widget>[
              _ValidationSummary(
                message: l10n.cardFormValidationSummary,
                onDismiss: () => setState(() => _showValidationSummary = false),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            KeyedSubtree(
              key: _fieldAnchors[CardDraftField.front],
              child: _textField(
                key: const ValueKey<String>('card-form-front'),
                controller: _front,
                label: l10n.cardFormFrontLabel,
                errorText: _errorText(l10n, CardDraftField.front),
                validationField: CardDraftField.front,
                helperText: _cardType == CardType.cloze
                    ? l10n.cardFormClozeHint(clozeSyntaxExample)
                    : null,
                minLines: 1,
                maxLines: 2,
                autofocus: true,
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _fieldAnchors[CardDraftField.back],
              child: _textField(
                key: const ValueKey<String>('card-form-back'),
                controller: _back,
                label: l10n.cardFormBackLabel,
                errorText: _errorText(l10n, CardDraftField.back),
                validationField: CardDraftField.back,
                minLines: 3,
                maxLines: 6,
              ),
            ),
            const SizedBox(height: 12),
            _textField(
              key: const ValueKey<String>('card-form-hint'),
              controller: _hint,
              label: l10n.cardFormHintLabel,
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _fieldAnchors[CardDraftField.tags],
              child: _textField(
                key: const ValueKey<String>('card-form-tags'),
                controller: _tags,
                label: l10n.cardFormTagsLabel,
                errorText: _errorText(l10n, CardDraftField.tags),
                validationField: CardDraftField.tags,
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _fieldAnchors[CardDraftField.sourceExcerpt],
              child: _textField(
                key: const ValueKey<String>('card-form-source'),
                controller: _sourceExcerpt,
                label: l10n.cardFormSourceExcerptLabel,
                errorText: _errorText(l10n, CardDraftField.sourceExcerpt),
                validationField: CardDraftField.sourceExcerpt,
                minLines: 2,
                maxLines: 4,
              ),
            ),
            const SizedBox(height: 16),
            _buildTypeSection(l10n),
            const SizedBox(height: 20),
            _buildMediaSection(l10n),
          ],
        ),
      ),
    );
  }

  /// Секция изображений: независимые списки вопроса и ответа (ADR-042).
  Widget _buildMediaSection(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final bool masksAvailable = _cardType == CardType.basic;
    final bool masksEnabled = masksAvailable && _useOcclusion;
    final String? error = masksEnabled || _useOcclusion
        ? _errorText(l10n, CardDraftField.occlusion)
        : null;
    final _MediaItem? occlusionSource = _questionImages.isEmpty
        ? null
        : _questionImages.first;
    final Uint8List? occlusionBytes =
        occlusionSource?.bytes ?? occlusionSource?.uploadBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.cardFormImageSection, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.cardFormImageHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        _buildSide(
          l10n: l10n,
          question: true,
          title: l10n.cardFormQuestionImages,
          items: _questionImages,
        ),
        const SizedBox(height: 16),
        _buildSide(
          l10n: l10n,
          question: false,
          title: l10n.cardFormAnswerImages,
          items: _answerImages,
        ),
        if (masksAvailable) ...<Widget>[
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey<String>('card-form-occlusion-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.cardFormOcclusionToggle),
            subtitle: Text(l10n.cardFormOcclusionToggleHint),
            value: _useOcclusion,
            onChanged: _saving ? null : _toggleOcclusion,
          ),
        ],
        if (masksEnabled) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.cardFormOcclusionSection,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (occlusionBytes != null && _occlusion != null)
            OcclusionMaskEditor(
              imageBytes: occlusionBytes,
              document: _occlusion!,
              onChanged: (document) {
                setState(() {
                  _occlusion = document;
                  _clearOcclusionError();
                });
              },
            )
          else
            Text(
              l10n.cardImageUnavailable,
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ],
    );
  }

  /// Один независимый список изображений стороны.
  Widget _buildSide({
    required AppLocalizations l10n,
    required bool question,
    required String title,
    required List<_MediaItem> items,
  }) {
    final ThemeData theme = Theme.of(context);
    final String prefix = question ? 'question' : 'answer';
    return Column(
      key: ValueKey<String>('card-form-$prefix-images'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
                key: ValueKey<String>('card-form-$prefix-images-title'),
              ),
            ),
            OutlinedButton.icon(
              key: ValueKey<String>(
                question
                    ? 'card-form-add-question-image'
                    : 'card-form-add-answer-image',
              ),
              onPressed: _imageLoading || _saving
                  ? null
                  : () => _addImage(question: question),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                question
                    ? l10n.cardFormAddQuestionImage
                    : l10n.cardFormAddAnswerImage,
              ),
            ),
          ],
        ),
        if (items.isEmpty)
          Container(
            key: ValueKey<String>('card-form-empty-$prefix-images'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(kCardImageCornerRadius),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  question
                      ? l10n.cardFormEmptyQuestionImages
                      : l10n.cardFormEmptyAnswerImages,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        for (var index = 0; index < items.length; index++)
          _buildImageTile(
            l10n: l10n,
            question: question,
            index: index,
            item: items[index],
          ),
      ],
    );
  }

  /// Карточка одного изображения с действиями стороны.
  Widget _buildImageTile({
    required AppLocalizations l10n,
    required bool question,
    required int index,
    required _MediaItem item,
  }) {
    final ThemeData theme = Theme.of(context);
    final String prefix = question ? 'question' : 'answer';
    final Uint8List? bytes = item.bytes ?? item.uploadBytes;
    final bool first = index == 0;
    return Container(
      key: ValueKey<String>('card-form-$prefix-image-$index'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(kCardImageCornerRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (bytes == null)
            Container(
              key: ValueKey<String>('card-form-$prefix-missing-$index'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.image_not_supported_outlined,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cardImageUnavailable,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            )
          else
            CardImageView(
              bytes: bytes,
              kind: item.metadata?.kind ?? GeneratedCardImageKind.photo,
              metadata: item.metadata,
              maxHeight: 180,
              onRetry: item.isStored ? () => _reloadImage(item) : null,
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              if (index > 0)
                IconButton(
                  key: ValueKey<String>('card-form-move-up-$prefix-$index'),
                  tooltip: l10n.cardFormMoveImageUp,
                  onPressed: _saving
                      ? null
                      : () => _moveImageBy(
                          question: question,
                          index: index,
                          delta: -1,
                        ),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
              if (index <
                  (question ? _questionImages : _answerImages).length - 1)
                IconButton(
                  key: ValueKey<String>('card-form-move-down-$prefix-$index'),
                  tooltip: l10n.cardFormMoveImageDown,
                  onPressed: _saving
                      ? null
                      : () => _moveImageBy(
                          question: question,
                          index: index,
                          delta: 1,
                        ),
                  icon: const Icon(Icons.arrow_downward, size: 20),
                ),
              TextButton.icon(
                key: ValueKey<String>('card-form-move-$prefix-$index'),
                onPressed: _saving
                    ? null
                    : () => _moveImage(question: question, index: index),
                icon: const Icon(Icons.swap_horiz, size: 20),
                label: Text(
                  question
                      ? l10n.cardFormMoveToAnswer
                      : l10n.cardFormMoveToQuestion,
                ),
              ),
              TextButton.icon(
                key: ValueKey<String>('card-form-replace-$prefix-$index'),
                onPressed: _imageLoading || _saving
                    ? null
                    : () => _replaceImage(question: question, index: index),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: Text(
                  item.bytes == null && !item.isStored
                      ? l10n.cardFormPickImage
                      : l10n.cardFormChangeImage,
                ),
              ),
              if (item.isStored)
                TextButton.icon(
                  key: first && question
                      ? const ValueKey<String>('card-form-refresh-image')
                      : ValueKey<String>('card-form-refresh-$prefix-$index'),
                  onPressed: _imageLoading || _saving
                      ? null
                      : () => _refreshImage(item),
                  icon: const Icon(Icons.travel_explore, size: 20),
                  label: Text(l10n.cardImageRetryAction),
                ),
              TextButton.icon(
                key: ValueKey<String>('card-form-remove-$prefix-$index'),
                onPressed: _saving
                    ? null
                    : () => _removeImage(question: question, index: index),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: Text(l10n.cardFormRemoveImage),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSection(AppLocalizations l10n) {
    if (_isEditing) {
      final String typeLabel = switch (_cardType) {
        CardType.basic => l10n.cardTypeBasic,
        CardType.basicReversed => l10n.cardTypeBasicReversed,
        CardType.cloze => l10n.cardTypeCloze,
      };
      return InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.cardFormTypeLabel,
          helperText: l10n.cardFormTypeImmutable,
          border: const OutlineInputBorder(),
        ),
        child: Text(typeLabel),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.cardFormTypeLabel),
        const SizedBox(height: 8),
        SegmentedButton<CardType>(
          segments: <ButtonSegment<CardType>>[
            ButtonSegment<CardType>(
              value: CardType.basic,
              label: Text(l10n.cardTypeBasic),
            ),
            ButtonSegment<CardType>(
              value: CardType.basicReversed,
              label: Text(l10n.cardTypeBasicReversed),
            ),
            ButtonSegment<CardType>(
              value: CardType.cloze,
              label: Text(l10n.cardTypeCloze),
            ),
          ],
          selected: <CardType>{_cardType},
          onSelectionChanged: (Set<CardType> selection) {
            setState(() => _cardType = selection.first);
          },
        ),
        if (_cardType == CardType.basicReversed) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.cardFormReversedHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        // Находка F2: синтаксис пропусков больше не нужно угадывать — пример
        // и правило стоят прямо под выбором типа, а не только в ошибке.
        if (_cardType == CardType.cloze) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.cardFormClozeHint(clozeSyntaxExample),
            key: const ValueKey<String>('card-form-cloze-hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? errorText,
    String? helperText,
    CardDraftField? validationField,
    int minLines = 1,
    int maxLines = 1,
    bool autofocus = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      // Прокрутка к полю при фокусе оставляет место для плавающей подписи.
      scrollPadding: const EdgeInsets.all(AppSpacing.xxl),
      onChanged: (_) => _clearError(validationField),
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        helperText: helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// Сбрасывает ошибку поля при правке, чтобы она не висела до следующего Save.
  void _clearError(CardDraftField? field) {
    if (field == null || !_errors.containsKey(field)) return;
    setState(() {
      _errors = <CardDraftField, CardValidationError>{
        for (final MapEntry<CardDraftField, CardValidationError> entry
            in _errors.entries)
          if (entry.key != field) entry.key: entry.value,
      };
      if (_errors.isEmpty) _showValidationSummary = false;
    });
  }

  String? _errorText(AppLocalizations l10n, CardDraftField field) {
    return switch (_errors[field]) {
      CardValidationError.frontEmpty => l10n.cardFormFrontEmptyError,
      CardValidationError.frontTooLong => l10n.cardFormFrontTooLongError,
      CardValidationError.backEmpty => l10n.cardFormBackEmptyError,
      CardValidationError.backTooLong => l10n.cardFormBackTooLongError,
      CardValidationError.tagsTooMany => l10n.cardFormTagsTooManyError,
      CardValidationError.sourceExcerptTooLong =>
        l10n.cardFormSourceExcerptTooLongError,
      CardValidationError.clozeMissing => l10n.cardFormClozeMissingError,
      CardValidationError.occlusionImageMissing =>
        l10n.cardFormOcclusionImageMissingError,
      CardValidationError.occlusionMasksMissing =>
        l10n.cardFormOcclusionMasksMissingError,
      CardValidationError.occlusionInvalid =>
        l10n.cardFormOcclusionInvalidError,
      null => null,
    };
  }
}

/// Сводка ошибок валидации формы (находка F3).
///
/// Появляется при неудачном сохранении: раньше ошибка могла оказаться выше
/// области прокрутки и «ничего не происходило».
class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('card-form-validation-summary'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + 4,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            iconSize: AppSizes.iconSmall,
            visualDensity: VisualDensity.compact,
            color: scheme.onErrorContainer,
            tooltip: AppLocalizations.of(context).sessionNoticeDismiss,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
