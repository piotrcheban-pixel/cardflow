import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Возможности платформы, от которых зависит UI (аудит 2.0, P3-05/P3-08).
///
/// Клавиатурные подсказки и настройка виброотдачи бессмысленны на телефоне:
/// раньше «Пробел — показать ответ» и «колесо мыши или стрелки» печатались и на
/// touch-устройстве, а переключатель «Тактильная отдача» показывался в
/// Windows-сборке.
///
/// Отдельный слой, чтобы виджеты не зависели от `dart:io` напрямую (guard-тест
/// архитектуры запрещает платформенные библиотеки в `lib/ui`, кроме токенов).
abstract final class PlatformInfo {
  /// Есть ли на устройстве физическая клавиатура (десктоп/веб).
  static bool get hasPhysicalKeyboard => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
    _ => true,
  };

  /// Поддерживает ли платформа виброотдачу.
  static bool get supportsHaptics => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}
