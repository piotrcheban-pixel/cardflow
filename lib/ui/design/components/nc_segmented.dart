import 'package:material_ui/material_ui.dart';

/// Сегмент `NcSegmented` (REDESIGN-SPEC §8).
@immutable
class NcSegment<T> {
  /// Создаёт сегмент.
  const NcSegment({
    required this.value,
    required this.label,
    this.leading,
    this.enabled = true,
    this.key,
    this.semanticLabel,
  });

  /// Значение сегмента.
  final T value;

  /// Текст сегмента (ARB).
  final String label;

  /// Иконка/превью перед текстом.
  final Widget? leading;

  /// Доступен ли сегмент.
  final bool enabled;

  /// Ключ сегмента (контракт §9).
  final Key? key;

  /// Текст семантики, если отличается от [label].
  final String? semanticLabel;
}

/// Pill-трек `ink2` с «бегунком» `ink4` + rim light, скользящим на пружине
/// `snap` (REDESIGN-SPEC §8). До 4 сегментов; при узкой ширине — горизонтальная
/// прокрутка.
class NcSegmented<T> extends StatelessWidget {
  /// Создаёт сегментированный переключатель.
  const NcSegmented({
    super.key,
    required this.segments,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  /// Сегменты (2–4).
  final List<NcSegment<T>> segments;

  /// Выбранное значение.
  final T value;

  /// Выбор; `null` — неактивен весь контрол.
  final ValueChanged<T>? onChanged;

  /// Текст семантики контрола.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
