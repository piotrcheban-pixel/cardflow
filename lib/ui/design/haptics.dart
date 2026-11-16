import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Виды тактильного отклика (REDESIGN-SPEC §7).
///
/// Таблица оценок FSRS → вид отклика живёт в экранах (этап 4): дизайн-система
/// не импортирует `domain/` (ADR-035), поэтому `Rating` проецируется в
/// [NcHapticKind] на стороне экрана.
enum NcHapticKind {
  /// Лёгкий «клик» выбора (переворот, переключатель, слайдер, «Легко»).
  selectionClick,

  /// Лёгкий удар («Сложно», «Знаю», порог свайпа, «верно»).
  lightImpact,

  /// Средний удар (завершение сессии, контекстное меню, удаление).
  mediumImpact,

  /// Сильный удар («Не знаю», ошибка, неверный ответ).
  heavyImpact,
}

/// Единая точка тактильного отклика (REDESIGN-SPEC §7, ADR-035).
///
/// Прямые `HapticFeedback.*` вне этого файла запрещены guard-тестом. Отклик
/// уважает настройку `haptics`, ограничен частотой (не чаще одного раза в
/// [minInterval]) и гасит повтор одного и того же события в окне [repeatWindow]
/// (слайдер, долгие нажатия).
class NcHaptics {
  /// Создаёт точку отклика.
  ///
  /// [clock] — источник времени для тестов; [enabled] обновляется из настроек
  /// при перестройке приложения (`app.dart`).
  NcHaptics({this.enabled = true, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Минимальный интервал между откликами.
  static const Duration minInterval = Duration(milliseconds: 40);

  /// Окно, в котором повтор того же события гасится.
  static const Duration repeatWindow = Duration(milliseconds: 200);

  /// Задержка второго отклика «успеха» (§7: mediumImpact → 110 мс → light).
  static const Duration successDelay = Duration(milliseconds: 110);

  /// Включён ли отклик (настройка «Тактильный отклик», A6.6).
  bool enabled;

  final DateTime Function() _clock;
  DateTime? _lastFiredAt;
  NcHapticKind? _lastKind;
  Timer? _successTimer;

  /// Отклик «переворот карточки / раскрытие маски» — `selectionClick`.
  void flip() => selectionClick();

  /// `selectionClick` — выбор, переключатель, чип, «Легко».
  void selectionClick() => _fire(NcHapticKind.selectionClick);

  /// `lightImpact` — «Сложно», «Знаю», порог свайпа.
  void lightImpact() => _fire(NcHapticKind.lightImpact);

  /// `mediumImpact` — завершение, меню, подтверждение удаления.
  void mediumImpact() => _fire(NcHapticKind.mediumImpact);

  /// `heavyImpact` — «Не знаю», ошибка, неверный ответ.
  void heavyImpact() => _fire(NcHapticKind.heavyImpact);

  /// Оценка: вид отклика передаёт экран (таблица §7).
  void rating(NcHapticKind kind) => _fire(kind);

  /// Порог подтверждения свайпа — `lightImpact`.
  void threshold() => lightImpact();

  /// Открытие контекстного меню — `mediumImpact`.
  void menu() => mediumImpact();

  /// Ошибка пользовательского действия — `heavyImpact`.
  void error() => heavyImpact();

  /// Завершение сессии — двойной «успех»: `mediumImpact` → 110 мс →
  /// `lightImpact`.
  void success() {
    _fire(NcHapticKind.mediumImpact);
    _successTimer?.cancel();
    _successTimer = Timer(successDelay, lightImpact);
  }

  /// Отменяет отложенный отклик (при закрытии экрана/приложения).
  void dispose() {
    _successTimer?.cancel();
    _successTimer = null;
  }

  void _fire(NcHapticKind kind) {
    if (!enabled) return;
    final DateTime now = _clock();
    final DateTime? last = _lastFiredAt;
    if (last != null && now.difference(last) < minInterval) return;
    if (_lastKind == kind &&
        last != null &&
        now.difference(last) < repeatWindow) {
      return;
    }
    _lastFiredAt = now;
    _lastKind = kind;
    switch (kind) {
      case NcHapticKind.selectionClick:
        HapticFeedback.selectionClick();
      case NcHapticKind.lightImpact:
        HapticFeedback.lightImpact();
      case NcHapticKind.mediumImpact:
        HapticFeedback.mediumImpact();
      case NcHapticKind.heavyImpact:
        HapticFeedback.heavyImpact();
    }
  }

  /// Единая точка для виджетов: scope, иначе выключенный экземпляр.
  static NcHaptics of(BuildContext context) =>
      NcHapticsScope.maybeOf(context) ?? disabled;

  /// Экземпляр без отклика (виджет без `NcHapticsScope` в тестах/превью).
  static final NcHaptics disabled = NcHaptics(enabled: false);

  /// Длительность второго отклика «успеха» (для тестов и документации).
  static Duration get successSecondDelay => const Duration(milliseconds: 110);
}

/// Передаёт [NcHaptics] вниз по дереву (ставится в `builder` приложения).
class NcHapticsScope extends InheritedWidget {
  const NcHapticsScope({
    super.key,
    required this.haptics,
    required super.child,
  });

  /// Точка отклика текущего приложения.
  final NcHaptics haptics;

  /// Ближайший scope или `null`.
  static NcHaptics? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NcHapticsScope>()?.haptics;

  @override
  bool updateShouldNotify(NcHapticsScope oldWidget) =>
      haptics != oldWidget.haptics;
}
