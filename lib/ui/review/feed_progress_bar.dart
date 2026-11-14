import 'package:material_ui/material_ui.dart';

/// Stories-прогресс ленты (SPEC A7.3): сегмент на карточку, текущий пульсирует.
///
/// Красная фаза итерации 4: контракт виджета зафиксирован тестами.
class FeedProgressBar extends StatelessWidget {
  /// Создаёт прогресс ленты.
  const FeedProgressBar({
    required this.rated,
    required this.currentIndex,
    super.key,
  });

  /// Оценена ли карточка с каждым индексом.
  final List<bool> rated;

  /// Индекс текущей карточки.
  final int currentIndex;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
