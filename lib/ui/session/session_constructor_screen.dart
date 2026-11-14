import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Экран «Конструктор сессии» (SPEC A6.7).
///
/// КРАСНАЯ ФАЗА итерации 6: каркас экрана объявлен, блоки фильтров, лимита,
/// порядка и пресетов ещё не реализованы — тесты падают по ожиданиям.
class SessionConstructorScreen extends ConsumerStatefulWidget {
  /// Создаёт экран конструктора.
  const SessionConstructorScreen({this.preselectedDeckId, super.key});

  /// Колода, предвыбранная при открытии с экрана колоды (SPEC A6.3).
  final String? preselectedDeckId;

  @override
  ConsumerState<SessionConstructorScreen> createState() =>
      _SessionConstructorScreenState();
}

class _SessionConstructorScreenState
    extends ConsumerState<SessionConstructorScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).constructorTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
