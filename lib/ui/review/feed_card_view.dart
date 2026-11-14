import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';

/// Карточка ленты: свайпы-оценки, пружина, морфинг формы, 3D-flip (SPEC A7.3).
///
/// Красная фаза итерации 4: контракт виджета зафиксирован тестами.
class FeedCardView extends StatefulWidget {
  /// Создаёт карточку ленты.
  const FeedCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.rated,
    required this.rating,
    required this.enabled,
    required this.resetToken,
    required this.onTap,
    required this.onRate,
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Оценена ли карточка.
  final bool rated;

  /// Оценка карточки, если она оценена.
  final Rating? rating;

  /// Доступны ли жесты (не идёт запись и карточка не оценена).
  final bool enabled;

  /// Счётчик сброса анимации после ошибки записи.
  final int resetToken;

  /// Тап по карточке (раскрыть/скрыть ответ).
  final VoidCallback onTap;

  /// Оценка свайпом.
  final ValueChanged<Rating> onRate;

  @override
  State<FeedCardView> createState() => _FeedCardViewState();
}

class _FeedCardViewState extends State<FeedCardView> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
