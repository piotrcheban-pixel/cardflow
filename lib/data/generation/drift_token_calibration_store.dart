/// Хранилище калибровки `tokensPerCard` в `app_settings` (ADR-040 §9).
///
/// Одно JSON-значение `generation.calibration` версии 1; схема БД и
/// `schemaVersion` не меняются. Хранятся только id аккаунта/модели, среднее,
/// число замеров и дата — без текстов, карточек и ключей.
library;

import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';

/// Версия JSON-контракта калибровки.
const int kTokenCalibrationVersion = 1;

/// Реализация [TokenCalibrationStore] поверх `app_settings`.
class DriftTokenCalibrationStore implements TokenCalibrationStore {
  /// Создаёт хранилище поверх [db].
  DriftTokenCalibrationStore(this.db, {DateTime Function()? now})
    : now = now ?? (() => DateTime.now().toUtc());

  /// БД приложения.
  final AppDatabase db;

  /// Текущее время (инжектируется тестами).
  final DateTime Function() now;

  /// Ключ строки в `app_settings`.
  static const String settingKey = 'generation.calibration';

  @override
  Future<List<TokenCalibration>> readAll() async {
    final AppSettingRow? row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals(settingKey))).getSingleOrNull();
    if (row == null) return const <TokenCalibration>[];
    try {
      final Object? json = jsonDecode(row.valueJson);
      final Object? records = json is Map ? json['records'] : null;
      if (records is! List) return const <TokenCalibration>[];
      return <TokenCalibration>[
        for (final Object? item in records)
          if (TokenCalibration.fromJson(item)
              case final TokenCalibration calibration)
            calibration,
      ];
    } on FormatException {
      return const <TokenCalibration>[];
    }
  }

  @override
  Future<TokenCalibration?> read({
    required String accountId,
    required String model,
  }) async {
    final String key = '${accountId.trim().toLowerCase()}|'
        '${model.trim().toLowerCase()}';
    for (final TokenCalibration calibration in await readAll()) {
      if (calibration.key == key) return calibration;
    }
    return null;
  }

  @override
  Future<TokenCalibration> record({
    required String accountId,
    required String model,
    required double observedTokensPerCard,
    DateTime? at,
  }) async {
    final TokenCalibration? previous = await read(
      accountId: accountId,
      model: model,
    );
    final double next = nextTokensPerCard(
      previous: previous?.tokensPerCard,
      observed: observedTokensPerCard,
    );
    final TokenCalibration calibration = TokenCalibration(
      accountId: accountId,
      model: model,
      tokensPerCard: next,
      samples: (previous?.samples ?? 0) + 1,
      updatedAt: (at ?? now()).toUtc(),
    );
    final List<TokenCalibration> records = <TokenCalibration>[
      for (final TokenCalibration existing in await readAll())
        if (existing.key != calibration.key) existing,
      calibration,
    ];
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            valueJson: jsonEncode(<String, Object?>{
              'version': kTokenCalibrationVersion,
              'records': <Object?>[
                for (final TokenCalibration record in records) record.toJson(),
              ],
            }),
          ),
        );
    return calibration;
  }
}
