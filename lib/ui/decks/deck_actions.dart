import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/decks/archive_error_message.dart';
import 'package:cardflow/ui/decks/deck_archive_file_name.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Действия над колодами (SPEC A6.2/A6.3/A6.9): диалоги, экспорт, импорт.
///
/// Пользовательские тексты — только из [AppLocalizations]; ошибки архива
/// маппятся в ARB (`archiveErrorMessage`), прочие — в общую строку. Сырые
/// исключения наружу не выводятся.

/// Ширина снекбара: на широком окне уведомление не растягивается на всю
/// ширину (аудит 2.0, P2-21: тёмная полоса 1250 px с текстом в 150).
const double kAppSnackBarMaxWidth = 520;

/// Показывает короткое сообщение снекбаром темы (F23: одна система
/// уведомлений — тот же inverseSurface и поля, что у `SessionNotice`).
///
/// Аудит 2.0 (P2-21): снекбар прижат к нижнему левому краю и ограничен
/// [kAppSnackBarMaxWidth]; текст получает ширину строки, а не полосы окна.
void showAppMessage(BuildContext context, String message) {
  final double windowWidth = MediaQuery.sizeOf(context).width;
  final double width = math.min(kAppSnackBarMaxWidth, windowWidth - 32);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: windowWidth >= 640 ? width : null,
        content: Text(message),
      ),
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
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool confirmed =
      (await showAppDialog<bool>(
        context: context,
        title: l10n.deckDeleteDialogTitle,
        subtitle: l10n.deckDeleteDialogMessage(deck.name),
        bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
        // F12/F37: один компонент диалога, опасное действие — error-заливка,
        // безопасное — нейтральный текст; крестика нет (закрытие — «Отмена»).
        actionsBuilder: (BuildContext dialogContext) => <Widget>[
          TextButton(
            key: const ValueKey<String>('delete-deck-cancel'),
            style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey<String>('delete-deck-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
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
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.deckArchivedMessage),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () async {
            try {
              await ref.read(deckRepositoryProvider).unarchiveDeck(deckId);
            } catch (_) {
              if (context.mounted) showAppMessage(context, l10n.genericError);
            }
          },
        ),
      ),
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
        .saveZipFile(
          suggestedFileName: suggestedFileName,
          bytes: bytes,
          dialogTitle: l10n.deckExportPickerTitle,
        );
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
    final String? path = await ref
        .read(fileGatewayProvider)
        .pickZipToImport(dialogTitle: l10n.deckImportPickerTitle);
    if (path == null || !context.mounted) {
      // Находка F13: отмена выбора файла больше не «молчит».
      if (context.mounted) showAppMessage(context, l10n.deckImportCancelled);
      return;
    }
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
    final ThemeData theme = Theme.of(context);
    return AppDialog(
      title: widget.title,
      bodyBuilder: (BuildContext dialogContext) => TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.deckNameLabel,
          errorText: _errorText,
        ),
      ),
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(),
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
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool? confirmed = await showAppDialog<bool>(
    context: context,
    title: l10n.importPreviewTitle,
    bodyBuilder: (BuildContext dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.importPreviewDeckName(preview.deckName)),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.importPreviewFormatVersion(preview.formatVersion)),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.importPreviewCards(preview.cardsCount)),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.importPreviewDuplicates(preview.duplicatesCount)),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.importPreviewMedia(preview.mediaCount)),
      ],
    ),
    actionsBuilder: (BuildContext dialogContext) => <Widget>[
      TextButton(
        key: const ValueKey<String>('import-cancel'),
        style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: Text(l10n.cancel),
      ),
      FilledButton(
        key: const ValueKey<String>('import-confirm'),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: Text(l10n.importConfirm),
      ),
    ],
  );
  return confirmed ?? false;
}

/// Действия контекстного меню колоды (V8: одно меню на всех экранах).
enum DeckMenuAction { rename, export, archive, delete }

/// Показывает единое контекстное меню колоды — нижний лист в стиле системы.
///
/// И «Колоды» (сетка), и экран «Колода» (шапка) используют этот лист, поэтому
/// механизм, порядок и оформление действий совпадают. [includeArchive] = false
/// на экране самой колоды: архивировать открытую колоду из её же меню не нужно.
Future<DeckMenuAction?> showDeckContextMenu(
  BuildContext context, {
  required String deckName,
  bool includeArchive = true,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showAppSheet<DeckMenuAction>(
    context: context,
    builder: (BuildContext sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSheetHeader(title: deckName, icon: Icons.style_outlined),
        ListTile(
          key: const ValueKey<String>('deck-menu-rename'),
          leading: const Icon(Icons.edit_outlined),
          title: Text(l10n.deckRename),
          onTap: () => Navigator.of(sheetContext).pop(DeckMenuAction.rename),
        ),
        ListTile(
          key: const ValueKey<String>('deck-menu-export'),
          leading: const Icon(Icons.ios_share),
          title: Text(l10n.deckExport),
          onTap: () => Navigator.of(sheetContext).pop(DeckMenuAction.export),
        ),
        if (includeArchive)
          ListTile(
            key: const ValueKey<String>('deck-menu-archive'),
            leading: const Icon(Icons.archive_outlined),
            title: Text(l10n.deckActionArchive),
            onTap: () => Navigator.of(sheetContext).pop(DeckMenuAction.archive),
          ),
        ListTile(
          key: const ValueKey<String>('deck-menu-delete'),
          leading: const Icon(Icons.delete_outline),
          title: Text(l10n.delete),
          onTap: () => Navigator.of(sheetContext).pop(DeckMenuAction.delete),
        ),
      ],
    ),
  );
}
