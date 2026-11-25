import 'package:cardflow/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Итерация «Фикс мобильного Empty State» (owner-note: APK на телефоне).
///
/// Дефект: блок «ИИ не настроен — …» был собран `Row`, где `TextButton`
/// забирал свою неделимую ширину, а `Expanded` получал остаток. На 390×844
/// от текста оставалось 36,8 px (42 строки, ~2 символа в строке), на 360×800 —
/// 6,8 px (77 строк, по одной букве). Ниже — контракт: на мобильной ширине
/// кнопка «Настроить ИИ» стоит ПОД текстом, текст занимает доступную ширину,
/// переполнения нет, а на десктопе блок остаётся горизонтальным.
void main() {
  Future<void> pumpDecksAt(
    WidgetTester tester,
    Size logicalSize, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(deckRepository: FakeDeckRepository()),
        routes: decksRoutes(),
      ),
    );
    await tester.pumpAndSettle();
  }

  _Rects aiBlockRects(WidgetTester tester) {
    final AppLocalizations l10n = l10nOf(tester);
    final Finder note = find.text(l10n.decksWelcomeAiNote);
    final Finder action = find.byKey(
      const ValueKey<String>('decks-welcome-ai-setup'),
    );
    expect(
      note,
      findsOneWidget,
      reason: 'заметка про ИИ должна быть на экране',
    );
    expect(action, findsOneWidget, reason: 'кнопка «Настроить ИИ» должна быть');
    return _Rects(note: tester.getRect(note), action: tester.getRect(action));
  }

  group('ИИ-блок пустого состояния: мобильная ширина', () {
    testWidgets('390×844 (390 px): кнопка «Настроить ИИ» ПОД текстом', (
      WidgetTester tester,
    ) async {
      await pumpDecksAt(tester, const Size(390, 844));
      final _Rects rects = aiBlockRects(tester);

      // Дефект: кнопка стояла справа (action.left ≈ text.right), текст был
      // сжат до 36,8 px. Контракт: кнопка начинается ниже низа текста.
      expect(
        rects.action.top,
        greaterThanOrEqualTo(rects.note.bottom),
        reason:
            'на 390 px кнопка должна быть под текстом, а не сбоку: '
            'note=$rects.note',
      );
      // Кнопка не «уезжает» от левого края блока.
      expect(
        rects.action.left,
        lessThanOrEqualTo(rects.note.left),
        reason: 'на мобильном кнопка выровнена по левому краю блока',
      );
    });

    testWidgets('390×844: текст заметки занимает доступную ширину', (
      WidgetTester tester,
    ) async {
      await pumpDecksAt(tester, const Size(390, 844));
      final _Rects rects = aiBlockRects(tester);

      // Дефект: ширина 36,8 px → перенос по 1–2 буквы. Порог 240 px при
      // bodySmall гарантирует ≥20 символов в строке даже с тестовым шрифтом.
      expect(
        rects.note.width,
        greaterThanOrEqualTo(240),
        reason:
            'текст не должен сжиматься в узкую колонку: '
            'width=${rects.note.width}',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('360×800: нет переполнения, текст не сжат', (
      WidgetTester tester,
    ) async {
      await pumpDecksAt(tester, const Size(360, 800));
      final _Rects rects = aiBlockRects(tester);

      // Дефект: ширина 6,8 px — по одной букве в строке; на 150 % кегле
      // теста вдобавок RenderFlex overflowed by 53 px.
      expect(
        rects.note.width,
        greaterThanOrEqualTo(220),
        reason:
            'на 360 px текст должен занимать ширину блока: '
            'width=${rects.note.width}',
      );
      expect(
        rects.action.top,
        greaterThanOrEqualTo(rects.note.bottom),
        reason: 'на 360 px кнопка должна быть под текстом',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'на 360×800 не должно быть переполнения',
      );
    });
  });

  group('ИИ-блок пустого состояния: десктоп', () {
    testWidgets('1440×900: блок остаётся горизонтальным (Row)', (
      WidgetTester tester,
    ) async {
      await pumpDecksAt(tester, const Size(1440, 900));
      final _Rects rects = aiBlockRects(tester);

      expect(
        rects.action.left,
        greaterThanOrEqualTo(rects.note.right - 1),
        reason:
            'на десктопе кнопка справа от текста, блок не рушится в колонку: '
            'note=$rects.note action=${rects.action}',
      );
      expect(
        rects.action.top,
        lessThan(rects.note.bottom),
        reason: 'на десктопе кнопка на одной строке с текстом',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ИИ-блок пустого состояния: крупный кегль (доступность)', () {
    testWidgets(
      '390×844 при 150 %: без RenderFlex overflow, кнопка под текстом',
      (WidgetTester tester) async {
        // Системный кегль 150 % — обычная настройка на Android. До фикса здесь
        // было «A RenderFlex overflowed by 53 pixels on the right» и текст
        // шириной 0 px.
        await pumpDecksAt(tester, const Size(390, 844), textScale: 1.5);
        final _Rects rects = aiBlockRects(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'при 150 % кегле мобильный экран не переполняется',
        );
        expect(
          rects.action.top,
          greaterThanOrEqualTo(rects.note.bottom),
          reason: 'при 150 % кегле кнопка остаётся под текстом',
        );
        expect(
          rects.note.width,
          greaterThanOrEqualTo(200),
          reason: 'тексту остаётся полноценная ширина: ${rects.note.width}',
        );
      },
    );
  });

  group('Мобильный главный экран: заголовок, иконка, кнопки, отступы', () {
    for (final Size size in const <Size>[Size(360, 800), Size(390, 844)]) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}: без переполнения, '
        'приветствие, иконка и три действия целиком в экране',
        (WidgetTester tester) async {
          await pumpDecksAt(tester, size);
          final AppLocalizations l10n = l10nOf(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: 'мобильный первый экран без RenderFlex overflow',
          );

          // Заголовок приветствия — из ARB, целиком в пределах экрана.
          final Rect title = tester.getRect(find.text(l10n.decksWelcomeTitle));
          expect(title.width, lessThanOrEqualTo(size.width));
          expect(title.left, greaterThanOrEqualTo(0));
          // Приветствие не должно «уезжать» в узкую колонку.
          expect(
            title.width,
            greaterThanOrEqualTo(220),
            reason: 'заголовок занимает ширину блока: width=${title.width}',
          );

          // Иконка состояния видна и в габаритах экрана.
          final Finder icon = find.byIcon(Icons.style_outlined);
          expect(icon, findsOneWidget);
          final Rect iconRect = tester.getRect(icon);
          expect(iconRect.left, greaterThanOrEqualTo(0));
          expect(iconRect.right, lessThanOrEqualTo(size.width));

          // Три пути к первой колоде — внутри экрана, без горизонтального
          // переполнения и без «сжатых» кнопок.
          for (final String key in const <String>[
            'decks-empty-create',
            'decks-empty-generate',
            'decks-empty-import',
          ]) {
            final Finder button = find.byKey(ValueKey<String>(key));
            expect(button, findsOneWidget, reason: 'действие $key на экране');
            final Rect rect = tester.getRect(button);
            expect(
              rect.left,
              greaterThanOrEqualTo(0),
              reason: '$key не выходит за левый край',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(size.width),
              reason: '$key не выходит за правый край: $rect',
            );
            expect(
              rect.height,
              greaterThanOrEqualTo(40),
              reason: '$key остаётся целью касания: ${rect.height}',
            );
          }
        },
      );
    }

    testWidgets('390×844: горизонтальные отступы пустого состояния — '
        'не более 20 px на сторону', (WidgetTester tester) async {
      await pumpDecksAt(tester, const Size(390, 844));
      final AppLocalizations l10n = l10nOf(tester);

      // Внутренняя панель пустого состояния — ближайший `DecoratedBox` вокруг
      // заметки про ИИ. Его левый край = отступ страницы (16) + отступ панели.
      // Дефект: hero-вариант держал 40 px с каждой стороны (80 из 390 —
      // пятая часть экрана на пустоту).
      final Rect contentBlock = tester.getRect(
        find
            .ancestor(
              of: find.text(l10n.decksWelcomeAiNote),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        contentBlock.left,
        lessThanOrEqualTo(16 + 20 + 1),
        reason:
            'отступ панели на мобильном ≤ 20 px, левый край контента = '
            '${contentBlock.left}',
      );
      // И сам контент шире 80 % экрана — панель не «съедает» полезное место.
      expect(
        contentBlock.width,
        greaterThanOrEqualTo(390 * 0.78),
        reason: 'ширина контента панели = ${contentBlock.width}',
      );
    });
  });
}

/// Прямоугольники блока (для диагностики в reason).
final class _Rects {
  const _Rects({required this.note, required this.action});

  final Rect note;
  final Rect action;

  @override
  String toString() => 'note=$note action=$action';
}
