/// Экран предпросмотра сгенерированных карточек (SPEC A6.8).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Предпросмотр: чекбоксы, инлайн-редактирование, импорт.
class GenerationPreviewScreen extends ConsumerStatefulWidget {
  /// Создаёт экран предпросмотра.
  const GenerationPreviewScreen({
    required this.request,
    required this.result,
    super.key,
  });

  /// Исходный запрос (провайдер/модель/колода).
  final GenerationRunRequest request;

  /// Результат генерации.
  final GenerationRunResult result;

  @override
  ConsumerState<GenerationPreviewScreen> createState() =>
      _GenerationPreviewScreenState();
}

class _GenerationPreviewScreenState
    extends ConsumerState<GenerationPreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generationPreviewTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
