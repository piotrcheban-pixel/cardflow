import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/review/feed_card_view.dart';

import '../../helpers/pump_app.dart';

/// Итерация 7.9: обратная сторона карточки «Ленты» не должна быть отзеркалена.
///
/// `Matrix4.rotationY(pi)` разворачивает обратную сторону так, что её текст
/// читается слева направо (m00 > 0). До фикса матрица давала m00 < 0 —
/// зеркальный текст.
void main() {
  Widget host({required bool revealed, required VoidCallback onTap}) {
    return appWithHome(
      overrides: const <Override>[],
      home: Scaffold(
        body: FeedCardView(
          front: 'Вопрос карточки',
          back: 'Ответ карточки',
          revealed: revealed,
          rated: false,
          rating: null,
          enabled: true,
          resetToken: 0,
          onTap: onTap,
          onRate: (_) {},
        ),
      ),
    );
  }

  Matrix4 flipMatrix(WidgetTester tester) {
    final Transform transform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('feed-card-flip-transform')),
    );
    return transform.transform;
  }

  testWidgets('обратная сторона при revealed=true не зеркалится', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(revealed: true, onTap: () {}));
    await tester.pump();

    expect(find.text('Ответ карточки'), findsOneWidget);
    expect(
      flipMatrix(tester).entry(0, 0),
      greaterThan(0),
      reason:
          'Обратная сторона отзеркалена: m00 <= 0. Нужен дополнительный '
          'Matrix4.rotationY(pi) для обратной стороны.',
    );
  });

  testWidgets('после анимации переворота текст не отзеркален', (
    WidgetTester tester,
  ) async {
    bool revealed = false;
    late StateSetter setState;
    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setter) {
              setState = setter;
              return FeedCardView(
                front: 'Вопрос карточки',
                back: 'Ответ карточки',
                revealed: revealed,
                rated: false,
                rating: null,
                enabled: true,
                resetToken: 0,
                onTap: () {},
                onRate: (_) {},
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Вопрос карточки'), findsOneWidget);

    setState(() => revealed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Ответ карточки'), findsOneWidget);
    expect(
      flipMatrix(tester).entry(0, 0),
      greaterThan(0),
      reason: 'После переворота обратная сторона должна читаться слева направо',
    );
  });
}
