import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_image_refresh_result.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/l10n/app_localizations.dart';
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

/// Экран создания/редактирования карточки (SPEC A6.3, ADR-009).
///
/// Поля: front (обязателен, ≤500), back (обязателен, ≤2000), hint, теги (≤3),
/// тип (`basic`/`basic_reversed`/`cloze`, при редактировании неизменяем),
/// `source_excerpt` для кнопки «Почему?», изображение и (необязательно) маски
/// Image Occlusion.
///
/// ADR-028 (итерация 7.12): изображение можно привязать к карточке **любого**
/// типа; это обычная иллюстрация. Маски occlusion — отдельный переключатель
/// для `basic`, по умолчанию выключен.
/// Сохранение — через репозиторий;
/// удаление — с подтверждением.
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
  CardImageUpload? _imageUpload;
  Uint8List? _imageBytes;
  MediaMetadata? _imageMetadata;
  bool _imageRemoved = false;
  OcclusionDocument? _occlusion;
  bool _useOcclusion = false;
  CardType _cardType = CardType.basic;
  Map<CardDraftField, CardValidationError> _errors =
      const <CardDraftField, CardValidationError>{};

  bool get _isEditing => widget.cardId != null;

  @override
  void initState() {
    super.initState();
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
      Uint8List? imageBytes;
      MediaMetadata? imageMetadata;
      if (card.mediaIds.isNotEmpty) {
        try {
          final primary = card.mediaIds.first;
          final bytes = await ref.read(cardMediaRepositoryProvider).readMedia(
            <String>[primary],
          );
          imageBytes = bytes[primary];
          final metadata = await ref
              .read(cardMediaRepositoryProvider)
              .readMetadata(<String>[primary]);
          imageMetadata = metadata[primary];
        } on Object {
          imageBytes = null;
          imageMetadata = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _card = card;
        _cardType = card.cardType;
        _imageBytes = imageBytes;
        _imageMetadata = imageMetadata;
        _occlusion = OcclusionDocument.tryParse(card.occlusionJson);
        // Старая occlusion-карточка открывается с включёнными масками; обычная
        // карточка с иллюстрацией — с выключенными (ADR-028).
        _useOcclusion = _occlusion != null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Выбирает изображение; маски при этом не включаются (ADR-028).
  Future<void> _pickImage() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _imageLoading = true);
    try {
      final upload = await ref.read(imageGatewayProvider).pickImage();
      if (!mounted || upload == null) return;
      setState(() {
        _imageUpload = upload;
        _imageBytes = upload.bytes;
        _imageMetadata = null;
        _imageRemoved = false;
        // Новая картинка под включённые маски — чистый холст для разметки.
        if (_useOcclusion) _occlusion = const OcclusionDocument();
        _clearOcclusionError();
      });
    } on Object {
      if (mounted) showAppMessage(context, l10n.cardFormImageLoadError);
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  /// Убирает изображение с карточки (маски при этом становятся недоступны).
  void _removeImage() {
    setState(() {
      _imageUpload = null;
      _imageBytes = null;
      _imageMetadata = null;
      _imageRemoved = true;
      _clearOcclusionError();
    });
  }

  /// Ищет картинку заново по сохранённому запросу модели (7.14).
  Future<void> _refreshImage() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Card? card = _card;
    if (card == null || card.mediaIds.isEmpty) return;
    setState(() => _imageLoading = true);
    try {
      final CardImageRefreshResult result = await ref
          .read(cardImageRefresherProvider)
          .refreshMedia(card.mediaIds.first);
      if (!mounted) return;
      switch (result) {
        case CardImageRefreshResult.updated:
          await _reloadImage();
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

  /// Перечитывает байты и метаданные основного изображения после обновления.
  Future<void> _reloadImage() async {
    final Card? card = _card;
    if (card == null || card.mediaIds.isEmpty) return;
    final primary = card.mediaIds.first;
    try {
      final bytes = await ref.read(cardMediaRepositoryProvider).readMedia(
        <String>[primary],
      );
      final metadata = await ref.read(cardMediaRepositoryProvider).readMetadata(
        <String>[primary],
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes[primary];
        _imageMetadata = metadata[primary];
      });
    } on Object {
      // Байты не прочитались — оставляем прежнее изображение.
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
    // Существующие медиа: первое — основное изображение. При замене/удалении
    // основное снимается, а прочие id сохраняются. Если файл не прочитался
    // (bytes == null), медиа не теряется: удаление — только явное.
    final List<String> existingMedia = _card?.mediaIds ?? const <String>[];
    final bool keepExistingPrimary =
        _imageUpload == null && !_imageRemoved && existingMedia.isNotEmpty;
    final mediaIds = <String>[
      if (keepExistingPrimary) existingMedia.first,
      ...existingMedia.skip(existingMedia.isEmpty ? 0 : 1),
    ];
    final OcclusionDocument? occlusion = useOcclusion
        ? (_occlusion ?? const OcclusionDocument())
        : null;
    final CardDraft draft = CardDraft(
      front: _front.text,
      back: _back.text,
      hint: _hint.text,
      tags: CardDraft.parseTags(_tags.text),
      cardType: _cardType,
      sourceExcerpt: _sourceExcerpt.text,
      mediaIds: mediaIds,
      occlusionJson: occlusion?.encode(),
      imageUpload: _imageUpload,
    );
    final Map<CardDraftField, CardValidationError> errors = draft.validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
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
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  key: const ValueKey<String>('card-form-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.save),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(l10n.cardFormLoadError, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadCard, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _textField(
            key: const ValueKey<String>('card-form-front'),
            controller: _front,
            label: l10n.cardFormFrontLabel,
            errorText: _errorText(l10n, CardDraftField.front),
            validationField: CardDraftField.front,
            minLines: 1,
            maxLines: 2,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          _textField(
            key: const ValueKey<String>('card-form-back'),
            controller: _back,
            label: l10n.cardFormBackLabel,
            errorText: _errorText(l10n, CardDraftField.back),
            validationField: CardDraftField.back,
            minLines: 3,
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          _textField(
            key: const ValueKey<String>('card-form-hint'),
            controller: _hint,
            label: l10n.cardFormHintLabel,
          ),
          const SizedBox(height: 12),
          _textField(
            key: const ValueKey<String>('card-form-tags'),
            controller: _tags,
            label: l10n.cardFormTagsLabel,
            errorText: _errorText(l10n, CardDraftField.tags),
            validationField: CardDraftField.tags,
          ),
          const SizedBox(height: 12),
          _textField(
            key: const ValueKey<String>('card-form-source'),
            controller: _sourceExcerpt,
            label: l10n.cardFormSourceExcerptLabel,
            errorText: _errorText(l10n, CardDraftField.sourceExcerpt),
            validationField: CardDraftField.sourceExcerpt,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          _buildTypeSection(l10n),
          const SizedBox(height: 20),
          _buildMediaSection(l10n),
        ],
      ),
    );
  }

  /// Секция изображения для любого типа карточки (ADR-028).
  ///
  /// Маски — необязательный переключатель у `basic`: по умолчанию картинка
  /// показывается как иллюстрация без масок.
  Widget _buildMediaSection(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final bool masksAvailable = _cardType == CardType.basic;
    final bool masksEnabled = masksAvailable && _useOcclusion;
    final String? error = masksEnabled || _useOcclusion
        ? _errorText(l10n, CardDraftField.occlusion)
        : null;
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
        const SizedBox(height: 8),
        if (_imageBytes != null) ...<Widget>[
          KeyedSubtree(
            key: const ValueKey<String>('card-form-image-preview'),
            child: CardImageView(
              bytes: _imageBytes!,
              kind: _imageMetadata?.kind ?? GeneratedCardImageKind.photo,
              metadata: _imageMetadata,
              maxHeight: 200,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              key: const ValueKey<String>('card-form-pick-image'),
              onPressed: _imageLoading || _saving ? null : _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _imageBytes == null
                    ? l10n.cardFormPickImage
                    : l10n.cardFormChangeImage,
              ),
            ),
            if (_isEditing && _imageBytes != null)
              OutlinedButton.icon(
                key: const ValueKey<String>('card-form-refresh-image'),
                onPressed: _imageLoading || _saving ? null : _refreshImage,
                icon: const Icon(Icons.travel_explore),
                label: Text(l10n.cardImageRetryAction),
              ),
            if (_imageBytes != null || _imageUpload != null)
              TextButton.icon(
                key: const ValueKey<String>('card-form-remove-image'),
                onPressed: _imageLoading || _saving ? null : _removeImage,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.cardFormRemoveImage),
              ),
          ],
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
          if (_imageBytes != null && _occlusion != null)
            OcclusionMaskEditor(
              imageBytes: _imageBytes!,
              document: _occlusion!,
              onChanged: (document) {
                setState(() {
                  _occlusion = document;
                  _clearOcclusionError();
                });
              },
            ),
        ],
      ],
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
      ],
    );
  }

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? errorText,
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
      onChanged: (_) => _clearError(validationField),
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
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
