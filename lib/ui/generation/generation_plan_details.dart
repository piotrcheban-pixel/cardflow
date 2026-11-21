/// Раскрывающийся блок «Подробнее» карточки «План генерации» (§3.10/§2.5).
///
/// Показывает числа **того же** [GenerationPlan], что и production-конвейер:
/// модель, источники лимитов с датой проверки, контекст, точность входа,
/// стратегию, части/партии/запросы, статусы изображений, оценку токенов и
/// стоимость (только если тариф известен), неизвестные лимиты. Второго
/// оценщика здесь нет — всё берётся из плана.
library;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/plan_warning_message.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Блок «Подробнее» плана генерации.
class GenerationPlanDetails extends StatelessWidget {
  /// Создаёт блок; [model] — выбранная модель, [limits] — её разрешённые
  /// лимиты (для источников и даты проверки), `null` — только план.
  const GenerationPlanDetails({
    required this.plan,
    required this.model,
    this.limits,
    super.key,
  });

  /// План генерации (тот же объект, что исполняет конвейер).
  final GenerationPlan plan;

  /// Отображаемое имя модели.
  final String model;

  /// Разрешённые лимиты модели с происхождением.
  final ModelLimits? limits;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? caption = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ExpansionTile(
      key: const ValueKey<String>('generation-plan-details'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      initiallyExpanded: false,
      title: Text(l10n.generationPlanDetails),
      children: <Widget>[
        _DetailRow(
          id: 'plan-detail-model',
          label: l10n.generationPlanDetailsModel,
          value: model.isEmpty ? l10n.generationPlanDetailsUnknownValue : model,
        ),
        _DetailRow(
          id: 'plan-detail-context',
          label: l10n.generationPlanDetailsContext,
          value: _sourced(l10n, limits?.contextTokens),
        ),
        _DetailRow(
          id: 'plan-detail-input',
          label: l10n.generationPlanDetailsInputTokens,
          value: _inputLine(l10n),
        ),
        // §3: число провайдера, оценка и резерв — отдельные строки. Плановый
        // бюджет не выдаётся за результат нативного подсчёта.
        if (_nativeInputTokens case final int native)
          _DetailRow(
            id: 'plan-detail-input-native',
            label: l10n.generationPlanDetailsNativeCountLabel,
            value: l10n.generationPlanDetailsInputExact(native),
          ),
        if (_estimatedExtraTokens > 0)
          _DetailRow(
            id: 'plan-detail-input-extra',
            label: l10n.generationPlanDetailsEstimatedExtraLabel,
            value: l10n.generationPlanDetailsInputEstimatedExtra(
              _estimatedExtraTokens,
              _componentsLabel(l10n),
            ),
          ),
        if (_nativeInputTokens != null) ...<Widget>[
          _DetailRow(
            id: 'plan-detail-input-margin',
            label: l10n.generationPlanDetailsMarginLabel,
            value: l10n.generationPlanDetailsInputMargin(_marginTokens),
          ),
          _DetailRow(
            id: 'plan-detail-input-budget',
            label: l10n.generationPlanDetailsBudgetLabel,
            value: l10n.generationPlanDetailsInputBudget(_budgetTokens),
          ),
        ],
        _DetailRow(
          id: 'plan-detail-strategy',
          label: l10n.generationPlanDetailsStrategy,
          value: _strategy(l10n),
        ),
        _DetailRow(
          id: 'plan-detail-parts',
          label: l10n.generationPlanDetailsParts,
          value: '${plan.partCount}',
        ),
        _DetailRow(
          id: 'plan-detail-batches',
          label: l10n.generationPlanDetailsBatches,
          value: '${plan.chunks.length}',
        ),
        // §4 задания 7.20: заказ, сумма плана, вместимость партии и её
        // распределение видны явно — «запрошено 40» не подменяется 32/16.
        if (plan.requestedCards > 0)
          _DetailRow(
            id: 'plan-detail-cards-requested',
            label: l10n.generationPlanDetailsCardsRequested,
            value: '${plan.requestedCards}',
          ),
        _DetailRow(
          id: 'plan-detail-cards-planned',
          label: l10n.generationPlanDetailsCardsPlanned,
          value: '${plan.plannedCards}',
        ),
        if (plan.chunks.isNotEmpty)
          _DetailRow(
            id: 'plan-detail-cards-per-batch',
            label: l10n.generationPlanDetailsCardsPerBatch,
            value: '${plan.cardsPerBatchMax}',
          ),
        if (plan.chunks.isNotEmpty)
          _DetailRow(
            id: 'plan-detail-batch-sizes',
            label: l10n.generationPlanDetailsBatchSizes,
            value: _batchSizes(l10n),
          ),
        _DetailRow(
          id: 'plan-detail-material-capacity',
          label: l10n.generationPlanDetailsMaterialCapacity,
          value: _materialCapacity(l10n),
        ),
        _DetailRow(
          id: 'plan-detail-requests',
          label: l10n.generationPlanDetailsRequests,
          value: '${plan.plannedRequests} (+${plan.retryAllowanceRequests})',
        ),
        if (plan.images.isNotEmpty)
          _DetailRow(
            id: 'plan-detail-images',
            label: l10n.generationPlanDetailsImagesLabel,
            value: l10n.generationPlanDetailsImages(
              plan.imagesSentToModel,
              plan.imagesCatalogOnly,
              plan.imagesUnsupported,
              plan.imagesOmitted,
            ),
          ),
        _DetailRow(
          id: 'plan-detail-tokens',
          label: l10n.generationPlanDetailsTokensLabel,
          value: '${plan.estimate.totalTokens}',
        ),
        // §3.4: каталог изображений — часть `D`; резерв рассуждения — часть
        // `max_tokens`. Оба числа видны, чтобы «Подробнее» сходилось с запросом.
        _DetailRow(
          id: 'plan-detail-catalog',
          label: l10n.generationPlanDetailsCatalogTokens,
          value: '${plan.estimate.catalogTokens}',
        ),
        if (plan.reasoningReserveTokens > 0)
          _DetailRow(
            id: 'plan-detail-reasoning',
            label: l10n.generationPlanDetailsReasoningReserve,
            value: '${plan.reasoningReserveTokens}',
          ),
        _DetailRow(
          id: 'plan-detail-cost',
          label: l10n.generationPlanDetailsCostLabel,
          value: _cost(l10n),
        ),
        _DetailRow(
          id: 'plan-detail-sources',
          label: l10n.generationPlanDetailsSourcesLabel,
          value: _sources(l10n),
        ),
        if (_unknownLimits(l10n) case final String unknown
            when unknown.isNotEmpty)
          _DetailRow(
            id: 'plan-detail-unknown-limits',
            label: l10n.generationPlanDetailsUnknownLimitsLabel,
            value: unknown,
            emphasized: true,
          ),
        if (plan.validity.warnings.isNotEmpty)
          _DetailRow(
            id: 'plan-detail-warnings',
            label: l10n.generationPlanDetailsWarningsLabel,
            value: planWarningMessages(l10n, plan).join('; '),
            emphasized: true,
          ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.generationPlanDetailsNote,
          style: caption,
          key: const ValueKey<String>('plan-detail-note'),
        ),
      ],
    );
  }

  String _inputLine(AppLocalizations l10n) {
    final InputPlan? inputPlan = plan.inputPlan;
    final int? native = inputPlan?.nativeInputTokens;
    if (native != null) {
      final int estimated = inputPlan!.estimatedExtraTokens;
      if (estimated > 0) {
        return l10n.generationPlanDetailsInputMixed(native, estimated);
      }
      return l10n.generationPlanDetailsInputExact(native);
    }
    final int tokens =
        inputPlan?.inputTokens ??
        plan.plannedInputTokens ??
        plan.estimate.totalTokens;
    return l10n.generationPlanDetailsInputEstimated(tokens);
  }

  InputPlan? get _inputPlan => plan.inputPlan;

  int? get _nativeInputTokens => _inputPlan?.nativeInputTokens;

  int get _estimatedExtraTokens => _inputPlan?.estimatedExtraTokens ?? 0;

  int get _marginTokens => _inputPlan?.marginTokens ?? 0;

  int get _budgetTokens =>
      _inputPlan?.effectiveBudgetTokens ??
      plan.plannedInputTokens ??
      plan.estimate.totalTokens;

  String _componentsLabel(AppLocalizations l10n) => <String>[
    for (final String component
        in _inputPlan?.estimatedComponents ?? <String>[])
      switch (component) {
        NativeInputCount.schemaComponent =>
          l10n.generationPlanDetailsComponentResponseSchema,
        'images' => l10n.generationPlanDetailsComponentImages,
        _ => component,
      },
  ].join(', ');

  /// Распределение карточек по партиям (первые 12, остальное — числом).
  String _batchSizes(AppLocalizations l10n) {
    final List<int> sizes = plan.batchSizes;
    const int visible = 12;
    final String head = sizes.take(visible).join(', ');
    if (sizes.length <= visible) return head;
    return l10n.generationPlanDetailsBatchSizesOverflow(
      head,
      sizes.length - visible,
    );
  }

  /// Оценка содержательной ёмкости материала (не бюджет модели).
  String _materialCapacity(AppLocalizations l10n) {
    final int? capacity = plan.materialCapacity;
    if (capacity == null) {
      return l10n.generationPlanDetailsMaterialCapacityUnknown;
    }
    return l10n.generationPlanDetailsMaterialCapacityValue(capacity);
  }

  String _strategy(AppLocalizations l10n) {
    return switch (plan.inputStrategy) {
      InputStrategy.wholeDocument => l10n.generationPlanDetailsStrategyWhole,
      InputStrategy.fragmented => l10n.generationPlanDetailsStrategyFragmented,
      InputStrategy.promptOnly => l10n.generationPlanDetailsStrategyPromptOnly,
      null => l10n.generationPlanDetailsUnknownValue,
    };
  }

  String _cost(AppLocalizations l10n) {
    final double? total = plan.estimate.totalCost;
    final String? currency = plan.estimate.currency;
    if (total == null || currency == null) {
      return l10n.generationPlanDetailsCostUnknown;
    }
    return l10n.generationPlanDetailsCost('$total $currency');
  }

  String _sourced(AppLocalizations l10n, Sourced<int>? value) {
    if (value == null) return l10n.generationPlanDetailsUnknownValue;
    final int? tokens = value.value;
    if (tokens == null) return l10n.generationPlanDetailsUnknownValue;
    final String source = capabilitySourceLabel(l10n, value.source);
    final DateTime? observed = value.observedAt;
    final String date = observed == null
        ? ''
        : ' · ${l10n.settingsCapabilitiesCheckedAt(_date(observed))}';
    return '${_formatTokens(tokens)} — $source$date';
  }

  String _sources(AppLocalizations l10n) {
    final List<String> parts = <String>[
      for (final MapEntry<String, CapabilitySource> entry
          in plan.capabilitySources.entries)
        '${entry.key}: ${capabilitySourceLabel(l10n, entry.value)}',
    ];
    return parts.isEmpty
        ? l10n.generationPlanDetailsUnknownValue
        : parts.join('; ');
  }

  String _unknownLimits(AppLocalizations l10n) {
    final List<String> fields = <String>{
      ...plan.unknownFields,
      if (limits != null) ...limits!.unknownFields,
    }.toList(growable: false);
    return fields.join(', ');
  }

  static String _formatTokens(int value) {
    final String digits = value.toString();
    final StringBuffer buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(' ');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  static String _date(DateTime value) {
    final DateTime local = value.toLocal();
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.id,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String id;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: ValueKey<String>(id),
              style: theme.textTheme.bodySmall?.copyWith(
                color: emphasized
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
