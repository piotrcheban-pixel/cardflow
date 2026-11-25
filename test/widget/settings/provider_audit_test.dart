import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/settings/provider_banner.dart';
import 'package:cardflow/ui/settings/provider_labels.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Аудит 1.0: провайдеры (F7) и настройки (D13/D14/D22).
void main() {
  ProviderAccount broken() => testCustomProviderAccount(
    id: 'custom',
    label: 'Пользовательская модель API',
    baseUrl: '',
    modelId: '',
  );

  ProviderAccounts accountsWith(ProviderAccount account, {bool active = true}) {
    final ProviderAccounts accounts = ProviderAccounts.empty.withAccount(
      account,
    );
    return active ? accounts.withActive(account.id) : accounts;
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    ProviderAccounts accounts, {
    Widget? home,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          providerAccountsStore: FakeProviderAccountsStore(accounts),
        ),
        home: home ?? const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('F7: невалидный основной провайдер — баннер в настройках', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester, accountsWith(broken()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(
      find.byKey(const ValueKey<String>('primary-provider-banner')),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsProvidersPrimaryBroken), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('primary-provider-fix')),
      findsOneWidget,
    );
  });

  testWidgets('F7: невалидный аккаунт нельзя сделать основным', (
    WidgetTester tester,
  ) async {
    final ProviderAccount valid = testProviderAccount(id: 'valid');
    final ProviderAccounts accounts = ProviderAccounts.empty
        .withAccount(valid)
        .withAccount(broken())
        .withActive(valid.id);
    await pumpSettings(
      tester,
      accounts,
      home: const GenerationSettingsScreen(),
    );
    final AppLocalizations l10n = l10nOf(tester);

    final Finder activate = find.byKey(
      const ValueKey<String>('provider-activate-custom'),
    );
    expect(activate, findsOneWidget);
    await tester.ensureVisible(activate);
    await tester.pumpAndSettle();
    await tester.tap(activate);
    await tester.pumpAndSettle();

    expect(find.text(l10n.settingsProvidersCannotBePrimary), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('provider-active-custom')),
      findsNothing,
      reason: 'невалидный аккаунт не стал основным',
    );
  });

  testWidgets('D14: подзаголовок карточки не повторяет название', (
    WidgetTester tester,
  ) async {
    await pumpSettings(
      tester,
      accountsWith(broken(), active: false),
      home: const GenerationSettingsScreen(),
    );
    final AppLocalizations l10n = l10nOf(tester);
    final String title = providerAccountLabel(l10n, broken());
    final String summary = providerSummary(l10n, broken());

    expect(summary, isNot(title));
    expect(find.text(title), findsOneWidget);
    expect(find.text(summary), findsOneWidget);
  });

  testWidgets('D13: диалог провайдера прокручивается и не обрезается', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSettings(
      tester,
      accountsWith(broken(), active: false),
      home: const GenerationSettingsScreen(),
    );

    final Finder edit = find.byKey(
      const ValueKey<String>('provider-edit-custom'),
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();

    // V8: форма провайдера — AppDialog с прокручиваемым телом; сырого
    // AlertDialog больше нет.
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('provider-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D22: активный раздел настроек подсвечен', (
    WidgetTester tester,
  ) async {
    // Узкое окно: поднавигация настроек — чипы (D22).
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSettings(tester, ProviderAccounts.empty);
    final AppLocalizations l10n = l10nOf(tester);

    final Finder chip = find.byKey(
      ValueKey<String>('settings-nav-${l10n.settingsNavAppearance}'),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    final ChoiceChip selected = tester.widget<ChoiceChip>(chip);
    expect(selected.selected, isTrue);
  });

  // Итерация «Фикс мобильного Empty State»: баннер основного провайдера —
  // тот же дефект, что и блок ИИ в пустом состоянии (Row с Expanded-текстом и
  // TextButton): на 390 px тексту оставалось 146 px, при кегле 150 % — 78,6 px.
  group('Баннер провайдера на мобильной ширине', () {
    Future<void> pumpBannerAt(
      WidgetTester tester,
      Size size, {
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        appWithHome(
          overrides: decksOverrides(deckRepository: FakeDeckRepository()),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: PrimaryProviderBanner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect bannerText(WidgetTester tester) => tester.getRect(
      find.text(l10nOf(tester).settingsProvidersPrimaryBroken),
    );

    Rect bannerAction(WidgetTester tester) => tester.getRect(
      find.byKey(const ValueKey<String>('primary-provider-fix')),
    );

    testWidgets('390×844: действие под текстом, текст на ширину баннера', (
      WidgetTester tester,
    ) async {
      await pumpBannerAt(tester, const Size(390, 844));
      final Rect text = bannerText(tester);
      final Rect action = bannerAction(tester);

      expect(
        text.width,
        greaterThanOrEqualTo(220),
        reason: 'текст не сжимается в узкую колонку: ${text.width}',
      );
      expect(
        action.top,
        greaterThanOrEqualTo(text.bottom),
        reason: 'на телефоне «Исправить» — под текстом, а не сбоку',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('390×844 при 150 %: без overflow, текст читается', (
      WidgetTester tester,
    ) async {
      await pumpBannerAt(tester, const Size(390, 844), textScale: 1.5);
      expect(tester.takeException(), isNull);
      expect(
        bannerText(tester).width,
        greaterThanOrEqualTo(160),
        reason: 'при 150 % кегле текст не сжат: ${bannerText(tester).width}',
      );
      expect(
        bannerAction(tester).top,
        greaterThanOrEqualTo(bannerText(tester).bottom),
      );
    });

    testWidgets('1440×900: баннер остаётся горизонтальным', (
      WidgetTester tester,
    ) async {
      await pumpBannerAt(tester, const Size(1440, 900));
      final Rect text = bannerText(tester);
      final Rect action = bannerAction(tester);
      expect(
        action.left,
        greaterThanOrEqualTo(text.right - 1),
        reason: 'на десктопе кнопка справа от текста',
      );
      expect(action.top, lessThan(text.bottom));
    });
  });
}
