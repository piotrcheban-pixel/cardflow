// Профиль совместимости схемы (TASK «Срез 13», часть 2): проба strict-схемы
// один раз на прогон, ключ — провайдер + модель + схема.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/schema_compat_profile.dart';

void main() {
  test('отказ strict-схемы запоминается по провайдеру, модели и схеме', () {
    final SchemaCompatProfile profile = SchemaCompatProfile();

    expect(
      profile.isRejected(
        provider: 'openaiCompletions',
        model: 'deepseek-flash',
        schema: 'gen-map-v1',
        rung: SchemaCompatRung.strictSchema,
      ),
      isFalse,
    );

    profile.rememberRejected(
      provider: 'openaiCompletions',
      model: 'deepseek-flash',
      schema: 'gen-map-v1',
      rung: SchemaCompatRung.strictSchema,
    );

    expect(
      profile.isRejected(
        provider: 'openaiCompletions',
        model: 'deepseek-flash',
        schema: 'gen-map-v1',
        rung: SchemaCompatRung.strictSchema,
      ),
      isTrue,
    );
    expect(
      profile.isRejected(
        provider: 'openaiCompletions',
        model: 'deepseek-flash',
        schema: 'gen-cards-v3',
        rung: SchemaCompatRung.strictSchema,
      ),
      isFalse,
      reason: 'новая схема — новый договор: отказ старой не «заражает» её',
    );
    expect(
      profile.isRejected(
        provider: 'openaiCompletions',
        model: 'deepseek-chat',
        schema: 'gen-map-v1',
        rung: SchemaCompatRung.strictSchema,
      ),
      isFalse,
      reason: 'другая модель — другой факт',
    );
    expect(profile.factCount, 1);
  });
}
