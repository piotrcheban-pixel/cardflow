import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/archive_error_message.dart';
import 'package:cardflow/ui/decks/deck_archive_file_name.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Действия над колодами (SPEC A6.2/A6.3/A6.9): диалоги, экспорт, импорт.
///
/// Пользовательские тексты — только из [AppLocalizations]; ошибки архива
/// маппятся в ARB (`archiveErrorMessage`), прочие — в общую строку. Сырые
/// исключения наружу не выводятся.

/// Показывает короткое сообщение снекбаром (M3 Expressive).
void showAppMessage(BuildContext context, String message) {
  M3ESnackbar.show(
    context,
    message: message,
    duration: const Duration(seconds: 4),
  );
}

/// Диалог создания колоды вручную; возвращает созданную колоду.
Future<Deck?> createDeckManually(BuildContext context, WidgetRef ref) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String? name = await _showDeckNameDialog(
    context,
    title: l10n.deckCreateDialogTitle,
    submitLabel: l10n.decksCreateButton,
  );
  if (name == null || !context.mounted) return null;
  try {
    return await ref.read(deckRepositoryProvider).createDeck(name: name);
  } catch (_) {
    if (context.mounted) showAppMessage(context, l10n.genericError);
    return null;
  }
}

/// Диалог переименования колоды; `true` — имя сохранено.
Future<bool> renameDeck(
  BuildContext context,
  WidgetRef ref, {
  required Deck deck,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String? name = await _showDeckNameDialog(
    context,
    title: l10n.deckRenameDialogTitle,
    initialName: deck.name,
    submitLabel: l10n.save,
  );
  if (name == null || !context.mounted) return false;
  try {
    await ref.read(deckRepositoryProvider).renameDeck(id: deck.id, name: name);
    return true;
  } catch (_) {
    if (context.mounted) showAppMessage(context, l10n.genericError);
    return false;
  }
}

/// Диалог удаления колоды с подтверждением; `true` — колода удалена.
Future<bool> deleteDeckWithConfirmation(
  BuildContext context,
  WidgetRef ref, {
  required Deck deck,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool confirmed =
      (await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.deckDeleteDialogTitle),
          content: Text(l10n.deckDeleteDialogMessage(deck.name)),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('delete-deck-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey<String>('delete-deck-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      )) ??
      false;
  if (confirmed != true || !context.mounted) return false;
  try {
    await ref.read(deckRepositoryProvider).deleteDeck(deck.id);
    return true;
  } catch (_) {
    if (context.mounted) showAppMessage(context, l10n.genericError);
    return false;
  }
}

/// Снекбар после архивации с действием «Отменить» (восстанавливает колоду).
void showArchivedUndoSnackbar(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  M3ESnackbar.show(
    context,
    message: l10n.deckArchivedMessage,
    actionLabel: l10n.undo,
    duration: const Duration(seconds: 8),
    onAction: () async {
      try {
        await ref.read(deckRepositoryProvider).unarchiveDeck(deckId);
      } catch (_) {
        if (context.mounted) showAppMessage(context, l10n.genericError);
      }
    },
  );
}

/// Экспорт колоды: ZIP-байты → системный диалог сохранения (шлюз сам пишет
/// файл; на мобильных платформах — через `content://`).
///
/// Отмена сохранения — тихий no-op (без снекбара).
Future<void> exportDeckZip(
  BuildContext context,
  WidgetRef ref, {
  required Deck deck,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  try {
    final bytes = await ref
        .read(deckTransferServiceProvider)
        .exportDeckZip(deck.id);
    final String suggestedFileName = deckArchiveFileName(
      deck.name,
      fallbackName: l10n.deckDefaultFileName,
    );
    final bool saved = await ref
        .read(fileGatewayProvider)
        .saveZipFile(suggestedFileName: suggestedFileName, bytes: bytes);
    if (!saved || !context.mounted) return;
    showAppMessage(context, l10n.deckExportSuccess);
  } catch (error) {
    if (context.mounted) {
      showAppMessage(context, archiveErrorMessage(l10n, error));
    }
  }
}

/// Импорт колоды: пикер → чтение → предпросмотр → импорт → переход в колоду.
///
/// Отмена выбора файла и отмена в предпросмотре — тихий no-op.
Future<void> importDeckZip(BuildContext context, WidgetRef ref) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  try {
    final String? path = await ref.read(fileGatewayProvider).pickZipToImport();
    if (path == null || !context.mounted) return;
    final bytes = await ref.read(fileGatewayProvider).readFile(path);
    final ImportPreview preview = await ref
        .read(deckTransferServiceProvider)
        .previewImport(bytes);
    if (!context.mounted) return;
    final bool confirmed = await _showImportPreviewDialog(context, preview);
    if (!confirmed || !context.mounted) return;
    final ImportResult result = await ref
        .read(deckTransferServiceProvider)
        .importZip(bytes);
    if (!context.mounted) return;
    showAppMessage(context, l10n.deckImportSuccess);
    context.push('/decks/${result.deckId}');
  } catch (error) {
    if (context.mounted) {
      showAppMessage(context, archiveErrorMessage(l10n, error));
    }
  }
}

/// Диалог ввода имени колоды; возвращает обрезанное имя или `null` при отмене.
Future<String?> _showDeckNameDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  String initialName = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _DeckNameDialog(
      title: title,
      submitLabel: submitLabel,
      initialName: initialName,
    ),
  );
}

/// Диалог имени колоды с собственным жизненным циклом контроллера.
///
/// Контроллер освобождается в `dispose` виджета, а не сразу после `pop`:
/// диалог продолжает анимационно закрываться, и `TextField` ещё жив.
class _DeckNameDialog extends StatefulWidget {
  const _DeckNameDialog({
    required this.title,
    required this.submitLabel,
    required this.initialName,
  });

  final String title;
  final String submitLabel;
  final String initialName;

  @override
  State<_DeckNameDialog> createState() => _DeckNameDialogState();
}

class _DeckNameDialogState extends State<_DeckNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.deckNameEmptyError);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.deckNameLabel,
          errorText: _errorText,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('deck-name-submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

/// Диалог предпросмотра импорта; `true` — пользователь подтвердил импорт.
Future<bool> _showImportPreviewDialog(
  BuildContext context,
  ImportPreview preview,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(l10n.importPreviewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.importPreviewDeckName(preview.deckName)),
          const SizedBox(height: 8),
          Text(l10n.importPreviewFormatVersion(preview.formatVersion)),
          const SizedBox(height: 8),
          Text(l10n.importPreviewCards(preview.cardsCount)),
          const SizedBox(height: 8),
          Text(l10n.importPreviewDuplicates(preview.duplicatesCount)),
          const SizedBox(height: 8),
          Text(l10n.importPreviewMedia(preview.mediaCount)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('import-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('import-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.importConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
