import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

ParsedDocument docOf(String name, int sections, int wordsCount) {
  final List<String> words = List<String>.filled(wordsCount, 'слово');
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> parsed = <ParsedSection>[];
  for (var index = 0; index < sections; index++) {
    if (index > 0) buffer.write('\n\n');
    final int start = buffer.length;
    buffer.write('Раздел $index. ${words.join(' ')}');
    parsed.add(ParsedSection(start: start, end: buffer.length));
  }
  return ParsedDocument(
    format: DocumentFormat.txt,
    fileName: name,
    text: buffer.toString(),
    sections: parsed,
  );
}

void main() {
  final ProviderAccount account = ProviderAccount.fromPreset(
    providerPresetById('deepseek')!,
    id: 'deepseek',
    modelId: 'deepseek-chat',
  );
  final GenerationPlan plan = const GenerationPlanBuilder().build(
    documents: <ParsedDocument>[
      for (var doc = 0; doc < 3; doc++) docOf('d$doc.txt', 8, 1500),
    ],
    capabilities: resolveModelCapabilities(account),
    requestedCards: 150,
    wishes: 'Нужно 150 карточек',
  );
  print('materials: strategy=${plan.inputStrategy} parts=${plan.partCount} chunks=${plan.chunks.length}');
  final GenerationPlan promptOnly = const GenerationPlanBuilder().buildPromptOnly(
    request: const PromptOnlyRequest(prompt: 'фотосинтез', requestedCards: 500),
    capabilities: resolveModelCapabilities(account),
  );
  print('promptOnly chunks=${promptOnly.chunks.length} planned=${promptOnly.plannedCards}');
  for (final PlannedChunk chunk in promptOnly.chunks.take(3)) {
    print('  pchunk#${chunk.index} limit=${chunk.limit}');
  }
}
