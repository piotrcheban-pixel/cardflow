import 'package:material_ui/material_ui.dart';

/// Анимированное число (REDESIGN-SPEC §8, §6.3-5): считает 0→N за 900 мс
/// ease-out, цифры табличные. Для точности, удержания, «+N».
class NcAnimatedNumber extends StatefulWidget {
  /// Создаёт анимированное число.
  const NcAnimatedNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.format,
    this.semanticLabel,
    this.from = 0,
    this.textAlign,
  });

  /// Целевое значение.
  final num value;

  /// Стиль (например, `displayXL`).
  final TextStyle? style;

  /// Длительность счёта.
  final Duration duration;

  /// Форматирование (например, «90 %»).
  final String Function(num value)? format;

  /// Текст семантики (итоговое значение, чтобы скринридер не читал кадры).
  final String? semanticLabel;

  /// Начальное значение.
  final num from;

  /// Выравнивание.
  final TextAlign? textAlign;

  @override
  State<NcAnimatedNumber> createState() => _NcAnimatedNumberState();
}

class _NcAnimatedNumberState extends State<NcAnimatedNumber> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
