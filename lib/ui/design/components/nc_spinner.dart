import 'package:material_ui/material_ui.dart';

/// Тонкое кольцо ожидания с градиентом `aurum` (REDESIGN-SPEC §8).
///
/// Для инлайн-ожидания: кнопки, проверка ключа, догрузка строки. Кольцо
/// вращается; в тестах — только `pump(Duration)`, не `pumpAndSettle` (§6.4).
class NcSpinner extends StatefulWidget {
  /// Создаёт спиннер.
  const NcSpinner({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color,
    this.semanticLabel,
    this.period = const Duration(milliseconds: 900),
  });

  /// Сторона кольца.
  final double size;

  /// Толщина кольца.
  final double strokeWidth;

  /// Базовый цвет (по умолчанию `aurum`).
  final Color? color;

  /// Текст семантики (из ARB, например «Загрузка»).
  final String? semanticLabel;

  /// Период полного оборота.
  final Duration period;

  @override
  State<NcSpinner> createState() => _NcSpinnerState();
}

class _NcSpinnerState extends State<NcSpinner>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
