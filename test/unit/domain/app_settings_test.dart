import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/settings/app_settings.dart';

void main() {
  group('AppSettings — значения по умолчанию', () {
    test('совпадают с ADR-019 §1', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.theme, AppThemePreference.system);
      expect(settings.dynamicColor, isFalse);
      expect(settings.motion, MotionPreference.expressive);
      expect(settings.dyslexiaFont, isFalse);
      expect(settings.textScale, 1.0);
      expect(settings.highContrast, isFalse);
      expect(settings.haptics, isTrue);
      expect(settings.desiredRetention, 0.9);
      expect(settings.learningSteps, <Duration>[
        Duration(minutes: 1),
        Duration(minutes: 10),
      ]);
      expect(settings.dailyNewLimit, 20);
      expect(settings.dailyReviewLimit, 200);
      expect(settings.defaultProvider, GenerationProvider.openai);
      expect(settings.defaultModelId, 'gpt-4o-mini');
    });
  });

  group('AppSettings — JSON', () {
    const AppSettings custom = AppSettings(
      theme: AppThemePreference.dark,
      dynamicColor: true,
      motion: MotionPreference.standard,
      dyslexiaFont: true,
      textScale: 1.2,
      highContrast: true,
      haptics: false,
      desiredRetention: 0.85,
      learningSteps: <Duration>[Duration(minutes: 5)],
      dailyNewLimit: 35,
      dailyReviewLimit: 400,
      defaultProvider: GenerationProvider.anthropic,
      defaultModelId: 'claude-3-5-haiku-latest',
    );

    test('roundtrip сохраняет все поля и версию', () {
      final Map<String, Object?> json = custom.toJson();
      expect(json['version'], AppSettings.version);
      expect(AppSettings.fromJson(json), custom);
    });

    test('неизвестные ключи игнорируются, отсутствующие — по умолчанию', () {
      final AppSettings parsed = AppSettings.fromJson(<String, Object?>{
        'version': 1,
        'theme': 'light',
        'future_field': <String, Object?>{'x': 1},
      });
      expect(parsed.theme, AppThemePreference.light);
      expect(parsed.textScale, AppSettings.defaults.textScale);
      expect(parsed.learningSteps, AppSettings.defaults.learningSteps);
    });

    test('числовые поля клампятся в допустимые диапазоны', () {
      final AppSettings parsed = AppSettings.fromJson(<String, Object?>{
        'version': 1,
        'text_scale': 3.0,
        'desired_retention': 0.1,
        'daily_new_limit': -4,
        'daily_review_limit': 10000,
        'learning_steps_minutes': <int>[0, 90, 90],
      });
      expect(parsed.textScale, AppSettings.maxTextScale);
      expect(parsed.desiredRetention, AppSettings.minRetention);
      expect(parsed.dailyNewLimit, 0);
      expect(parsed.dailyReviewLimit, AppSettings.maxDailyLimit);
      expect(parsed.learningSteps, <Duration>[
        Duration(minutes: 1),
        Duration(minutes: 60),
      ]);
    });

    test('шаги обучения: не больше пяти, непустой список', () {
      final AppSettings many = AppSettings.fromJson(<String, Object?>{
        'version': 1,
        'learning_steps_minutes': <int>[1, 2, 3, 4, 5, 6],
      });
      expect(many.learningSteps.length, AppSettings.maxLearningSteps);

      final AppSettings empty = AppSettings.fromJson(<String, Object?>{
        'version': 1,
        'learning_steps_minutes': <int>[],
      });
      expect(empty.learningSteps, AppSettings.defaultLearningSteps);
    });

    test('неизвестная версия — FormatException', () {
      expect(
        () => AppSettings.fromJson(<String, Object?>{'version': 2}),
        throwsFormatException,
      );
      expect(
        () => AppSettings.fromJson(<String, Object?>{}),
        throwsFormatException,
      );
    });

    test('неверные типы и значения enum — FormatException', () {
      expect(
        () => AppSettings.fromJson(<String, Object?>{
          'version': 1,
          'text_scale': 'large',
        }),
        throwsFormatException,
      );
      expect(
        () => AppSettings.fromJson(<String, Object?>{
          'version': 1,
          'theme': 'neon',
        }),
        throwsFormatException,
      );
      expect(
        () => AppSettings.fromJson(<String, Object?>{
          'version': 1,
          'haptics': 'yes',
        }),
        throwsFormatException,
      );
      expect(
        () => AppSettings.fromJson(<String, Object?>{
          'version': 1,
          'default_provider': 'unknown',
        }),
        throwsFormatException,
      );
    });
  });

  group('AppSettings — copyWith', () {
    test('меняет только указанные поля', () {
      final AppSettings changed = AppSettings.defaults.copyWith(
        theme: AppThemePreference.light,
        textScale: 1.3,
        learningSteps: <Duration>[Duration(minutes: 5)],
      );
      expect(changed.theme, AppThemePreference.light);
      expect(changed.textScale, 1.3);
      expect(changed.learningSteps, <Duration>[Duration(minutes: 5)]);
      expect(changed.desiredRetention, AppSettings.defaults.desiredRetention);
      expect(changed.dailyNewLimit, AppSettings.defaults.dailyNewLimit);
    });

    test('copyWith нормализует шаги обучения (порядок и дубликаты)', () {
      final AppSettings a = AppSettings.defaults.copyWith(
        learningSteps: <Duration>[
          Duration(minutes: 10),
          Duration(minutes: 1),
          Duration(minutes: 10),
        ],
      );
      expect(a.learningSteps, <Duration>[
        Duration(minutes: 1),
        Duration(minutes: 10),
      ]);
      expect(a, AppSettings.defaults);

      final AppSettings b = AppSettings.defaults.copyWith(
        learningSteps: <Duration>[Duration(minutes: 5)],
      );
      expect(a == b, isFalse);
    });
  });
}
