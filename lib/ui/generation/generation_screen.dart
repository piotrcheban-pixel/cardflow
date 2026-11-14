/// Экран «Генерация карточек» (SPEC A6.8).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Единый поток генерации: файлы → пожелания → провайдер/модель → генерация.
class GenerationScreen extends ConsumerStatefulWidget {
  /// Создаёт экран; [deckId] задан — карточки добавляются в существующую колоду.
  const GenerationScreen({this.deckId, super.key});

  /// Целевая колода; `null` — создать новую.
  final String? deckId;

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generationTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
