import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Этап пути генерации v3 (TASK «Срез 9», п. 2).
///
/// Порядок отражает ARCH §2: анализ материала → план → генерация → проверка.
enum GenerationV3Stage {
  /// Разбор материалов и построение модели документа.
  analysis,

  /// План частей и партий (до первого запроса).
  planning,

  /// Запросы к модели и приём карточек.
  generating,

  /// Проверка карточек, дедупликация и вердикт.
  validation,
}

/// Степпер этапов генерации v3 и счётчик «принято N из M».
///
/// Показывается только при включённом флаге `generationPipelineV3`: старый путь
/// сохраняет прежний индикатор прогресса без изменений (протокол §9).
class GenerationV3ProgressView extends StatelessWidget {
  /// Создаёт степпер.
  const GenerationV3ProgressView({
    required this.phase,
    required this.accepted,
    this.requested = 0,
    this.finishing = false,
    super.key,
  });

  /// Текущая фаза прогресса старого конвейера (источник этапа).
  final GenerationProgressPhase? phase;

  /// Принято карточек прямо сейчас.
  final int accepted;

  /// Запрошено карточек (0 — авто-режим: счётчик не показывается).
  final int requested;

  /// true — запросы завершены, идёт проверка/вердикт.
  final bool finishing;

  /// Этап по фазе прогресса: единственное место с этим правилом.
  static GenerationV3Stage stageFor(
    GenerationProgressPhase? phase, {
    bool finishing = false,
  }) {
    if (finishing) return GenerationV3Stage.validation;
    return switch (phase) {
      GenerationProgressPhase.chunking => GenerationV3Stage.analysis,
      GenerationProgressPhase.sending ||
      GenerationProgressPhase.receiving => GenerationV3Stage.generating,
      null => GenerationV3Stage.planning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final GenerationV3Stage current = stageFor(phase, finishing: finishing);
    final int currentIndex = current.index;
    return Column(
      key: const ValueKey<String>('generation-v3-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.generationStageTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final GenerationV3Stage stage in GenerationV3Stage.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              key: ValueKey<String>(
                'generation-v3-stage-${stage.name}-'
                '${stage.index < currentIndex
                    ? 'done'
                    : stage.index == currentIndex
                    ? 'current'
                    : 'pending'}',
              ),
              children: <Widget>[
                Icon(
                  stage.index < currentIndex
                      ? Icons.check_circle
                      : stage.index == currentIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: AppSizes.iconSmall,
                  color: stage.index <= currentIndex
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    _label(l10n, stage),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: stage.index <= currentIndex
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: stage.index == currentIndex
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (requested > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.generationProgressCardsCount(accepted, requested),
            key: const ValueKey<String>('generation-v3-accepted'),
            style: AppTypography.numeric(context),
          ),
        ],
      ],
    );
  }

  String _label(AppLocalizations l10n, GenerationV3Stage stage) {
    return switch (stage) {
      GenerationV3Stage.analysis => l10n.generationStageAnalysis,
      GenerationV3Stage.planning => l10n.generationStagePlanning,
      GenerationV3Stage.generating => l10n.generationStageGenerating,
      GenerationV3Stage.validation => l10n.generationStageValidation,
    };
  }
}
