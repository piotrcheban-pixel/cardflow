import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/archive_error_message.dart';
import 'package:cardflow/ui/decks/deck_archive_file_name.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Действия над колодами (SPEC A6.2/A6.3/A6.9): диалоги, экспорт, импорт.
///
/// Пользовательские тексты — только из [AppLocalizations]; ошибки архива
/// маппятся в ARB (`archiveErrorMessage`), прочие — в общую строку. Сырые
/// исключения наружу не выводятся. Диалоги — `NcDialog` (REDESIGN-SPEC §9.2),
/// сигнатуры функций и типы результатов прежние.

/// Показывает короткое сообщение тостом Nocturne (`NcToast`, §8).
void showAppMessage(BuildContext context, String message) {
  showNcToast(context, message: message, duration: const Duration(seconds: 4));
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
      (await showNcDialog<bool>(
        context,
        title: l10n.deckDeleteDialogTitle,
        message: l10n.deckDeleteDialogMessage(deck.name),
        icon3dName: 'shield_error',
        actions: <Widget>[
          NcButton(
            key: const ValueKey<String>('delete-deck-cancel'),
            label: l10n.cancel,
            variant: NcButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NcButton(
            key: const ValueKey<String>('delete-deck-confirm'),
            label: l10n.delete,
            variant: NcButtonVariant.destructive,
            onPressed: () => Navigator.of(context).pop(true),
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

/// Тост после архивации с действием «Отменить» (восстанавливает колоду).
void showArchivedUndoSnackbar(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  showNcToast(
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
  final AppLocalizations l10n = AppLocalizations.of(context);
  final GlobalKey<_DeckNameFieldState> fieldKey =
      GlobalKey<_DeckNameFieldState>();

  void submit() {
    final String? name = fieldKey.currentState?.trySubmit();
    if (name == null) return;
    Navigator.of(context).pop(name);
  }

  return showNcDialog<String>(
    context,
    title: title,
    content: _DeckNameField(key: fieldKey, initialName: initialName),
    actions: <Widget>[
      NcButton(
        label: l10n.cancel,
        variant: NcButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(),
      ),
      NcButton(
        key: const ValueKey<String>('deck-name-submit'),
        label: submitLabel,
        onPressed: submit,
      ),
    ],
  );
}

/// Поле имени колоды с собственной валидацией (Enter = отправка).
class _DeckNameField extends StatefulWidget {
  const _DeckNameField({super.key, required this.initialName});

  final String initialName;

  @override
  State<_DeckNameField> createState() => _DeckNameFieldState();
}

class _DeckNameFieldState extends State<_DeckNameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Возвращает обрезанное имя или `null`, если оно пустое.
  String? trySubmit() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.deckNameEmptyError);
      return null;
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcTextField(
      controller: _controller,
      autofocus: true,
      label: l10n.deckNameLabel,
      errorText: _errorText,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        final String? name = trySubmit();
        if (name != null) Navigator.of(context).pop(name);
      },
    );
  }
}

/// Диалог предпросмотра импорта; `true` — пользователь подтвердил импорт.
Future<bool> _showImportPreviewDialog(
  BuildContext context,
  ImportPreview preview,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showNcDialog<bool>(
    context,
    title: l10n.importPreviewTitle,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PreviewLine(text: l10n.importPreviewDeckName(preview.deckName)),
        _PreviewLine(
          text: l10n.importPreviewFormatVersion(preview.formatVersion),
        ),
        _PreviewLine(text: l10n.importPreviewCards(preview.cardsCount)),
        _PreviewLine(
          text: l10n.importPreviewDuplicates(preview.duplicatesCount),
        ),
        _PreviewLine(text: l10n.importPreviewMedia(preview.mediaCount)),
      ],
    ),
    actions: <Widget>[
      NcButton(
        key: const ValueKey<String>('import-cancel'),
        label: l10n.cancel,
        variant: NcButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      NcButton(
        key: const ValueKey<String>('import-confirm'),
        label: l10n.importConfirm,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return confirmed ?? false;
}

/// Строка сводки предпросмотра импорта.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.typography.bodyM.copyWith(
          color: theme.colors.textSecondary,
        ),
      ),
    );
  }
}
