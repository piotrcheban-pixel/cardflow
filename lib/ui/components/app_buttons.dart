import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Единые вариации кнопок дизайн-системы (аудит v4, V38).
///
/// Базовая высота всех кнопок задана в теме ([AppTheme]: 44 px с адаптивным
/// множителем). Здесь — только осознанные исключения:
///
/// * [large] — главное действие страницы (48 px): «Новая колода»,
///   «Начать сессию», «Сгенерировать»;
/// * [compact] — действие внутри плотной панели/карточки (не ниже 44 px по
///   доступности, визуально — 40 px по контенту).
abstract final class AppButtons {
  /// Множитель контролов: тот же, что в теме (1,0 / 1,24 / 1,45 → до 1,3).
  static double _control(BuildContext context) =>
      AppAdaptive.factorForContext(context).clamp(1.0, 1.3);

  /// Главное действие страницы: высота 48 px (с адаптивом).
  static ButtonStyle large(BuildContext context) => FilledButton.styleFrom(
    minimumSize: Size(0, AppSizes.buttonHeightLarge * _control(context)),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    textStyle: Theme.of(context).textTheme.labelLarge,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
    ),
  );

  /// Действие в плотной панели: высота 44 px, компактные поля.
  static ButtonStyle compact(BuildContext context) => FilledButton.styleFrom(
    minimumSize: Size(0, AppSizes.buttonHeight * _control(context)),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    textStyle: Theme.of(context).textTheme.labelLarge,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
    ),
  );

  /// Главное действие карточки («Показать ответ»): не ниже 56 лог. px (G1).
  ///
  /// Аудит v7: главное действие сессии было 48–59 px и визуально терялось
  /// рядом с четырьмя оценками. Теперь это крупная кнопка на всю ширину
  /// карточки, с кеглем 17 с адаптивным множителем.
  static ButtonStyle cardAction(BuildContext context) {
    final double factor = _control(context);
    return FilledButton.styleFrom(
      minimumSize: Size.fromHeight(AppSizes.revealButtonHeight * factor),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      textStyle: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontSize: 17 * factor, fontWeight: FontWeight.w600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
      ),
    );
  }
}
