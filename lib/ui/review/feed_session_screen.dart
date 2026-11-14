import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Экран режима «Лента» (SPEC A7.3, ADR-016).
///
/// Красная фаза итерации 4: контракт экрана зафиксирован тестами.
class FeedSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран ленты для колоды [deckId].
  const FeedSessionScreen({required this.deckId, super.key});

  /// Идентификатор колоды.
  final String deckId;

  @override
  ConsumerState<FeedSessionScreen> createState() => _FeedSessionScreenState();
}

class _FeedSessionScreenState extends ConsumerState<FeedSessionScreen> {
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
