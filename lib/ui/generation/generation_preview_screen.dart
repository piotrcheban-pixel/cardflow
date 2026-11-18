/// Экран предпросмотра сгенерированных карточек (SPEC A6.8, ADR-015).
///
/// Чекбоксы, инлайн-редактирование front/back, пометки A8.4, импорт всех или
/// выбранных карточек одной транзакцией, частичный успех с повтором упавших
/// фрагментов. Упавшие фрагменты импорт не блокируют, невалидная карточка
/// пропускается сама (fix-gen, Д6). Картинку из файла/поиска можно убрать или
/// заменить до импорта (Д3). Все сообщения — из ARB.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' show CardType;
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/document_gateway.dart'
    show PickedDocument;
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/generation/generation_error_message.dart';
import 'package:cardflow/ui/generation/generation_failure_message.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран предпросмотра.
class GenerationPreviewScreen extends ConsumerStatefulWidget {
  /// Создаёт экран предпросмотра.
  const GenerationPreviewScreen({
    required this.request,
    required this.result,
    super.key,
  });

  /// Исходный запрос (провайдер/модель/колода).
  final GenerationRunRequest request;

  /// Результат генерации (может обновиться после повтора).
  final GenerationRunResult result;

  @override
  ConsumerState<GenerationPreviewScreen> createState() =>
      _GenerationPreviewScreenState();
}

/// Редактируемая карточка предпросмотра.
class _EditableCard {
  _EditableCard(this.original)
    : front = TextEditingController(text: original.front),
      back = TextEditingController(text: original.back),
      image = original.image,
      imageId = original.imageId,
      selected = true;

  final GeneratedCard original;
  final TextEditingController front;
  final TextEditingController back;
  bool selected;

  /// Текущая картинка карточки (из файла или поиска); `null` — нет.
  GeneratedCardImage? image;

  /// Идентификатор изображения из `<images>`; `null` — нет.
  String? imageId;

  void dispose() {
    front.dispose();
    back.dispose();
  }

  /// Карточка с текущими правками пользователя.
  GeneratedCard toCard() {
    // Если картинка выбрана/заменена вручную, пометки о ненайденной картинке
    // больше не актуальны (fix-gen, Д3).
    final List<CardIssueCode> issues = image == null
        ? original.issues
        : original.issues
              .where(
                (CardIssueCode issue) =>
                    issue != CardIssueCode.imageNotFound &&
                    issue != CardIssueCode.imageIdUnknown,
              )
              .toList(growable: false);
    return GeneratedCard(
      front: front.text.trim(),
      back: back.text.trim(),
      cardType: original.cardType,
      hint: original.hint,
      tags: original.tags,
      sourceExcerpt: original.sourceExcerpt,
      sourceFile: original.sourceFile,
      issues: issues,
      imageQuery: original.imageQuery,
      imageId: imageId,
      image: image,
      isOcclusion: original.isOcclusion,
      occlusionJson: original.occlusionJson,
    );
  }
}

class _GenerationPreviewScreenState
    extends ConsumerState<GenerationPreviewScreen> {
  late GenerationRunResult _result;
  final List<_EditableCard> _cards = <_EditableCard>[];
  bool _retrying = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _rebuildCards(merge: false);
  }

  @override
  void dispose() {
    for (final _EditableCard card in _cards) {
      card.dispose();
    }
    super.dispose();
  }

  /// Перестраивает список по результату, сохраняя правки старых карточек.
  void _rebuildCards({required bool merge}) {
    final List<_EditableCard> previous = List<_EditableCard>.of(_cards);
    final List<_EditableCard> next = <_EditableCard>[];
    for (final GeneratedCard card in _result.cards) {
      _EditableCard? existing;
      if (merge) {
        for (final _EditableCard candidate in previous) {
          if (candidate.original == card) {
            existing = candidate;
            break;
          }
        }
      }
      if (existing != null) {
        next.add(existing);
      } else {
        next.add(_EditableCard(card));
      }
    }
    for (final _EditableCard card in previous) {
      if (!next.contains(card)) card.dispose();
    }
    _cards
      ..clear()
      ..addAll(next);
  }

  int get _selectedCount =>
      _cards.where((_EditableCard card) => card.selected).length;

  /// Сколько **выбранных** карточек осталось без картинки после поиска
  /// (ADR-028). Снятая галочка убирает карточку из импорта и из предупреждения.
  int get _imagesNotFound => _cards
      .where(
        (_EditableCard card) =>
            card.selected &&
            card.image == null &&
            card.original.issues.contains(CardIssueCode.imageNotFound),
      )
      .length;

  Future<void> _retryFailed() async {
    if (_retrying || _importing) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _retrying = true);
    try {
      final GenerationRunResult updated = await ref
          .read(generationRunnerProvider)
          .retryFailed(widget.request, _result);
      if (!mounted) return;
      setState(() {
        _result = updated;
        _rebuildCards(merge: true);
        _retrying = false;
      });
    } on GenerationException catch (error) {
      if (!mounted) return;
      setState(() => _retrying = false);
      showAppMessage(
        context,
        generationErrorCodeMessage(
          l10n,
          error.code,
          retryAfter: error.retryAfter,
          providerReason: error.providerReason,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _retrying = false);
      showAppMessage(context, l10n.generationErrorGeneric);
    }
  }

  /// Убирает картинку карточки — она импортируется без изображения (Д3).
  void _removeImage(int index) {
    setState(() {
      _cards[index]
        ..image = null
        ..imageId = null;
    });
  }

  /// Заменяет картинку карточки изображением JPG/PNG пользователя (Д3).
  Future<void> _replaceImage(int index) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final List<PickedDocument> picked = await ref
          .read(documentGatewayProvider)
          .pickDocuments();
      if (picked.isEmpty || !mounted) return;
      final PickedDocument document = picked.first;
      final AttachmentMediaType? mediaType = attachmentMediaTypeForFileName(
        document.name,
      );
      if (mediaType == null) {
        showAppMessage(context, l10n.generationPreviewImageReplaceError);
        return;
      }
      final bytes = await ref
          .read(documentGatewayProvider)
          .readDocument(document);
      if (!mounted) return;
      if (!hasValidAttachmentSignature(mediaType, bytes)) {
        showAppMessage(context, l10n.generationPreviewImageReplaceError);
        return;
      }
      setState(() {
        _cards[index]
          ..image = GeneratedCardImage(
            bytes: bytes,
            mediaType: mediaType,
            query: document.name,
          )
          ..imageId = null;
      });
      showAppMessage(context, l10n.generationPreviewImageReplaced);
    } on Object {
      if (!mounted) return;
      showAppMessage(context, l10n.generationPreviewImageReplaceError);
    }
  }

  Future<void> _import({required bool all}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_importing || _retrying) return;
    final List<_EditableCard> picked = all
        ? List<_EditableCard>.of(_cards)
        : _cards.where((_EditableCard card) => card.selected).toList();
    if (picked.isEmpty) {
      showAppMessage(context, l10n.generationPreviewNoSelection);
      return;
    }
    // Невалидная карточка пропускается сама, остальные импортируются
    // (fix-gen, Д6): один пустой вопрос не должен блокировать пак.
    final List<GeneratedCard> cards = <GeneratedCard>[];
    var skipped = 0;
    for (final _EditableCard card in picked) {
      final GeneratedCard candidate = card.toCard();
      final CardDraft draft = CardDraft(
        front: candidate.front,
        back: candidate.back,
        cardType: candidate.cardType,
        tags: candidate.tags,
      );
      if (!draft.isValid) {
        skipped++;
        continue;
      }
      cards.add(candidate);
    }
    if (cards.isEmpty) {
      showAppMessage(context, l10n.generationPreviewValidationError);
      return;
    }

    setState(() => _importing = true);
    try {
      final GenerationImportResult imported = await ref
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: widget.request.targetDeckId,
            deckName: widget.request.deckName,
            cards: cards,
            jobId: _result.jobId,
            now: DateTime.now(),
          );
      if (!mounted) return;
      setState(() => _importing = false);
      showAppMessage(
        context,
        skipped > 0
            ? l10n.generationImportedWithSkipped(
                imported.importedCards,
                skipped,
              )
            : l10n.generationImported(imported.importedCards),
      );
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(imported);
      }
    } on Object {
      if (!mounted) return;
      setState(() => _importing = false);
      showAppMessage(context, l10n.generationImportError);
    }
  }

  /// Текст ошибки фрагмента: причина из кода/внутреннего кода (fix-gen, Д6).
  ///
  /// Для HTTP 400 показывается очищенная причина провайдера (ADR-022), если
  /// она есть: она конкретнее общей формулировки причины.
  String _failureMessage(
    AppLocalizations l10n,
    GenerationChunkFailure failure,
  ) {
    final String? providerReason = failure.providerReason?.trim();
    if (failure.code == GenerationErrorCode.badRequest &&
        providerReason != null &&
        providerReason.isNotEmpty) {
      return generationErrorCodeMessage(
        l10n,
        failure.code,
        providerReason: providerReason,
      );
    }
    final GenerationFailureReason reason =
        failure.reason ?? GenerationFailureReason.forErrorCode(failure.code);
    return generationFailureReasonMessage(l10n, reason);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final int chunkTotal = _result.chunkCount == 0
        ? _result.failures.length
        : _result.chunkCount;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generationPreviewTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          if (_result.requestedCards > 0 &&
              _result.requestedCards > _result.achievableCards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.generationPlanRequestedAboveAchievable(
                  _result.requestedCards,
                  _result.achievableCards,
                ),
                key: const ValueKey<String>('generation-preview-plan-warning'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (_result.requestedCards > 0 &&
              _result.achievableCards > _result.requestedCards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.generationPlanAchievableAboveRequested(
                  _result.requestedCards,
                  _result.achievableCards,
                ),
                key: const ValueKey<String>(
                  'generation-preview-plan-above-requested',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (_result.plan != null && _result.plan!.hasOmittedUnits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.generationPlanOmittedUnits(_result.plan!.omitted.length),
                key: const ValueKey<String>('generation-preview-plan-omitted'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (_result.cancelled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.generationCancelled,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (_result.cards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.generationPreviewEmpty,
                textAlign: TextAlign.center,
              ),
            )
          else ...<Widget>[
            Text(
              l10n.generationPreviewSelected(
                _selectedCount,
                _result.cards.length,
              ),
              key: const ValueKey<String>('generation-preview-selected'),
              style: theme.textTheme.titleSmall,
            ),
            if (_result.duplicatesRemoved > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.generationDuplicatesRemoved(_result.duplicatesRemoved),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (_result.rejectedCards > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.generationRejectedCards(_result.rejectedCards),
                  key: const ValueKey<String>('generation-preview-rejected'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.generationTokensUsed(_result.tokensUsed),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_imagesNotFound > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  key: const ValueKey<String>(
                    'generation-preview-image-warning',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.generationImageSearchFailed(_imagesNotFound),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          // Ошибки фрагментов — до карточек: при частичном успехе их видно
          // сразу, не прокручивая список (fix-gen, Д6).
          if (_result.failures.isNotEmpty) ...<Widget>[
            Text(
              l10n.generationFailuresTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _result.failures.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.generationFailureChunkOf(
                    _result.failures[i].chunkIndex,
                    chunkTotal,
                    _failureMessage(l10n, _result.failures[i]),
                  ),
                  key: ValueKey<String>('generation-preview-failure-$i'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey<String>('generation-preview-retry-failed'),
              onPressed: _retrying ? null : _retryFailed,
              child: Text(l10n.generationRetryFailed),
            ),
            const SizedBox(height: 16),
          ],
          if (_result.cards.isNotEmpty)
            for (var i = 0; i < _cards.length; i++)
              _PreviewCardTile(
                key: ValueKey<String>('generation-preview-card-$i'),
                card: _cards[i],
                index: i,
                onSelected: (bool selected) =>
                    setState(() => _cards[i].selected = selected),
                onRemoveImage: () => _removeImage(i),
                onReplaceImage: () => _replaceImage(i),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('generation-preview-import-all'),
                onPressed: _importing || _cards.isEmpty
                    ? null
                    : () => _import(all: true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                child: Text(l10n.generationPreviewImportAll),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey<String>(
                  'generation-preview-import-selected',
                ),
                onPressed: _importing || _selectedCount == 0
                    ? null
                    : () => _import(all: false),
                child: Text(l10n.generationPreviewImportSelected),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const ValueKey<String>('generation-preview-cancel'),
                onPressed: _importing
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: Text(l10n.generationPreviewCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка предпросмотра: чекбокс, поля front/back, картинка, пометки.
class _PreviewCardTile extends StatelessWidget {
  const _PreviewCardTile({
    required this.card,
    required this.index,
    required this.onSelected,
    required this.onRemoveImage,
    required this.onReplaceImage,
    super.key,
  });

  final _EditableCard card;
  final int index;
  final ValueChanged<bool> onSelected;
  final VoidCallback onRemoveImage;
  final VoidCallback onReplaceImage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final GeneratedCardImage? image = card.image;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  key: ValueKey<String>('generation-preview-checkbox-$index'),
                  value: card.selected,
                  onChanged: (bool? value) => onSelected(value ?? false),
                ),
                Expanded(
                  child: Text(
                    card.original.isOcclusion
                        ? l10n.cardTypeOcclusion
                        : switch (card.original.cardType) {
                            CardType.basic => l10n.cardTypeBasic,
                            CardType.basicReversed =>
                              l10n.cardTypeBasicReversed,
                            CardType.cloze => l10n.cardTypeCloze,
                          },
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (image != null)
                  IconButton(
                    key: ValueKey<String>(
                      'generation-preview-remove-image-$index',
                    ),
                    tooltip: l10n.generationPreviewRemoveImage,
                    onPressed: onRemoveImage,
                    icon: const Icon(Icons.hide_image_outlined, size: 20),
                  ),
                IconButton(
                  key: ValueKey<String>(
                    'generation-preview-replace-image-$index',
                  ),
                  tooltip: l10n.generationPreviewReplaceImage,
                  onPressed: onReplaceImage,
                  icon: Icon(
                    image == null
                        ? Icons.add_photo_alternate_outlined
                        : Icons.swap_horiz,
                    size: 20,
                  ),
                ),
              ],
            ),
            if (image != null) ...<Widget>[
              const SizedBox(height: 8),
              KeyedSubtree(
                key: ValueKey<String>('generation-preview-image-$index'),
                child: CardImageView(
                  bytes: image.bytes,
                  kind: image.kind,
                  maxHeight: 160,
                  metadata: MediaMetadata(
                    provider: image.provider,
                    sourceUrl: image.sourceUrl,
                    author: image.author,
                    license: image.license,
                    isPlaceholder: image.isPlaceholder,
                    query: image.query,
                    fallbackQuery: image.fallbackQuery,
                    kind: image.kind,
                  ),
                ),
              ),
            ],
            TextField(
              key: ValueKey<String>('generation-preview-front-$index'),
              controller: card.front,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.cardFormFrontLabel,
                border: _fieldBorder,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey<String>('generation-preview-back-$index'),
              controller: card.back,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.cardFormBackLabel,
                border: _fieldBorder,
              ),
            ),
            if (card.original.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final CardIssueCode issue in card.original.issues)
                    Chip(
                      label: Text(issueLabel(l10n, issue)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static OutlineInputBorder get _fieldBorder =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12));
}

/// Подпись пометки A8.4 для предпросмотра.
String issueLabel(AppLocalizations l10n, CardIssueCode issue) {
  return switch (issue) {
    CardIssueCode.emptyFront => l10n.generationIssueEmptyFront,
    CardIssueCode.frontTooLong => l10n.generationIssueFrontTooLong,
    CardIssueCode.backTooLong => l10n.generationIssueBackTooLong,
    CardIssueCode.clozeMissing => l10n.generationIssueClozeMissing,
    CardIssueCode.latexBroken => l10n.generationIssueLatexBroken,
    CardIssueCode.excerptMismatch => l10n.generationIssueExcerptMismatch,
    CardIssueCode.tagsAdjusted => l10n.generationIssueTagsAdjusted,
    CardIssueCode.occlusionImageMissing =>
      l10n.generationIssueOcclusionImageMissing,
    CardIssueCode.imageNotFound => l10n.generationIssueImageNotFound,
    CardIssueCode.imageIdUnknown => l10n.generationIssueImageIdUnknown,
    CardIssueCode.imageQueryAdjusted => l10n.generationIssueImageQueryAdjusted,
    CardIssueCode.abstractImageQuery => l10n.generationIssueAbstractImageQuery,
    CardIssueCode.answerInFront => l10n.generationIssueAnswerInFront,
    CardIssueCode.frontLooksLikeHeading =>
      l10n.generationIssueFrontLooksLikeHeading,
    CardIssueCode.backTooVerbose => l10n.generationIssueBackTooVerbose,
    CardIssueCode.backOnlyNotation => l10n.generationIssueBackOnlyNotation,
    CardIssueCode.unicodeMath => l10n.generationIssueUnicodeMath,
    CardIssueCode.markdownInText => l10n.generationIssueMarkdownInText,
  };
}
