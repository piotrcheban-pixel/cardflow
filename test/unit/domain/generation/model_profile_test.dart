import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт этапа Allocation: профиль модели — данные, а не магические числа
/// в логике упаковки (TASK «Срез 4», ADR-050).
void main() {
  group('ModelProfile', () {
    const ModelProfile profile = ModelProfile(
      id: 'test-model',
      provider: 'test',
      contextWindow: 100000,
      maxOutputTokens: 8192,
      supportsJsonSchema: true,
      supportsVision: false,
      concurrency: 3,
    );

    test('бюджет батча — 40 % окна контекста', () {
      expect(ModelProfile.batchWindowShare, 0.4);
      expect(profile.batchTokenBudget, 40000);
      const ModelProfile small = ModelProfile(
        id: 'small',
        provider: 'test',
        contextWindow: 801,
        maxOutputTokens: 100,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 1,
      );
      expect(
        small.batchTokenBudget,
        320,
        reason: 'Округление вниз: 801 × 0,4 = 320,4',
      );
    });

    test('fitsBatch: выход в пределе и вход + выход в бюджете батча', () {
      expect(profile.fitsBatch(inputTokens: 30000, outputTokens: 8000), isTrue);
      expect(
        profile.fitsBatch(inputTokens: 32000, outputTokens: 8000),
        isTrue,
        reason: 'Ровно 40 % окна — ещё влезает',
      );
      expect(
        profile.fitsBatch(inputTokens: 32001, outputTokens: 8000),
        isFalse,
        reason: '40001 > 40000 — батч не влезает в 40 % окна',
      );
      expect(profile.fitsBatch(inputTokens: 0, outputTokens: 8192), isTrue);
      expect(
        profile.fitsBatch(inputTokens: 0, outputTokens: 8193),
        isFalse,
        reason: 'Выход больше maxOutputTokens',
      );
      expect(profile.fitsBatch(inputTokens: -1, outputTokens: 10), isFalse);
      expect(profile.fitsBatch(inputTokens: 10, outputTokens: -1), isFalse);
      expect(profile.fitsBatch(inputTokens: 35000, outputTokens: 5000), isTrue);
    });

    test('maxCardsPerBatch — по пределу вывода', () {
      expect(profile.maxCardsPerBatch(300), 27);
      expect(profile.maxCardsPerBatch(8192), 1);
      expect(profile.maxCardsPerBatch(10000), 0);
      expect(() => profile.maxCardsPerBatch(0), throwsArgumentError);
      expect(() => profile.maxCardsPerBatch(-5), throwsArgumentError);
    });

    test('инварианты конструктора', () {
      expect(
        () => ModelProfile(
          id: '',
          provider: 'test',
          contextWindow: 1000,
          maxOutputTokens: 100,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 1,
        ),
        throwsAssertionError,
      );
      expect(
        () => ModelProfile(
          id: 'x',
          provider: '',
          contextWindow: 1000,
          maxOutputTokens: 100,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 1,
        ),
        throwsAssertionError,
      );
      expect(
        () => ModelProfile(
          id: 'x',
          provider: 'test',
          contextWindow: 0,
          maxOutputTokens: 100,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 1,
        ),
        throwsAssertionError,
      );
      expect(
        () => ModelProfile(
          id: 'x',
          provider: 'test',
          contextWindow: 1000,
          maxOutputTokens: 0,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 1,
        ),
        throwsAssertionError,
      );
      expect(
        () => ModelProfile(
          id: 'x',
          provider: 'test',
          contextWindow: 1000,
          maxOutputTokens: 1001,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 1,
        ),
        throwsAssertionError,
        reason: 'Предел вывода не больше окна контекста',
      );
      expect(
        () => ModelProfile(
          id: 'x',
          provider: 'test',
          contextWindow: 1000,
          maxOutputTokens: 100,
          supportsJsonSchema: false,
          supportsVision: false,
          concurrency: 0,
        ),
        throwsAssertionError,
      );
    });

    test('равенство и строка — по id', () {
      const ModelProfile same = ModelProfile(
        id: 'test-model',
        provider: 'test',
        contextWindow: 100000,
        maxOutputTokens: 8192,
        supportsJsonSchema: true,
        supportsVision: false,
        concurrency: 3,
      );
      const ModelProfile other = ModelProfile(
        id: 'other',
        provider: 'test',
        contextWindow: 100000,
        maxOutputTokens: 8192,
        supportsJsonSchema: true,
        supportsVision: false,
        concurrency: 3,
      );
      expect(profile, same);
      expect(profile.hashCode, same.hashCode);
      expect(profile, isNot(other));
      expect(profile.toString(), contains('test-model'));
    });
  });

  group('Каталог профилей', () {
    test('данные для 3+ провайдеров, id уникальны, значения согласованы', () {
      final Set<String> providers = <String>{
        for (final ModelProfile profile in kModelProfiles) profile.provider,
      };
      expect(
        providers.length,
        greaterThanOrEqualTo(3),
        reason: 'TASK: данные для 3+ провайдеров',
      );
      expect(
        providers,
        containsAll(<String>['deepseek', 'openai', 'anthropic', 'gemini']),
      );
      expect(
        kModelProfiles.map((ModelProfile profile) => profile.id).toSet(),
        hasLength(kModelProfiles.length),
        reason: 'id моделей уникальны',
      );
      for (final ModelProfile profile in kModelProfiles) {
        expect(profile.contextWindow, greaterThan(0));
        expect(profile.maxOutputTokens, greaterThan(0));
        expect(
          profile.maxOutputTokens,
          lessThanOrEqualTo(profile.contextWindow),
        );
        expect(profile.concurrency, greaterThan(0));
        expect(profile.batchTokenBudget, profile.contextWindow * 2 ~/ 5);
      }
    });

    test('профили согласованы с каталогом пресетов провайдеров', () {
      var matched = 0;
      for (final ProviderPreset preset in kProviderPresets) {
        for (final ProviderPresetModel model in preset.models) {
          final ModelProfile? profile = modelProfileById(model.id);
          if (profile == null) continue;
          matched++;
          expect(
            profile.contextWindow,
            model.contextTokens,
            reason: 'Окно ${model.id} должно совпадать с пресетом',
          );
          expect(
            profile.supportsVision,
            model.supportsVision,
            reason: 'Vision ${model.id} должен совпадать с пресетом',
          );
          expect(profile.provider, preset.id);
        }
      }
      expect(
        matched,
        greaterThanOrEqualTo(4),
        reason: 'Профили покрывают модели из каталога пресетов',
      );
    });

    test('поиск по id; неизвестная модель — null', () {
      final ModelProfile? gpt = modelProfileById('gpt-4o');
      expect(gpt, isNotNull);
      expect(gpt!.provider, 'openai');
      expect(gpt.supportsJsonSchema, isTrue);
      expect(gpt.supportsVision, isTrue);
      expect(modelProfileById('нет-такой-модели'), isNull);
    });

    test('неизвестная модель получает консервативный профиль', () {
      final ModelProfile fallback = modelProfileOrDefault('нет-такой-модели');
      expect(fallback.id, kConservativeModelProfile.id);
      expect(fallback.supportsJsonSchema, isFalse);
      expect(fallback.supportsVision, isFalse);
      expect(fallback.concurrency, 1);
      expect(fallback.contextWindow, lessThan(128000));
      expect(modelProfileOrDefault('gpt-4o').id, 'gpt-4o');
    });

    test(
      'DeepSeek: strict JSON-схема не поддерживается (лестница ADR-021)',
      () {
        for (final ModelProfile profile in kModelProfiles) {
          if (profile.provider != 'deepseek') continue;
          expect(
            profile.supportsJsonSchema,
            isFalse,
            reason: 'strict response_format DeepSeek отвечает 400',
          );
        }
      },
    );
  });
}
