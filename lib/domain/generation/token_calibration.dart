/// Калибровка `tokensPerCard` по фактическому `usage` (ADR-040 §9).
///
/// Первые два замера закладывают основу, далее — экспоненциальное среднее.
/// Значение применяется только после ≥2 замеров: один замер может быть
/// случайным. Кэш — `generation.calibration` v1 в `app_settings` (схема БД не
/// меняется). Домен не зависит от Flutter.
library;

/// Сколько замеров нужно, чтобы применять калибровку.
const int kMinCalibrationSamples = 2;

/// Доля нового замера в экспоненциальном среднем.
const double kCalibrationEmaWeight = 0.3;

/// Разумные границы средней карточки (защита от мусорных `usage`).
const double kMinCalibrationTokensPerCard = 50;
const double kMaxCalibrationTokensPerCard = 5000;

/// Следующее значение `tokensPerCard`.
///
/// `previous == null` — первый замер (значение запоминается, но не применяется
/// до ≥2 замеров); иначе EMA с весом [kCalibrationEmaWeight].
double nextTokensPerCard({double? previous, required double observed}) {
  final double safe = observed
      .clamp(kMinCalibrationTokensPerCard, kMaxCalibrationTokensPerCard)
      .toDouble();
  if (previous == null) return safe;
  final double next =
      previous * (1 - kCalibrationEmaWeight) + safe * kCalibrationEmaWeight;
  return next
      .clamp(kMinCalibrationTokensPerCard, kMaxCalibrationTokensPerCard)
      .toDouble();
}

/// Запись калибровки для аккаунта/модели.
final class TokenCalibration {
  /// Создаёт запись.
  const TokenCalibration({
    required this.accountId,
    required this.model,
    required this.tokensPerCard,
    required this.samples,
    required this.updatedAt,
  }) : assert(samples > 0),
       assert(tokensPerCard > 0);

  /// id аккаунта.
  final String accountId;

  /// id модели.
  final String model;

  /// Среднее число токенов на карточку.
  final double tokensPerCard;

  /// Сколько замеров учтено.
  final int samples;

  /// Когда обновлено.
  final DateTime updatedAt;

  /// true, если значение можно применять в планировании.
  bool get isApplicable => samples >= kMinCalibrationSamples;

  /// Ключ записи.
  String get key =>
      '${accountId.trim().toLowerCase()}|${model.trim().toLowerCase()}';

  /// JSON-представление.
  Map<String, Object?> toJson() => <String, Object?>{
    'account_id': accountId,
    'model': model,
    'tokens_per_card': tokensPerCard,
    'samples': samples,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Разбор записи; `null` — повреждена.
  static TokenCalibration? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? accountId = json['account_id'];
    final Object? model = json['model'];
    final Object? value = json['tokens_per_card'];
    final Object? samples = json['samples'];
    final DateTime? at = DateTime.tryParse(
      json['updated_at'] is String ? json['updated_at']! as String : '',
    );
    if (accountId is! String ||
        model is! String ||
        value is! num ||
        value <= 0 ||
        samples is! num ||
        samples < 1 ||
        at == null) {
      return null;
    }
    return TokenCalibration(
      accountId: accountId,
      model: model,
      tokensPerCard: value.toDouble(),
      samples: samples.toInt(),
      updatedAt: at.toUtc(),
    );
  }

  @override
  String toString() =>
      'TokenCalibration($accountId/$model: '
      '${tokensPerCard.toStringAsFixed(1)} tpc, $samples замеров)';
}

/// Порт хранилища калибровки.
abstract interface class TokenCalibrationStore {
  /// Все записи (для UI/диагностики).
  Future<List<TokenCalibration>> readAll();

  /// Калибровка для аккаунта/модели; применяйте только при `isApplicable`.
  Future<TokenCalibration?> read({
    required String accountId,
    required String model,
  });

  /// Добавляет замер — EMA после первых двух.
  Future<TokenCalibration> record({
    required String accountId,
    required String model,
    required double observedTokensPerCard,
    DateTime? at,
  });
}
