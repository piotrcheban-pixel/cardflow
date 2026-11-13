import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Результат работы формы карточки (для сообщений на экране колоды).
enum CardFormResult {
  /// Карточка создана.
  created,

  /// Изменения сохранены.
  updated,

  /// Карточка удалена.
  deleted,
}

/// Экран создания/редактирования карточки (SPEC A6.3, ADR-009).
///
/// Красная фаза итерации 2: заглушка — поля, валидация, сохранение и удаление
/// появятся в зелёной фазе.
class CardFormScreen extends ConsumerWidget {
  /// Создаёт форму; [cardId] == null — создание новой карточки.
  const CardFormScreen({required this.deckId, this.cardId, super.key});

  /// Колода-владелец.
  final String deckId;

  /// Карточка при редактировании; `null` — создание.
  final String? cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(cardId == null ? l10n.cardFormTitleNew : l10n.cardFormTitleEdit),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
