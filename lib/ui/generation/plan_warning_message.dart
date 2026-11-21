/// Человекочитаемые предупреждения плана генерации (7.18.3 §4).
///
/// Один маппинг для экрана генерации и блока «Подробнее»: коды
/// [PlanWarningCode] не показываются пользователю латиницей, каждому коду —
/// строка ARB. Числа берутся из того же [GenerationPlan], второй оценки нет.
library;

import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Сообщение предупреждения [code] для плана [plan]; `null` — код без текста.
String? planWarningMessage(
  AppLocalizations l10n,
  GenerationPlan plan,
  PlanWarningCode code,
) => switch (code) {
  PlanWarningCode.unknownCapabilities => l10n.generationPlanUnknownCapabilities,
  PlanWarningCode.assumedImageLimits => l10n.generationPlanAssumedImageLimits,
  PlanWarningCode.imagesWithoutVision => l10n.generationPlanNoVisionImages(
    plan.imagesUnsupported,
  ),
  PlanWarningCode.imagesVisionUnconfirmed =>
    l10n.generationPlanVisionUnconfirmed,
  PlanWarningCode.catalogOnlyImages => l10n.generationPlanCatalogOnlyImages(
    plan.imagesCatalogOnly,
  ),
  PlanWarningCode.omittedUnits => l10n.generationPlanOmittedUnits(
    plan.omitted.length,
  ),
  PlanWarningCode.requestedAbovePlan =>
    l10n.generationPlanRequestedAboveAchievable(
      plan.requestedCards,
      plan.achievableCards,
    ),
  PlanWarningCode.cardsAboveRequested =>
    l10n.generationPlanAchievableAboveRequested(
      plan.requestedCards,
      plan.achievableCards,
    ),
  PlanWarningCode.contextUnconfirmed => l10n.generationPlanContextUnconfirmed,
  PlanWarningCode.payloadLimited => l10n.generationPlanPayloadLimited,
};

/// Все предупреждения плана строками (в порядке кодов).
List<String> planWarningMessages(
  AppLocalizations l10n,
  GenerationPlan plan,
) => <String>[
  for (final PlanWarningCode code in plan.validity.warnings)
    if (planWarningMessage(l10n, plan, code) case final String message) message,
];
