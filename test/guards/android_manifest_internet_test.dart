import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Guard: release-сборка Android обязана иметь разрешение INTERNET.
///
/// `flutter build apk --release` собирает манифест только из
/// `android/app/src/main/AndroidManifest.xml`: `debug`/`profile`-манифесты в
/// release не попадают. В итерации «Диагностика и фикс пайплайна генерации»
/// обнаружено, что в APK 1.0.1 не было `android.permission.INTERNET` (проверено
/// `aapt2 dump permissions`), поэтому генерация ИИ на Android в release падала
/// на первом запросе к провайдеру. Тест фиксирует разрешение в main-манифесте и
/// не даёт молча удалить его снова.
void main() {
  test('main AndroidManifest содержит android.permission.INTERNET', () {
    final File manifest = File(
      '${projectRoot().path}${Platform.pathSeparator}android'
      '${Platform.pathSeparator}app${Platform.pathSeparator}src'
      '${Platform.pathSeparator}main${Platform.pathSeparator}'
      'AndroidManifest.xml',
    );
    expect(manifest.existsSync(), isTrue, reason: 'манифест Android не найден');

    final String source = manifest.readAsStringSync();
    expect(
      source,
      contains('android.permission.INTERNET'),
      reason:
          'release APK собирается из main-манифеста: без INTERNET все запросы '
          'к провайдеру генерации завершаются ошибкой сети',
    );

    // Разрешение должно быть объявлено как uses-permission, а не комментарий.
    final RegExp declared = RegExp(
      r'<uses-permission[^>]*android:name="android\.permission\.INTERNET"',
    );
    expect(declared.hasMatch(source), isTrue);
  });
}
