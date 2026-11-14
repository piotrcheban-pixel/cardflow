import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/l10n/app_localizations.dart';
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
/// `source_excerpt` для кнопки «Почему?» и редактор масок occlusion.
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
  OcclusionDocument? _occlusion;
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
      if (card.mediaIds.isNotEmpty) {
        try {
          final bytes = await ref.read(cardMediaRepositoryProvider).readMedia(
            <String>[card.mediaIds.first],
          );
          imageBytes = bytes[card.mediaIds.first];
        } on Object {
          imageBytes = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _card = card;
        _cardType = card.cardType;
        _imageBytes = imageBytes;
        _occlusion = OcclusionDocument.tryParse(card.occlusionJson);
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

  Future<void> _pickImage() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _imageLoading = true);
    try {
      final upload = await ref.read(imageGatewayProvider).pickImage();
      if (!mounted || upload == null) return;
      setState(() {
        _imageUpload = upload;
        _imageBytes = upload.bytes;
        _occlusion = const OcclusionDocument();
        _errors = <CardDraftField, CardValidationError>{
          for (final entry in _errors.entries)
            if (entry.key != CardDraftField.occlusion) entry.key: entry.value,
        };
      });
    } on Object {
      if (mounted) showAppMessage(context, l10n.cardFormImageLoadError);
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasOcclusion = _imageBytes != null && _occlusion != null;
    final bool replacingImage = _imageUpload != null;
    final mediaIds = <String>[
      if (_card != null && (!hasOcclusion || !replacingImage))
        ..._card!.mediaIds,
      if (_card != null &&
          hasOcclusion &&
          replacingImage &&
          _card!.mediaIds.length > 1)
        ..._card!.mediaIds.skip(1),
    ];
    final CardDraft draft = CardDraft(
      front: _front.text,
      back: _back.text,
      hint: _hint.text,
      tags: CardDraft.parseTags(_tags.text),
      cardType: _cardType,
      sourceExcerpt: _sourceExcerpt.text,
      mediaIds: mediaIds,
      occlusionJson: hasOcclusion && _cardType == CardType.basic
          ? _occlusion!.encode()
          : null,
      imageUpload: hasOcclusion && _cardType == CardType.basic
          ? _imageUpload
          : null,
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
          if (_cardType == CardType.basic) ...<Widget>[
            const SizedBox(height: 20),
            _buildOcclusionSection(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildOcclusionSection(AppLocalizations l10n) {
    final error = _errorText(l10n, CardDraftField.occlusion);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.cardFormOcclusionSection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
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
        if (_imageBytes != null && _occlusion != null) ...<Widget>[
          const SizedBox(height: 12),
          OcclusionMaskEditor(
            imageBytes: _imageBytes!,
            document: _occlusion!,
            onChanged: (document) {
              setState(() {
                _occlusion = document;
                _errors = <CardDraftField, CardValidationError>{
                  for (final entry in _errors.entries)
                    if (entry.key != CardDraftField.occlusion)
                      entry.key: entry.value,
                };
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
