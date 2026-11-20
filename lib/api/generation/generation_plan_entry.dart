/// Единая точка построения плана запуска (7.18.1 §2.5, §0.11).
///
/// Предпросмотр на экране генерации и production-конвейер используют **один**
/// и тот же объект [GenerationPlan] и один и тот же сборщик сообщения: функция
/// ниже выбирает prompt-only или материаловый путь по тому же правилу, что
/// `GenerationPipeline`, и не имеет собственного оценщика.
library;

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';

/// Есть ли у запуска материалы (файлы, вложения, изображения документов).
bool runHasMaterials(GenerationRunRequest request) =>
    request.documents.isNotEmpty ||
    request.images.isNotEmpty ||
    request.documentImages.isNotEmpty;

/// Тема prompt-only (непустые пожелания) или `null`.
String? runTopic(String? wishes) {
  final String text = wishes?.trim() ?? '';
  return text.isEmpty ? null : text;
}

/// Строит план запуска; `null` — ни материалов, ни темы (вызывающий покажет
/// `noMaterials`).
///
/// [exactInputTokens]/[inputTokenSource] передаются, когда провайдер умеет
/// считать вход (`count_tokens`): тот же builder пересобирает план с точным
/// значением, второй оценки не появляется.
GenerationPlan? buildRunPlan({
  required GenerationPlanBuilder builder,
  required GenerationRunRequest request,
  required ModelCapabilities capabilities,
  int? exactInputTokens,
  String? inputTokenSource,
}) {
  final bool hasMaterials = runHasMaterials(request);
  final String? topic = runTopic(request.wishes);
  final int? requested =
      request.requestedCards ?? requestedCardCount(request.wishes);
  if (!hasMaterials) {
    if (topic == null) return null;
    return builder.buildPromptOnly(
      request: PromptOnlyRequest(prompt: topic, requestedCards: requested),
      capabilities: capabilities,
      exactInputTokens: exactInputTokens,
      inputTokenSource: inputTokenSource,
    );
  }
  return builder.build(
    documents: request.documents,
    capabilities: capabilities,
    attachments: request.images,
    documentImages: request.documentImages,
    wishes: request.wishes,
    requestedCards: requested,
    exactInputTokens: exactInputTokens,
    inputTokenSource: inputTokenSource,
  );
}
