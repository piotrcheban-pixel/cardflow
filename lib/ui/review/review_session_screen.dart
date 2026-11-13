import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Экран классической сессии повторения (SPEC A6.4, A7.2).
///
/// Красная фаза итерации 2: заглушка — раскладка scaffold, flip-карточка,
/// 4 кнопки с прогнозом, undo и диалоги появятся в зелёной фазе.
class ReviewSessionScreen extends ConsumerWidget {
  /// Создаёт экран сессии для колоды [deckId].
  const ReviewSessionScreen({required this.deckId, super.key});

  /// Идентификатор колоды.
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: Center(child: Text(l10n.reviewEmptyTitle)),
    );
  }
}
