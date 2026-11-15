import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/generation_failure_message.dart';

/// У каждой причины сбоя фрагмента есть понятная строка ARB (fix-gen, Д6).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('все GenerationFailureReason маппятся в непустые строки', () async {
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('ru'),
    );
    for (final GenerationFailureReason reason
        in GenerationFailureReason.values) {
      final String message = generationFailureReasonMessage(l10n, reason);
      expect(
        message.trim(),
        isNotEmpty,
        reason: 'нет строки для причины ${reason.code}',
      );
    }
  });

  test('строки причин различаются (не общая заглушка)', () async {
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('ru'),
    );
    final Set<String> messages = <String>{
      for (final GenerationFailureReason reason
          in GenerationFailureReason.values)
        generationFailureReasonMessage(l10n, reason),
    };
    expect(messages.length, greaterThan(8));
  });
}
