import 'dart:typed_data';
import 'dart:ui' show PathMetric;

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
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/cards/occlusion_mask_editor.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Пример cloze-разметки для подсказки синтаксиса.
const String _clozeExample = '{{c1::…}}';

/// Пример LaTeX-разметки для подсказки синтаксиса.
const String _latexExample = r'$…$';

/// Результат работы формы карточки (для сообщений на экране колоды).
enum CardFormResult {
  /// Карточка создана.
  created,

  /// Изменения сохранены.
  updated,

  /// Карточка удалена.
  deleted,
}

/// Экран создания/редактирования карточки (SPEC A6.3, ADR-009;
/// REDESIGN-SPEC §9.4).
///
/// Поля: front (обязателен, ≤500), back (обязателен, ≤2000), hint, теги (≤3),
/// тип (`basic`/`basic_reversed`/`cloze`, при редактировании неизменяем),
/// `source_excerpt` для кнопки «Почему?», изображение и (необязательно) маски
/// Image Occlusion. Оформление — `NcTopBar`/`NcSegmented`/`NcTextField`/
/// `NcDialog`/`NcGlass`; обработчики, валидация и результат — прежние.
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
  bool _frontPreview = false;
  bool _backPreview = false;
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
        (await showNcDialog<bool>(
          context,
          title: l10n.cardDeleteDialogTitle,
          message: l10n.cardDeleteDialogMessage,
          icon3dName: 'shield_error',
          actions: <Widget>[
            NcButton(
              key: const ValueKey<String>('card-delete-cancel'),
              label: l10n.cancel,
              variant: NcButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NcButton(
              key: const ValueKey<String>('card-delete-confirm'),
              label: l10n.delete,
              variant: NcButtonVariant.destructive,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
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
    final bool showSaveBar =
        !(_loading || _loadFailed || (_isEditing && _card == null));
    return NcGlassGroup(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NcTopBar(
                title: _isEditing
                    ? l10n.cardFormTitleEdit
                    : l10n.cardFormTitleNew,
                leading: NcIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: l10n.reviewBack,
                  variant: NcIconButtonVariant.glass,
                  onPressed: () {
                    if (context.canPop()) context.pop();
                  },
                ),
                actions: _isEditing && _card != null
                    ? <Widget>[
                        NcIconButton(
                          key: const ValueKey<String>('card-form-delete'),
                          icon: Icons.delete_outline,
                          tooltip: l10n.cardDeleteTooltip,
                          iconColor: NcTheme.of(context).colors.ember,
                          onPressed: _saving ? null : _confirmDelete,
                        ),
                      ]
                    : const <Widget>[],
              ),
              Expanded(child: _buildBody(context, l10n)),
            ],
          ),
        ),
        bottomNavigationBar: showSaveBar ? _buildSaveBar(l10n) : null,
      ),
    );
  }

  Widget _buildSaveBar(AppLocalizations l10n) {
    return NcGlass(
      tier: NcGlassTier.regular,
      radius: 0,
      grouped: true,
      showNoise: false,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget button = NcButton(
            key: const ValueKey<String>('card-form-save'),
            label: l10n.save,
            size: NcButtonSize.l,
            loading: _saving,
            expand: constraints.maxWidth < 600,
            onPressed: _saving ? null : _save,
          );
          if (constraints.maxWidth < 600) return button;
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[SizedBox(width: 240, child: button)],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 240, child: NcSkeleton(height: 120)),
      );
    }
    if (_loadFailed || (_isEditing && _card == null)) {
      return NcErrorState(
        message: l10n.cardFormLoadError,
        retryLabel: l10n.retry,
        onRetry: _loadCard,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTypeSection(l10n),
              const SizedBox(height: 16),
              _field(
                key: const ValueKey<String>('card-form-front'),
                controller: _front,
                label: l10n.cardFormFrontLabel,
                errorText: _errorText(l10n, CardDraftField.front),
                validationField: CardDraftField.front,
                minLines: 1,
                maxLines: 4,
                autofocus: true,
              ),
              _FieldPreview(
                key: const ValueKey<String>('card-form-front-preview'),
                visible: _frontPreview,
                text: _front,
                onToggle: () => setState(() => _frontPreview = !_frontPreview),
                toggleTooltip: l10n.cardFormPreviewToggle,
                title: l10n.cardFormPreview,
              ),
              const SizedBox(height: 12),
              _field(
                key: const ValueKey<String>('card-form-back'),
                controller: _back,
                label: l10n.cardFormBackLabel,
                errorText: _errorText(l10n, CardDraftField.back),
                validationField: CardDraftField.back,
                minLines: 3,
                maxLines: 6,
              ),
              _FieldPreview(
                key: const ValueKey<String>('card-form-back-preview'),
                visible: _backPreview,
                text: _back,
                onToggle: () => setState(() => _backPreview = !_backPreview),
                toggleTooltip: l10n.cardFormPreviewToggle,
                title: l10n.cardFormPreview,
              ),
              const SizedBox(height: 12),
              _field(
                key: const ValueKey<String>('card-form-hint'),
                controller: _hint,
                label: l10n.cardFormHintLabel,
              ),
              const SizedBox(height: 12),
              _field(
                key: const ValueKey<String>('card-form-tags'),
                controller: _tags,
                label: l10n.cardFormTagsLabel,
                errorText: _errorText(l10n, CardDraftField.tags),
                validationField: CardDraftField.tags,
                onChanged: (_) => setState(() {}),
              ),
              _TagsPreview(controller: _tags),
              const SizedBox(height: 12),
              _field(
                key: const ValueKey<String>('card-form-source'),
                controller: _sourceExcerpt,
                label: l10n.cardFormSourceExcerptLabel,
                errorText: _errorText(l10n, CardDraftField.sourceExcerpt),
                validationField: CardDraftField.sourceExcerpt,
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              _buildMediaSection(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Секция изображения для любого типа карточки (ADR-028).
  ///
  /// Маски — необязательный переключатель у `basic`: по умолчанию картинка
  /// показывается как иллюстрация без масок.
  Widget _buildMediaSection(AppLocalizations l10n) {
    final NcTheme theme = NcTheme.of(context);
    final bool masksAvailable = _cardType == CardType.basic;
    final bool masksEnabled = masksAvailable && _useOcclusion;
    final String? error = masksEnabled || _useOcclusion
        ? _errorText(l10n, CardDraftField.occlusion)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.cardFormImageSection,
          style: theme.typography.titleS.copyWith(
            color: theme.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.cardFormImageHint,
          style: theme.typography.bodyS.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            error,
            style: theme.typography.bodyS.copyWith(color: theme.colors.ember),
          ),
        ],
        const SizedBox(height: 12),
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
        ] else
          _ImageDropZone(onPick: _imageLoading || _saving ? null : _pickImage),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            NcButton(
              key: const ValueKey<String>('card-form-pick-image'),
              label: _imageBytes == null
                  ? l10n.cardFormPickImage
                  : l10n.cardFormChangeImage,
              variant: NcButtonVariant.secondary,
              size: NcButtonSize.s,
              icon: Icons.add_photo_alternate_outlined,
              onPressed: _imageLoading || _saving ? null : _pickImage,
            ),
            if (_isEditing && _imageBytes != null)
              NcButton(
                key: const ValueKey<String>('card-form-refresh-image'),
                label: l10n.cardImageRetryAction,
                variant: NcButtonVariant.secondary,
                size: NcButtonSize.s,
                icon: Icons.travel_explore,
                onPressed: _imageLoading || _saving ? null : _refreshImage,
              ),
            if (_imageBytes != null || _imageUpload != null)
              NcButton(
                key: const ValueKey<String>('card-form-remove-image'),
                label: l10n.cardFormRemoveImage,
                variant: NcButtonVariant.ghost,
                size: NcButtonSize.s,
                icon: Icons.delete_outline,
                onPressed: _imageLoading || _saving ? null : _removeImage,
              ),
          ],
        ),
        if (masksAvailable) ...<Widget>[
          const SizedBox(height: 8),
          NcListRow(
            key: const ValueKey<String>('card-form-occlusion-toggle'),
            title: Text(l10n.cardFormOcclusionToggle),
            subtitle: Text(l10n.cardFormOcclusionToggleHint),
            showDivider: false,
            trailing: NcSwitch(
              value: _useOcclusion,
              onChanged: _saving ? null : _toggleOcclusion,
              semanticLabel: l10n.cardFormOcclusionToggle,
            ),
            onTap: _saving ? null : () => _toggleOcclusion(!_useOcclusion),
          ),
        ],
        if (masksEnabled) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.cardFormOcclusionSection,
            style: theme.typography.titleS.copyWith(
              color: theme.colors.textPrimary,
            ),
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
    final NcTheme theme = NcTheme.of(context);
    if (_isEditing) {
      final String typeLabel = switch (_cardType) {
        CardType.basic => l10n.cardTypeBasic,
        CardType.basicReversed => l10n.cardTypeBasicReversed,
        CardType.cloze => l10n.cardTypeCloze,
      };
      return NcSection(
        title: l10n.cardFormTypeLabel,
        children: <Widget>[
          NcListRow(
            title: Text(typeLabel),
            subtitle: Text(l10n.cardFormTypeImmutable),
            showDivider: false,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.cardFormTypeLabel,
          style: theme.typography.labelM.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        NcSegmented<CardType>(
          value: _cardType,
          onChanged: (CardType type) => setState(() => _cardType = type),
          segments: <NcSegment<CardType>>[
            NcSegment<CardType>(
              value: CardType.basic,
              label: l10n.cardTypeBasic,
            ),
            NcSegment<CardType>(
              value: CardType.basicReversed,
              label: l10n.cardTypeBasicReversed,
            ),
            NcSegment<CardType>(
              value: CardType.cloze,
              label: l10n.cardTypeCloze,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.cardFormSyntaxHint,
          style: theme.typography.bodyS.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: <Widget>[
            Text(
              _clozeExample,
              style: theme.typography.monoM.copyWith(color: theme.colors.aurum),
            ),
            Text(
              _latexExample,
              style: theme.typography.monoM.copyWith(color: theme.colors.aurum),
            ),
          ],
        ),
        if (_cardType == CardType.basicReversed) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.cardFormReversedHint,
            style: theme.typography.bodyS.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? errorText,
    CardDraftField? validationField,
    int minLines = 1,
    int maxLines = 1,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
  }) {
    return NcTextField(
      key: key,
      controller: controller,
      label: label,
      errorText: errorText,
      multiline: maxLines != 1,
      maxLines: maxLines,
      autofocus: autofocus,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      onChanged: (String value) {
        _clearError(validationField);
        onChanged?.call(value);
      },
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

/// Сворачиваемый предпросмотр поля: `CardText` на мини-монолите.
class _FieldPreview extends StatelessWidget {
  const _FieldPreview({
    super.key,
    required this.visible,
    required this.text,
    required this.onToggle,
    required this.toggleTooltip,
    required this.title,
  });

  final bool visible;
  final TextEditingController text;
  final VoidCallback onToggle;
  final String toggleTooltip;
  final String title;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: text,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        if (value.text.trim().isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: theme.typography.overline.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  ),
                  NcIconButton(
                    icon: visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    tooltip: toggleTooltip,
                    size: 32,
                    onPressed: onToggle,
                  ),
                ],
              ),
              if (visible)
                NcSurface(
                  tone: NcSurfaceTone.monolith,
                  radius: NcRadii.xl,
                  level: 2,
                  padding: const EdgeInsets.all(16),
                  child: CardText(
                    source: value.text,
                    style: theme.typography.answer.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Визуальный ряд тегов под полем (значение поля не меняется).
class _TagsPreview extends StatelessWidget {
  const _TagsPreview({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        final List<String> tags = CardDraft.parseTags(value.text);
        if (tags.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            key: const ValueKey<String>('card-form-tags-preview'),
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String tag in tags) NcChip.tag(label: tag),
            ],
          ),
        );
      },
    );
  }
}

/// Пунктирная зона выбора изображения (пустое состояние секции).
class _ImageDropZone extends StatelessWidget {
  const _ImageDropZone({required this.onPick});

  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    return GestureDetector(
      onTap: onPick,
      child: SizedBox(
        height: 140,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: theme.colors.hairlineStrong,
            radius: NcRadii.l,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 28,
                  color: theme.colors.textTertiary,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.cardFormPickImage,
                  style: theme.typography.bodyS.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Пунктирная рамка зоны изображения (не стекло, §4.3).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final double next = (distance + 6).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
