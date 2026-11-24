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
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/document_gateway.dart'
    show PickedDocument;
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/generation/generation_error_message.dart';
import 'package:cardflow/ui/generation/generation_failure_message.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

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
      questionImages = List<GeneratedCardImage>.of(original.questionImages),
      answerImages = List<GeneratedCardImage>.of(original.answerImages),
      selected = true;

  final GeneratedCard original;
  final TextEditingController front;
  final TextEditingController back;
  bool selected;

  /// Изображения лицевой стороны (вопрос) — независимо от ответа (7.19).
  List<GeneratedCardImage> questionImages;

  /// Изображения обратной стороны (ответ).
  List<GeneratedCardImage> answerImages;

  void dispose() {
    front.dispose();
    back.dispose();
  }

  /// Есть ли изображения хотя бы у одной стороны.
  bool get hasImages => questionImages.isNotEmpty || answerImages.isNotEmpty;

  /// Карточка с текущими правками пользователя.
  GeneratedCard toCard() {
    // Если изображение выбрано/заменено вручную, пометки о ненайденной картинке
    // больше не актуальны (fix-gen, Д3).
    final List<CardIssueCode> issues = hasImages
        ? original.issues
              .where(
                (CardIssueCode issue) =>
                    issue != CardIssueCode.imageNotFound &&
                    issue != CardIssueCode.imageIdUnknown,
              )
              .toList(growable: false)
        : original.issues;
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
      imageFallbackQuery: original.imageFallbackQuery,
      imageKind: original.imageKind,
      imageSide: original.imageSide,
      questionImages: List<GeneratedCardImage>.unmodifiable(questionImages),
      answerImages: List<GeneratedCardImage>.unmodifiable(answerImages),
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
  /// Сколько карточек получили изображения автоматическим поиском: для них
  /// показывается предупреждение «проверьте иллюстрации» (аудит 2.0, P1-04).
  int get _autoImages =>
      _cards.where((_EditableCard card) => card.hasImages).length;

  /// Убирает все автоматически найденные изображения сразу.
  void _removeAllImages() {
    setState(() {
      for (final _EditableCard card in _cards) {
        card.questionImages = <GeneratedCardImage>[];
        card.answerImages = <GeneratedCardImage>[];
      }
    });
    showAppMessage(
      context,
      AppLocalizations.of(context).generationImagesRemoved,
    );
  }

  int get _imagesNotFound => _cards
      .where(
        (_EditableCard card) =>
            card.selected &&
            !card.hasImages &&
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

  /// Убирает изображение стороны — карточка импортируется без него (Д3/7.19).
  void _removeImage({required bool question, required int index}) {
    setState(() {
      final List<GeneratedCardImage> target = question
          ? <GeneratedCardImage>[..._cards[index].questionImages]
          : <GeneratedCardImage>[..._cards[index].answerImages];
      if (index < 0 || index >= target.length) return;
      target.removeAt(index);
      if (question) {
        _cards[index].questionImages = target;
      } else {
        _cards[index].answerImages = target;
      }
    });
  }

  /// Заменяет изображение стороны файлом JPG/PNG пользователя (Д3/7.19).
  Future<void> _replaceImage({
    required bool question,
    required int index,
  }) async {
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
        final GeneratedCardImage image = GeneratedCardImage(
          bytes: bytes,
          mediaType: mediaType,
          query: document.name,
        );
        final List<GeneratedCardImage> target = question
            ? <GeneratedCardImage>[..._cards[index].questionImages]
            : <GeneratedCardImage>[..._cards[index].answerImages];
        if (index < target.length) {
          target[index] = image;
        } else {
          target.add(image);
        }
        if (question) {
          _cards[index].questionImages = target;
        } else {
          _cards[index].answerImages = target;
        }
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
  /// она есть: она конкретнее общей формулировки причины. `Retry-After`
  /// добавляется, если провайдер его сообщил (TASK 03).
  String _failureMessage(
    AppLocalizations l10n,
    GenerationChunkFailure failure,
  ) {
    final String? providerReason = failure.providerReason?.trim();
    final String base;
    if (failure.code == GenerationErrorCode.badRequest &&
        providerReason != null &&
        providerReason.isNotEmpty) {
      base = generationErrorCodeMessage(
        l10n,
        failure.code,
        providerReason: providerReason,
      );
    } else {
      final GenerationFailureReason reason =
          failure.reason ?? GenerationFailureReason.forErrorCode(failure.code);
      base = generationFailureReasonMessage(l10n, reason);
    }
    final int? seconds = failure.retryAfter?.inSeconds;
    if (seconds == null || seconds <= 0) return base;
    return '$base (${l10n.generationFailureRetryAfter(seconds)})';
  }

  /// Постоянные баннеры состояния: частичный успех, fatal, изображения,
  /// калибровка токенов и восстановление (TASK 03, раздел 8).
  List<Widget> _statusWidgets(AppLocalizations l10n, ThemeData theme) {
    final List<Widget> widgets = <Widget>[];
    void add(String text, Key key, {Color? color}) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            key: key,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color ?? theme.colorScheme.tertiary,
            ),
          ),
        ),
      );
    }

    final GenerationErrorCode? fatal = _result.fatalErrorCode;
    if (fatal != null) {
      add(
        l10n.generationPreviewFatal(
          generationErrorCodeMessage(
            l10n,
            fatal,
            providerReason: _result.fatalProviderReason,
          ),
        ),
        const ValueKey<String>('generation-preview-fatal'),
        color: theme.colorScheme.error,
      );
    } else if (_result.status == GenerationJobStatus.partial) {
      add(
        l10n.generationPreviewPartial(
          _result.chunkCount,
          _result.failures.length,
        ),
        const ValueKey<String>('generation-preview-partial'),
      );
    }

    final GenerationPlan? plan = _result.plan;
    if (plan != null && plan.images.isNotEmpty) {
      add(
        l10n.generationPreviewImageSummary(
          plan.imagesSentToModel,
          plan.imagesCatalogOnly,
          plan.imagesUnsupported,
          plan.imagesOmitted,
        ),
        const ValueKey<String>('generation-preview-image-summary'),
      );
    }

    if (_result.recoveryRequestsUsed > 0) {
      add(
        l10n.generationPreviewRecovery(_result.recoveryRequestsUsed),
        const ValueKey<String>('generation-preview-recovery'),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final int chunkTotal = _result.chunkCount == 0
        ? _result.failures.length
        : _result.chunkCount;
    final int emptyCoverageSections = _result.sectionCoverage
        .where((cov) => cov.produced == 0 && cov.allocated > 0)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generationPreviewTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppSizes.formWidth(context)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              ..._statusWidgets(l10n, theme),
              if (_result.requestedCards > 0 &&
                  _result.requestedCards > _result.achievableCards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPlanRequestedAboveAchievable(
                      _result.requestedCards,
                      _result.achievableCards,
                    ),
                    key: const ValueKey<String>(
                      'generation-preview-plan-warning',
                    ),
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
              // §5 задания 7.20: фактически созданное количество и причина
              // недобора — материал исчерпан, а не «бюджет модели». Причиной
              // считается только исчерпание (`shortfallCards`/`skippedBatches`);
              // недобор из-за сбоев партий объясняется баннером частичного
              // успеха и материалом НЕ называется.
              if (_result.requestedCards > 0 &&
                  (_result.exhaustedSectionIds.isNotEmpty ||
                      _result.skippedBatches > 0))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPreviewMaterialExhausted(
                      _result.cards.length,
                      _result.requestedCards,
                    ),
                    key: const ValueKey<String>(
                      'generation-preview-material-exhausted',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              // Цель не достигнута без исчерпания материала и без отказов
              // партий: честно сообщаем недобор, не называя его материалом.
              if (_result.requestedCards > 0 &&
                  _result.cards.length < _result.requestedCards &&
                  _result.exhaustedSectionIds.isEmpty &&
                  _result.failures.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPreviewShortfall(
                      _result.cards.length,
                      _result.requestedCards,
                    ),
                    key: const ValueKey<String>('generation-preview-shortfall'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              if (_result.trimmedCards > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPreviewTrimmed(_result.trimmedCards),
                    key: const ValueKey<String>('generation-preview-trimmed'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              if (_result.sectionCoverage.isNotEmpty &&
                  emptyCoverageSections > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPreviewCoverage(
                      emptyCoverageSections,
                      _result.sectionCoverage.length,
                    ),
                    key: const ValueKey<String>('generation-preview-coverage'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              if (_result.plan != null && _result.plan!.hasOmittedUnits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.generationPlanOmittedUnits(
                      _result.plan!.omitted.length,
                    ),
                    key: const ValueKey<String>(
                      'generation-preview-plan-omitted',
                    ),
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
                      l10n.generationDuplicatesRemoved(
                        _result.duplicatesRemoved,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_result.rejectedCards > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.generationRejectedCards(_result.rejectedCards),
                      key: const ValueKey<String>(
                        'generation-preview-rejected',
                      ),
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
                if (_autoImages > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppPanel(
                      key: const ValueKey<String>(
                        'generation-preview-auto-images',
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.xs,
                        AppSpacing.xs,
                        AppSpacing.xs,
                      ),
                      color: theme.colorScheme.tertiaryContainer,
                      borderColor: theme.colorScheme.tertiaryContainer,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  l10n.generationImagesAutoTitle,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color:
                                        theme.colorScheme.onTertiaryContainer,
                                  ),
                                ),
                                Text(
                                  l10n.generationImagesAutoMessage,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: const ValueKey<String>(
                              'generation-preview-remove-all-images',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  theme.colorScheme.onTertiaryContainer,
                            ),
                            onPressed: _removeAllImages,
                            child: Text(l10n.generationRemoveAllImages),
                          ),
                        ],
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
                  key: const ValueKey<String>(
                    'generation-preview-retry-failed',
                  ),
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
                    onRemoveImage: (bool question, int imageIndex) =>
                        _removeImage(question: question, index: imageIndex),
                    onReplaceImage: (bool question, int imageIndex) =>
                        _replaceImage(question: question, index: imageIndex),
                  ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
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
                constraints: BoxConstraints(
                  maxWidth: AppSizes.wideFormWidth(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton(
                      key: const ValueKey<String>(
                        'generation-preview-import-all',
                      ),
                      onPressed: _importing || _cards.isEmpty
                          ? null
                          : () => _import(all: true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSizes.buttonHeightLarge,
                        ),
                      ),
                      child: Text(l10n.generationPreviewImportAll),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton(
                      key: const ValueKey<String>(
                        'generation-preview-import-selected',
                      ),
                      onPressed: _importing || _selectedCount == 0
                          ? null
                          : () => _import(all: false),
                      child: Text(l10n.generationPreviewImportSelected),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
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
  final void Function(bool question, int imageIndex) onRemoveImage;
  final void Function(bool question, int imageIndex) onReplaceImage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppPanel(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.xxs,
          AppSpacing.sm + 4,
          AppSpacing.sm,
        ),
        radius: AppRadii.input,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Аудит 2.0 (P2-20): подпись «Обычная» стояла рядом с чекбоксом и
            // читалась как переключатель типа. Теперь чекбокс называется
            // «Выбрать карточку», а тип — отдельный бейдж справа.
            Row(
              children: <Widget>[
                InkWell(
                  key: ValueKey<String>('generation-preview-select-$index'),
                  onTap: () => onSelected(!card.selected),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Checkbox(
                          key: ValueKey<String>(
                            'generation-preview-checkbox-$index',
                          ),
                          value: card.selected,
                          onChanged: (bool? value) =>
                              onSelected(value ?? false),
                        ),
                        Text(
                          l10n.generationSelectCard,
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppStatusChip(
                      label: card.original.isOcclusion
                          ? l10n.cardTypeOcclusion
                          : switch (card.original.cardType) {
                              CardType.basic => l10n.cardTypeBasic,
                              CardType.basicReversed =>
                                l10n.cardTypeBasicReversed,
                              CardType.cloze => l10n.cardTypeCloze,
                            },
                      tone: card.original.isOcclusion
                          ? AppStatusTone.info
                          : AppStatusTone.neutral,
                      dense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey<String>(
                    'generation-preview-replace-image-$index',
                  ),
                  tooltip: l10n.generationPreviewReplaceImage,
                  onPressed: () => onReplaceImage(true, 0),
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 20,
                  ),
                ),
              ],
            ),
            _PreviewSide(
              l10n: l10n,
              question: true,
              title: l10n.cardFormQuestionImages,
              images: card.questionImages,
              cardIndex: index,
              onRemoveImage: onRemoveImage,
              onReplaceImage: onReplaceImage,
            ),
            const SizedBox(height: 8),
            _PreviewSide(
              l10n: l10n,
              question: false,
              title: l10n.cardFormAnswerImages,
              images: card.answerImages,
              cardIndex: index,
              onRemoveImage: onRemoveImage,
              onReplaceImage: onReplaceImage,
            ),
            const SizedBox(height: 8),
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

/// Изображения одной стороны карточки в предпросмотре (7.19).
///
/// Предпросмотр показывает ровно то, что будет на экране обучения: изображения
/// вопроса — до переворота, изображения ответа — после.
class _PreviewSide extends StatelessWidget {
  const _PreviewSide({
    required this.l10n,
    required this.question,
    required this.title,
    required this.images,
    required this.cardIndex,
    required this.onRemoveImage,
    required this.onReplaceImage,
  });

  final AppLocalizations l10n;
  final bool question;
  final String title;
  final List<GeneratedCardImage> images;
  final int cardIndex;
  final void Function(bool question, int imageIndex) onRemoveImage;
  final void Function(bool question, int imageIndex) onReplaceImage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String prefix = question ? 'question' : 'answer';
    return Column(
      key: ValueKey<String>('generation-preview-$prefix-images-$cardIndex'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          titleWithCount(title, images.length),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (images.isEmpty)
          Text(
            question
                ? l10n.cardFormEmptyQuestionImages
                : l10n.cardFormEmptyAnswerImages,
            key: ValueKey<String>(
              'generation-preview-$prefix-empty-$cardIndex',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (var imageIndex = 0; imageIndex < images.length; imageIndex++)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Аудит 2.0 (P2-20/P3-10): подпись стороны повторялась второй
                // раз, а немые иконки не объясняли действие. Действия —
                // текстовые кнопки с иконкой и подписью.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.generationPreviewImageNumber(imageIndex + 1),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey<String>(
                        'generation-preview-remove-$prefix-$cardIndex-$imageIndex',
                      ),
                      onPressed: () => onRemoveImage(question, imageIndex),
                      icon: const Icon(Icons.hide_image_outlined, size: 18),
                      label: Text(l10n.generationPreviewRemoveShort),
                    ),
                    TextButton.icon(
                      key: ValueKey<String>(
                        'generation-preview-replace-$prefix-$cardIndex-$imageIndex',
                      ),
                      onPressed: () => onReplaceImage(question, imageIndex),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(l10n.generationPreviewReplaceShort),
                    ),
                  ],
                ),
                KeyedSubtree(
                  key: ValueKey<String>(
                    'generation-preview-$prefix-image-$cardIndex-$imageIndex',
                  ),
                  child: CardImageView(
                    bytes: images[imageIndex].bytes,
                    kind: images[imageIndex].kind,
                    maxHeight: 140,
                    metadata: MediaMetadata(
                      provider: images[imageIndex].provider,
                      sourceUrl: images[imageIndex].sourceUrl,
                      author: images[imageIndex].author,
                      license: images[imageIndex].license,
                      query: images[imageIndex].query,
                      fallbackQuery: images[imageIndex].fallbackQuery,
                      kind: images[imageIndex].kind,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Подпись секции стороны с числом изображений (без литералов в UI).
String titleWithCount(String title, int count) => '$title ($count)';

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
    CardIssueCode.imageDuplicatedSide =>
      l10n.generationIssueImageDuplicatedSide,
    CardIssueCode.imageInvalid => l10n.generationIssueImageInvalid,
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
