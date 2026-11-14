/// Экран предпросмотра сгенерированных карточек (SPEC A6.8, ADR-015).
///
/// Чекбоксы, инлайн-редактирование front/back, пометки A8.4, импорт всех или
/// выбранных карточек одной транзакцией, частичный успех с повтором упавших
/// фрагментов. Все сообщения — из ARB.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' show CardType;
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/generation/generation_error_message.dart';
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
      selected = true;

  final GeneratedCard original;
  final TextEditingController front;
  final TextEditingController back;
  bool selected;

  void dispose() {
    front.dispose();
    back.dispose();
  }

  /// Карточка с текущими правками пользователя.
  GeneratedCard toCard() {
    return GeneratedCard(
      front: front.text.trim(),
      back: back.text.trim(),
      cardType: original.cardType,
      hint: original.hint,
      tags: original.tags,
      sourceExcerpt: original.sourceExcerpt,
      sourceFile: original.sourceFile,
      issues: original.issues,
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

  Future<void> _retryFailed() async {
    if (_retrying) return;
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
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _retrying = false);
      showAppMessage(context, l10n.generationErrorGeneric);
    }
  }

  Future<void> _import({required bool all}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_importing) return;
    final List<_EditableCard> picked = all
        ? List<_EditableCard>.of(_cards)
        : _cards.where((_EditableCard card) => card.selected).toList();
    if (picked.isEmpty) {
      showAppMessage(context, l10n.generationPreviewNoSelection);
      return;
    }
    final List<GeneratedCard> cards = <GeneratedCard>[];
    for (final _EditableCard card in picked) {
      final GeneratedCard candidate = card.toCard();
      final CardDraft draft = CardDraft(
        front: candidate.front,
        back: candidate.back,
        cardType: candidate.cardType,
        tags: candidate.tags,
      );
      if (!draft.isValid) {
        showAppMessage(context, l10n.generationPreviewValidationError);
        return;
      }
      cards.add(candidate);
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
      showAppMessage(context, l10n.generationImported(imported.importedCards));
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generationPreviewTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
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
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.generationTokensUsed(_result.tokensUsed),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _cards.length; i++)
              _PreviewCardTile(
                key: ValueKey<String>('generation-preview-card-$i'),
                card: _cards[i],
                index: i,
                onSelected: (bool selected) =>
                    setState(() => _cards[i].selected = selected),
              ),
          ],
          if (_result.failures.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              l10n.generationFailuresTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _result.failures.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.generationFailureChunk(
                    _result.failures[i].chunkIndex,
                    generationErrorCodeMessage(l10n, _result.failures[i].code),
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
          ],
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
                onPressed: _importing || _result.cards.isEmpty
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
                onPressed: _importing || _result.cards.isEmpty
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

/// Карточка предпросмотра: чекбокс, поля front/back, пометки.
class _PreviewCardTile extends StatelessWidget {
  const _PreviewCardTile({
    required this.card,
    required this.index,
    required this.onSelected,
    super.key,
  });

  final _EditableCard card;
  final int index;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
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
                    switch (card.original.cardType) {
                      CardType.basic => l10n.cardTypeBasic,
                      CardType.basicReversed => l10n.cardTypeBasicReversed,
                      CardType.cloze => l10n.cardTypeCloze,
                    },
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
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
  };
}
