import 'package:material_ui/material_ui.dart';

/// Варианты кнопки Nocturne (REDESIGN-SPEC §8).
enum NcButtonVariant {
  /// Градиент `aurumBright→aurumDeep`, текст `textOnAccent`, `glow` при
  /// `prominent: true` (один главный CTA на экран).
  primary,

  /// `ink4` + рамка `hairlineStrong`.
  secondary,

  /// Прозрачная, текст `textPrimary`.
  ghost,

  /// `emberSoft` + текст `ember` (удаление, ошибка).
  destructive,

  /// Градиент `iris→irisDeep` + блик (только «Сгенерировать»).
  ai,
}

/// Размер кнопки: высота 36 / 48 / 56 (§8).
enum NcButtonSize {
  /// 36 — малые действия в ряду.
  s,

  /// 48 — обычная кнопка.
  m,

  /// 56 — главное действие.
  l,
}

/// Кнопка Nocturne (REDESIGN-SPEC §8): 5 вариантов, 3 размера, pill,
/// состояние загрузки, фокус клавиатуры и `press`-сжатие.
class NcButton extends StatelessWidget {
  /// Создаёт кнопку.
  const NcButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = NcButtonVariant.primary,
    this.size = NcButtonSize.m,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.prominent = false,
    this.expand = false,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
  });

  /// Текст кнопки (из ARB).
  final String label;

  /// Действие; `null` — неактивная кнопка.
  final VoidCallback? onPressed;

  /// Вариант оформления.
  final NcButtonVariant variant;

  /// Размер.
  final NcButtonSize size;

  /// Иконка перед текстом.
  final IconData? icon;

  /// Иконка после текста.
  final IconData? trailingIcon;

  /// Состояние загрузки: текст заменяется тремя точками, ширина не меняется.
  final bool loading;

  /// Включить `glow` (только один главный CTA на экран).
  final bool prominent;

  /// Растянуть на всю доступную ширину.
  final bool expand;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Текст семантики, если отличается от [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
