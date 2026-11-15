/// Экран «Генерация карточек» (SPEC A6.8, ADR-015).
///
/// Поток: прикрепить файлы (picker/DnD) → дождаться локального парсинга →
/// пожелания, провайдер/модель, имя колоды → оценка токенов → генерация с
/// прогрессом/отменой → экран предпросмотра. Все тексты — из ARB; ошибки
/// файлов и провайдера показываются кодами без сырых исключений.
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart'
    show kImageTokenEstimate;
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart' show showAppMessage;
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/generation/generation_error_message.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/generation/parser_error_message.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';

/// Порог предупреждения о большом объёме материалов (SPEC A8.5 шаг 4).
const int _largeMaterialTokenThreshold = 100000;

/// Порог «PDF-скан»: меньше символов текста — отправляем страницы как PNG
/// (итерация 7.9, ADR-023).
const int kPdfScanMinTextLength = 50;

/// Статус локального парсинга прикреплённого файла.
enum _FileStatus { parsing, parsed, image, scanned, pdfPages, failed }

/// Прикреплённый файл и результат его парсинга.
class _AttachedFile {
  _AttachedFile(this.picked);

  final PickedDocument picked;
  _FileStatus status = _FileStatus.parsing;
  ParsedDocument? document;

  /// Вложения файла: JPG/PNG, PDF-скан или отрендеренные страницы PDF.
  List<GenerationAttachment> attachments = const <GenerationAttachment>[];
  ParserErrorCode? errorCode;
}

/// Экран генерации карточек.
class GenerationScreen extends ConsumerStatefulWidget {
  /// Создаёт экран; [deckId] задан — карточки добавляются в существующую колоду.
  const GenerationScreen({this.deckId, super.key});

  /// Целевая колода; `null` — создать новую.
  final String? deckId;

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen> {
  final TokenEstimator _estimator = const TokenEstimator();
  final TextEditingController _wishesController = TextEditingController();
  final TextEditingController _deckNameController = TextEditingController();

  final List<_AttachedFile> _files = <_AttachedFile>[];

  /// Наличие ключей по id аккаунта (только present/absent, без значений).
  Map<String, bool> _keyConfigured = <String, bool>{};

  /// Настроенные провайдеры (ADR-020).
  ProviderAccounts _accounts = ProviderAccounts.empty;

  /// Выбранный аккаунт; `null` — провайдеры не настроены.
  ProviderAccount? _account;
  String? _modelId;
  bool _loading = true;
  bool _configError = false;
  bool _generating = false;
  bool _dragging = false;
  GenerationCancellation? _cancellation;
  GenerationProgress? _progress;
  int? _actualTokens;

  @override
  void initState() {
    super.initState();
    _loadProviderConfig();
  }

  @override
  void dispose() {
    _wishesController.dispose();
    _deckNameController.dispose();
    super.dispose();
  }

  /// Читает настроенных провайдеров и наличие их ключей.
  ///
  /// [preserveSelection] — не сбрасывать выбранного провайдера/модель после
  /// возврата с экрана настроек (A6.8, ADR-020).
  Future<void> _loadProviderConfig({bool preserveSelection = false}) async {
    try {
      final ProviderAccounts accounts = await ref.read(
        providerAccountsProvider.future,
      );
      final ApiKeyStore keyStore = ref.read(apiKeyStoreProvider);
      final Map<String, bool> configured = <String, bool>{};
      for (final ProviderAccount account in accounts.accounts) {
        final String? key = await keyStore.read(account.id);
        configured[account.id] = key != null && key.isNotEmpty;
      }
      if (!mounted) return;
      final ProviderAccount? previous = preserveSelection ? _account : null;
      final ProviderAccount? selected =
          (previous == null ? null : accounts.accountById(previous.id)) ??
          accounts.active;
      setState(() {
        _accounts = accounts;
        _keyConfigured = configured;
        _account = selected;
        _modelId = selected?.modelId;
        _loading = false;
        _configError = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _configError = true;
      });
    }
  }

  /// Аккаунт для запроса: выбранная модель с контекстом из каталога.
  ProviderAccount? get _requestAccount {
    final ProviderAccount? account = _account;
    if (account == null) return null;
    final String modelId = (_modelId ?? account.modelId).trim();
    final ProviderPresetModel? model = account.preset?.modelById(modelId);
    return account.copyWith(
      modelId: modelId,
      contextTokens: model?.contextTokens ?? account.contextTokens,
      supportsVision: model?.supportsVision ?? account.supportsVision,
    );
  }

  /// Провайдеры не настроены.
  bool get _noProvider => _account == null;

  /// Аккаунт неполный (нет адреса/модели).
  bool get _accountNotConfigured => _account != null && !_account!.isConfigured;

  bool get _providerNeedsKey {
    final ProviderAccount? account = _account;
    if (account == null) return false;
    return account.requiresApiKey && !(_keyConfigured[account.id] ?? false);
  }

  List<ParsedDocument> get _parsedDocuments => <ParsedDocument>[
    for (final _AttachedFile file in _files)
      if (file.status == _FileStatus.parsed && file.document != null)
        file.document!,
  ];

  /// Вложения: изображения, PDF-сканы и страницы PDF-сканов.
  List<GenerationAttachment> get _attachments => <GenerationAttachment>[
    for (final _AttachedFile file in _files)
      if (file.status == _FileStatus.image ||
          file.status == _FileStatus.scanned ||
          file.status == _FileStatus.pdfPages)
        ...file.attachments,
  ];

  /// Есть ли материалы для генерации (текст или вложения).
  bool get _hasContent =>
      _parsedDocuments.isNotEmpty || _attachments.isNotEmpty;

  /// Есть ли файлы, которые ещё читаются/парсятся.
  bool get _anyParsing =>
      _files.any((_AttachedFile file) => file.status == _FileStatus.parsing);

  int get _estimatedTokens =>
      _estimator.estimateAll(
        _parsedDocuments.map((ParsedDocument document) => document.text),
      ) +
      _attachments.length * kImageTokenEstimate +
      _estimator.estimate(systemPromptGenRuV2) +
      kPromptWrapperTokenReserve;

  Future<void> _pickFiles() async {
    try {
      final List<PickedDocument> picked = await ref
          .read(documentGatewayProvider)
          .pickDocuments();
      if (!mounted) return;
      if (picked.isNotEmpty) await _attach(picked);
    } on Object {
      if (!mounted) return;
      showAppMessage(
        context,
        AppLocalizations.of(context).parserErrorUnreadableFile,
      );
    }
  }

  /// Обрабатывает drag-n-drop на ПК (директории пропускаются).
  Future<void> _handleDrop(DropDoneDetails details) async {
    if (_generating) return;
    final picked = <PickedDocument>[];
    for (final DropItem item in details.files) {
      if (item is DropItemDirectory) continue;
      final int length = await item.length();
      picked.add(
        PickedDocument(
          path: item.path,
          name: item.name.isEmpty ? p.basename(item.path) : item.name,
          sizeBytes: length,
        ),
      );
    }
    if (picked.isNotEmpty && mounted) await _attach(picked);
  }

  /// Добавляет файлы (без дублей по пути) и запускает парсинг.
  Future<void> _attach(List<PickedDocument> picked) async {
    final List<_AttachedFile> added = <_AttachedFile>[];
    for (final PickedDocument document in picked) {
      final bool exists = _files.any(
        (_AttachedFile file) => file.picked.path == document.path,
      );
      if (exists) continue;
      final _AttachedFile file = _AttachedFile(document);
      _files.add(file);
      added.add(file);
    }
    if (added.isEmpty) return;
    setState(() {});
    for (final _AttachedFile file in added) {
      await _parse(file);
    }
  }

  /// Парсит один файл; изображения и PDF-сканы сохраняются как вложения.
  Future<void> _parse(_AttachedFile file) async {
    try {
      final bytes = await ref
          .read(documentGatewayProvider)
          .readDocument(file.picked);
      if (!mounted) return;
      final AttachmentMediaType? imageType = attachmentMediaTypeForFileName(
        file.picked.name,
      );
      if (imageType != null) {
        final bool valid = hasValidAttachmentSignature(imageType, bytes);
        setState(() {
          if (!valid) {
            file
              ..status = _FileStatus.failed
              ..errorCode = ParserErrorCode.unreadableFile;
            return;
          }
          file
            ..status = _FileStatus.image
            ..attachments = <GenerationAttachment>[
              GenerationAttachment(
                fileName: file.picked.name,
                mediaType: imageType,
                bytes: bytes,
              ),
            ];
        });
        return;
      }
      final ParsingOutcome outcome = await ref
          .read(fileParsingServiceProvider)
          .parseFile(
            FileParsingInput(fileName: file.picked.name, bytes: bytes),
          );
      if (!mounted) return;
      if (outcome is ParsedFileSuccess) {
        final bool shortPdfScan =
            outcome.document.format == DocumentFormat.pdf &&
            outcome.document.text.trim().length < kPdfScanMinTextLength;
        if (shortPdfScan) {
          await _attachPdfPages(file, bytes);
          return;
        }
        setState(() {
          file
            ..status = _FileStatus.parsed
            ..document = outcome.document;
        });
        return;
      }
      final ParsedFileFailure failure = outcome as ParsedFileFailure;
      final bool scannedPdf =
          failure.code == ParserErrorCode.scannedPdf &&
          documentFormatFromFileName(file.picked.name) == DocumentFormat.pdf;
      if (scannedPdf) {
        // PDF без текстового слоя: сначала пробуем отрендерить страницы в PNG
        // для Vision-моделей; при неудаче — fallback на PDF-документ для
        // протоколов Anthropic/Gemini (ADR-022/ADR-023).
        await _attachPdfPages(file, bytes);
        return;
      }
      setState(() {
        file
          ..status = _FileStatus.failed
          ..errorCode = failure.code;
      });
    } on ParserException catch (error) {
      if (!mounted) return;
      setState(() {
        file
          ..status = _FileStatus.failed
          ..errorCode = error.code;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        file
          ..status = _FileStatus.failed
          ..errorCode = ParserErrorCode.unreadableFile;
      });
    }
  }

  /// Рендерит страницы PDF-скана в PNG; при неудаче — fallback на PDF.
  Future<void> _attachPdfPages(_AttachedFile file, Uint8List bytes) async {
    try {
      final List<Uint8List> pages = await ref
          .read(fileParsingServiceProvider)
          .renderPdfPages(bytes, fileName: file.picked.name);
      if (!mounted) return;
      final List<GenerationAttachment> attachments = <GenerationAttachment>[
        for (var index = 0; index < pages.length; index++)
          if (hasValidAttachmentSignature(
            AttachmentMediaType.png,
            pages[index],
          ))
            GenerationAttachment(
              fileName: file.picked.name,
              mediaType: AttachmentMediaType.png,
              bytes: pages[index],
              pageNumber: index + 1,
              groupKey: file.picked.path,
            ),
      ];
      if (attachments.isNotEmpty) {
        setState(() {
          file
            ..status = _FileStatus.pdfPages
            ..attachments = List<GenerationAttachment>.unmodifiable(
              attachments,
            );
        });
        return;
      }
    } on Object {
      // Ниже — fallback на PDF-документ, если протокол его принимает.
    }
    if (!mounted) return;
    setState(() {
      file
        ..status = _FileStatus.scanned
        ..attachments = <GenerationAttachment>[
          GenerationAttachment(
            fileName: file.picked.name,
            mediaType: AttachmentMediaType.pdf,
            bytes: bytes,
          ),
        ];
    });
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  Future<void> _openSettings() async {
    await context.push(AppRoutes.generationSettingsPath);
    if (mounted) await _loadProviderConfig(preserveSelection: true);
  }

  Future<void> _generate() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_generating || _loading) return;
    final List<ParsedDocument> documents = _parsedDocuments;
    final List<GenerationAttachment> attachments = _attachments;
    if (_files.isEmpty) {
      showAppMessage(context, l10n.generationNoFilesError);
      return;
    }
    if (_anyParsing) {
      showAppMessage(context, l10n.generationFilesParsing);
      return;
    }
    if (documents.isEmpty && attachments.isEmpty) {
      showAppMessage(context, l10n.generationNoParsedFilesError);
      return;
    }
    if (_providerNeedsKey) {
      showAppMessage(context, l10n.generationKeyMissing);
      return;
    }
    final ProviderAccount? account = _requestAccount;
    if (account == null || !account.isConfigured) {
      showAppMessage(context, l10n.generationErrorProviderNotConfigured);
      return;
    }
    final bool hasPdfDocuments = attachments.any(
      (GenerationAttachment attachment) => attachment.isPdf,
    );
    final bool hasPdfPages = attachments.any(
      (GenerationAttachment attachment) => attachment.isPdfPage,
    );
    if (attachments.isNotEmpty && !account.supportsVision) {
      final String message;
      if (hasPdfPages) {
        message = l10n.generationErrorPdfScanVisionRequired;
      } else if (hasPdfDocuments) {
        message = l10n.generationErrorFileWithoutTextAndVision;
      } else {
        message = l10n.generationErrorVisionUnsupported;
      }
      showAppMessage(context, message);
      return;
    }
    if (hasPdfDocuments && !account.protocol.supportsPdfAttachments) {
      showAppMessage(context, l10n.generationErrorPdfScanUnsupported);
      return;
    }
    final String deckName = widget.deckId == null
        ? _resolveDeckName(l10n, documents, attachments)
        : '';
    final String? wishes = _wishesController.text.trim().isEmpty
        ? null
        : _wishesController.text.trim();
    final GenerationRunRequest request = GenerationRunRequest(
      documents: documents,
      images: attachments,
      account: account,
      deckName: deckName,
      wishes: wishes,
      targetDeckId: widget.deckId,
    );

    final GenerationRunner runner = ref.read(generationRunnerProvider);
    final GenerationCancellation cancellation = GenerationCancellation();
    setState(() {
      _generating = true;
      _progress = const GenerationProgress(
        phase: GenerationProgressPhase.chunking,
      );
      _cancellation = cancellation;
      _actualTokens = null;
    });
    try {
      final GenerationRunResult result = await runner.run(
        request,
        onProgress: (GenerationProgress progress) {
          if (mounted) setState(() => _progress = progress);
        },
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _generating = false;
        _progress = null;
        _actualTokens = result.tokensUsed;
      });
      if (result.cancelled && result.cards.isEmpty) {
        showAppMessage(context, l10n.generationCancelled);
        return;
      }
      if (result.fatalErrorCode != null && result.cards.isNotEmpty) {
        showAppMessage(
          context,
          generationErrorCodeMessage(
            l10n,
            result.fatalErrorCode!,
            providerReason: result.fatalProviderReason,
          ),
        );
      }
      if (result.cards.isEmpty) {
        if (result.failures.isNotEmpty) {
          // Все фрагменты упали: предпросмотр покажет ошибки и «Повторить
          // неудавшиеся» вместо ложного «пустого ответа» (A6.8).
          await _openPreview(request, result);
          return;
        }
        if (result.duplicatesRemoved > 0) {
          showAppMessage(
            context,
            l10n.generationDuplicatesRemoved(result.duplicatesRemoved),
          );
          return;
        }
        // Валидный ответ модели с пустым массивом cards (правило 13 промпта):
        // материалы без фактов (скан/пустая форма), а не пустой ответ
        // провайдера — повтор не поможет (ADR-021).
        showAppMessage(context, l10n.generationNoCardsFound);
        return;
      }
      await _openPreview(request, result);
    } on GenerationException catch (error) {
      if (!mounted) return;
      setState(() => _generating = false);
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
      setState(() => _generating = false);
      showAppMessage(context, l10n.generationErrorGeneric);
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _cancellation = null;
        });
      }
    }
  }

  /// Открывает предпросмотр и переходит в колоду после импорта.
  Future<void> _openPreview(
    GenerationRunRequest request,
    GenerationRunResult result,
  ) async {
    final GenerationImportResult? imported = await Navigator.of(context)
        .push<GenerationImportResult>(
          MaterialPageRoute<GenerationImportResult>(
            builder: (BuildContext context) =>
                GenerationPreviewScreen(request: request, result: result),
          ),
        );
    if (imported != null && mounted && GoRouter.maybeOf(context) != null) {
      context.go(AppRoutes.deckPath(imported.deckId));
    }
  }

  String _resolveDeckName(
    AppLocalizations l10n,
    List<ParsedDocument> documents,
    List<GenerationAttachment> attachments,
  ) {
    final String typed = _deckNameController.text.trim();
    if (typed.isNotEmpty) return typed;
    final String? fileName = documents.isNotEmpty
        ? documents.first.fileName
        : attachments.isNotEmpty
        ? attachments.first.fileName
        : null;
    if (fileName != null) {
      final String base = p.basenameWithoutExtension(fileName);
      if (base.trim().isNotEmpty) return base.trim();
    }
    return l10n.generationDeckDefaultName;
  }

  void _cancel() {
    _cancellation?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Deck? targetDeck = widget.deckId == null
        ? null
        : ref.watch(deckProvider(widget.deckId!)).value;
    return PopScope(
      canPop: !_generating,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _generating) {
          _cancellation?.cancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.generationTitle)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _configError
            ? _buildConfigError(context, l10n)
            : _buildForm(context, l10n, targetDeck),
        bottomNavigationBar: _loading || _configError
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _buildActions(l10n),
                ),
              ),
      ),
    );
  }

  /// Ошибка чтения ключей/настроек: сообщение ARB и повтор.
  Widget _buildConfigError(BuildContext context, AppLocalizations l10n) {
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
            Text(l10n.settingsLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey<String>('generation-config-retry'),
              onPressed: () {
                setState(() {
                  _loading = true;
                  _configError = false;
                });
                _loadProviderConfig();
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  /// Нижняя панель действий: «Сгенерировать» или прогресс + «Отмена».
  Widget _buildActions(AppLocalizations l10n) {
    if (_generating) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ProgressView(progress: _progress, l10n: l10n),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey<String>('generation-cancel'),
            onPressed: _cancel,
            child: Text(l10n.cancel),
          ),
        ],
      );
    }
    return FilledButton(
      key: const ValueKey<String>('generation-start'),
      onPressed: _anyParsing ? null : _generate,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
      ),
      child: Text(l10n.generationStart),
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l10n,
    Deck? targetDeck,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool hasContent = _hasContent;
    final int estimate = _estimatedTokens;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _handleDrop,
      enable: !_generating,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('generation-attach-zone'),
            onTap: _generating ? null : _pickFiles,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _dragging
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerLow,
                border: Border.all(
                  color: _dragging
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.upload_file_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.generationAttachHint, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    l10n.generationAttachButton,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_noProvider || _accountNotConfigured) ...<Widget>[
            _KeyBanner(
              key: const ValueKey<String>('generation-provider-banner'),
              message: l10n.generationErrorProviderNotConfigured,
              actionLabel: l10n.generationOpenSettings,
              onAction: _openSettings,
            ),
            const SizedBox(height: 12),
          ] else if (_providerNeedsKey) ...<Widget>[
            _KeyBanner(
              key: const ValueKey<String>('generation-key-banner'),
              message: l10n.generationKeyMissing,
              actionLabel: l10n.generationOpenSettings,
              onAction: _openSettings,
            ),
            const SizedBox(height: 12),
          ],
          if (_files.isEmpty)
            Text(
              l10n.generationFilesEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var i = 0; i < _files.length; i++)
              _FileTile(
                key: ValueKey<String>('generation-file-tile-$i'),
                file: _files[i],
                index: i,
                onRemove: _generating ? null : () => _removeFile(i),
              ),
          const SizedBox(height: 16),
          if (widget.deckId == null)
            TextField(
              key: const ValueKey<String>('generation-deck-name'),
              controller: _deckNameController,
              enabled: !_generating,
              decoration: InputDecoration(
                labelText: l10n.generationDeckNameLabel,
                hintText: l10n.generationDeckNameHint,
                border: _fieldBorder,
              ),
            )
          else
            Text(l10n.generationTargetDeck(targetDeck?.name ?? '')),
          if (hasContent) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.generationEstimate(estimate),
              key: const ValueKey<String>('generation-estimate'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (estimate > _largeMaterialTokenThreshold) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              l10n.generationEstimateWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey<String>('generation-wishes'),
            controller: _wishesController,
            minLines: 2,
            maxLines: 4,
            enabled: !_generating,
            decoration: InputDecoration(
              labelText: l10n.generationWishesLabel,
              hintText: l10n.generationWishesHint,
              border: _fieldBorder,
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.generationProviderLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ProviderAccount account in _accounts.accounts)
                ChoiceChip(
                  key: ValueKey<String>('generation-provider-${account.id}'),
                  avatar: Icon(
                    providerProtocolIcon(account.protocol),
                    size: 18,
                  ),
                  label: Text(providerAccountLabel(l10n, account)),
                  selected: _account?.id == account.id,
                  onSelected: _generating
                      ? null
                      : (bool selected) {
                          if (!selected) return;
                          setState(() {
                            _account = account;
                            _modelId = account.modelId;
                          });
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_account?.preset != null)
            DropdownButtonFormField<String>(
              key: ValueKey<String>('generation-model-${_account?.preset?.id}'),
              initialValue: _modelId ?? _account?.modelId,
              decoration: InputDecoration(
                labelText: l10n.generationModelLabel,
                border: _fieldBorder,
              ),
              items: <DropdownMenuItem<String>>[
                for (final ProviderPresetModel model
                    in _account?.preset?.models ??
                        const <ProviderPresetModel>[])
                  DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label),
                  ),
              ],
              onChanged: _generating
                  ? null
                  : (String? value) => setState(() => _modelId = value),
            )
          else
            InputDecorator(
              key: const ValueKey<String>('generation-model-fixed'),
              decoration: InputDecoration(
                labelText: l10n.generationModelLabel,
                helperText: l10n.generationModelProviderHint,
                border: _fieldBorder,
              ),
              child: Text(_account?.modelId ?? ''),
            ),
          const SizedBox(height: 16),
          if (_actualTokens != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.generationTokensUsed(_actualTokens!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static OutlineInputBorder get _fieldBorder =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(16));
}

/// Одна строка списка прикреплённых файлов со статусом парсинга.
class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.index,
    required this.onRemove,
    super.key,
  });

  final _AttachedFile file;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final DocumentFormat? format = documentFormatFromFileName(file.picked.name);
    final AttachmentMediaType? imageType = attachmentMediaTypeForFileName(
      file.picked.name,
    );
    final String status = switch (file.status) {
      _FileStatus.parsing => l10n.generationFileParsing,
      _FileStatus.parsed => l10n.generationFileParsed,
      _FileStatus.image => l10n.generationFileImage,
      _FileStatus.scanned => l10n.generationFileScannedPdf,
      _FileStatus.pdfPages => l10n.generationFilePdfPages,
      _FileStatus.failed => parserErrorCodeMessage(
        l10n,
        file.errorCode ?? ParserErrorCode.unreadableFile,
      ),
    };
    final String? size = file.picked.sizeBytes <= 0
        ? null
        : formatFileSize(l10n, file.picked.sizeBytes);
    return ListTile(
      leading: Icon(
        imageType == null ? _formatIcon(format) : Icons.image_outlined,
      ),
      title: Text(file.picked.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (size != null) Text(size),
          Text(
            status,
            style: file.status == _FileStatus.failed
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : null,
          ),
        ],
      ),
      trailing: IconButton(
        key: ValueKey<String>('generation-file-remove-$index'),
        tooltip: l10n.generationFileRemoveTooltip,
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }

  IconData _formatIcon(DocumentFormat? format) {
    return switch (format) {
      DocumentFormat.pdf => Icons.picture_as_pdf_outlined,
      DocumentFormat.docx || DocumentFormat.odt => Icons.description_outlined,
      DocumentFormat.xlsx => Icons.table_chart_outlined,
      DocumentFormat.pptx => Icons.slideshow_outlined,
      DocumentFormat.rtf ||
      DocumentFormat.txt ||
      DocumentFormat.md => Icons.text_snippet_outlined,
      DocumentFormat.doc || DocumentFormat.xls => Icons.block_outlined,
      null => Icons.insert_drive_file_outlined,
    };
  }
}

/// Форматирует размер файла строкой ARB.
String formatFileSize(AppLocalizations l10n, int sizeBytes) {
  if (sizeBytes < 1024) return l10n.generationFileSizeBytes(sizeBytes);
  if (sizeBytes < 1024 * 1024) {
    return l10n.generationFileSizeKb((sizeBytes / 1024).ceil());
  }
  return l10n.generationFileSizeMb((sizeBytes / (1024 * 1024)).ceil());
}

/// Баннер «ключ не задан / сервер не настроен» с переходом в настройки.
class _KeyBanner extends StatelessWidget {
  const _KeyBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('generation-key-missing'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.key_off_outlined,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          TextButton(
            key: const ValueKey<String>('generation-open-settings'),
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// Индикатор прогресса генерации.
class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.progress, required this.l10n});

  final GenerationProgress? progress;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final GenerationProgress? value = progress;
    final String text;
    switch (value?.phase) {
      case GenerationProgressPhase.sending:
        text = l10n.generationProgressSending(
          value?.chunkIndex ?? 1,
          value?.chunkCount ?? 1,
        );
      case GenerationProgressPhase.receiving:
        text = l10n.generationProgressReceiving;
      case GenerationProgressPhase.chunking:
      case null:
        text = l10n.generationProgressReading;
    }
    return Column(
      key: const ValueKey<String>('generation-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
      ],
    );
  }
}
