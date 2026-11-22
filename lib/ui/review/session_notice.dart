import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Неблокирующее сообщение сессии над панелью оценок (находка D4 аудита).
///
/// Раньше «Оценка отменена» / «Не удалось сохранить оценку» показывались
/// снекбаром поверх нижней панели: тост перекрывал 2 из 4 кнопок оценок, а на
/// узких экранах — и подписи. Теперь сообщение сессии живёт в собственной
/// строке над панелью: не перекрывает действия, закрывается крестиком и само
/// исчезает через несколько секунд.
class SessionNotice extends StatelessWidget {
  /// Создаёт сообщение.
  const SessionNotice({
    required this.message,
    required this.onDismiss,
    required this.dismissTooltip,
    super.key,
  });

  /// Текст сообщения (из ARB).
  final String message;

  /// Закрыть сообщение.
  final VoidCallback onDismiss;

  /// Подпись кнопки закрытия (tooltip/семантика).
  final String dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('session-notice'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + 4,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: AppSizes.icon,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('session-notice-dismiss'),
            tooltip: dismissTooltip,
            iconSize: AppSizes.iconSmall,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Состояние сообщения сессии: показ с автоскрытием и ручным закрытием.
///
/// Миксин для `State` экранов сессий: заменяет снекбар, который перекрывал
/// панель оценок (D4). Вызывать `super.dispose()` в экране обязательно — как и
/// раньше.
mixin SessionNoticeMixin<T extends StatefulWidget> on State<T> {
  String? _sessionNotice;
  Timer? _sessionNoticeTimer;

  /// Текущее сообщение; `null` — строки нет.
  String? get sessionNotice => _sessionNotice;

  /// Показать сообщение над панелью оценок на 4 секунды.
  void showSessionNotice(String message) {
    _sessionNoticeTimer?.cancel();
    setState(() => _sessionNotice = message);
    _sessionNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _sessionNotice = null);
    });
  }

  /// Закрыть сообщение сразу.
  void dismissSessionNotice() {
    _sessionNoticeTimer?.cancel();
    if (_sessionNotice == null) return;
    setState(() => _sessionNotice = null);
  }

  @override
  void dispose() {
    _sessionNoticeTimer?.cancel();
    super.dispose();
  }
}
