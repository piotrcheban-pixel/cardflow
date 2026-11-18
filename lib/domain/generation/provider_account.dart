/// Аккаунт провайдера генерации: протокол, адрес, модель и ключ (ADR-020).
///
/// Ключ API здесь не хранится: он живёт только в `ApiKeyStore` (secure storage,
/// SPEC 3.4) под [ProviderAccount.id]. Список аккаунтов — одно JSON-значение
/// `app_settings` с ключом `generation.providers`; схема БД не меняется.
/// Домен не зависит от Flutter, сети и БД.
library;

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Контекст пользовательского аккаунта по умолчанию — историческое поле JSON
/// (`context_tokens`), **не** подтверждённое окно модели (L-18).
///
/// `resolveModelCapabilities` намеренно не использует это значение как окно:
/// неизвестное окно остаётся неизвестным и получает консервативную стратегию
/// планировщика. Константа сохранена для обратной совместимости старых записей
/// и отображения в настройках.
const int kCustomProviderContextTokens = 16000;

/// Настроенный провайдер генерации.
class ProviderAccount {
  /// Создаёт аккаунт.
  ///
  /// Поля возможностей и цен (JSON v2, раздел K.1 аудита TASK 01) необязательны
  /// и по умолчанию неизвестны (`null`): отсутствие значения — «неизвестно»,
  /// а не 0 и не типовое число семейства моделей.
  const ProviderAccount({
    required this.id,
    required this.label,
    required this.protocol,
    required this.baseUrl,
    required this.modelId,
    this.presetId,
    this.contextTokens = kCustomProviderContextTokens,
    this.requiresApiKey = false,
    this.supportsVision = false,
    this.maxOutputTokens,
    this.maxImagesPerRequest,
    this.maxImageBytes,
    this.maxRequestBytes,
    this.pricing,
    this.capabilitiesSource = CapabilitySource.unknown,
  });

  /// Аккаунт из пресета каталога; [id] — id аккаунта (=== ключ secure storage).
  factory ProviderAccount.fromPreset(
    ProviderPreset preset, {
    required String id,
    String? modelId,
  }) {
    final ProviderPresetModel model = modelId == null
        ? preset.defaultModel
        : (preset.modelById(modelId) ?? preset.defaultModel);
    return ProviderAccount(
      id: id,
      label: preset.label,
      presetId: preset.id,
      protocol: preset.protocol,
      baseUrl: preset.baseUrl,
      modelId: model.id,
      contextTokens: model.contextTokens,
      requiresApiKey: preset.requiresApiKey,
      supportsVision: model.supportsVision,
    );
  }

  /// Идентификатор аккаунта; он же ключ в secure storage
  /// (`cardflow.api_key.<id>`), поэтому не меняется при редактировании.
  final String id;

  /// Отображаемое имя: бренд пресета или название, введённое пользователем.
  final String label;

  /// id пресета каталога; `null` — пользовательская модель API.
  final String? presetId;

  /// Протокол API.
  final ProviderProtocol protocol;

  /// Базовый адрес сервера.
  final String baseUrl;

  /// Идентификатор модели в запросе.
  final String modelId;

  /// Окно контекста модели, токенов (для нарезки фрагментов).
  final int contextTokens;

  /// Требуется ли ключ доступа (локальному серверу — нет).
  final bool requiresApiKey;

  /// Принимает ли модель изображения (Vision).
  final bool supportsVision;

  /// Жёсткий лимит вывода модели, токенов; `null` — неизвестно.
  final int? maxOutputTokens;

  /// Максимум image-частей в одном запросе; `null` — неизвестно.
  final int? maxImagesPerRequest;

  /// Максимум байт одного изображения; `null` — неизвестно.
  final int? maxImageBytes;

  /// Максимум байт тела запроса; `null` — неизвестно.
  final int? maxRequestBytes;

  /// Цены аккаунта; `null` — неизвестны.
  final GenerationPricing? pricing;

  /// Источник полей возможностей/цен аккаунта (JSON v2).
  final CapabilitySource capabilitiesSource;

  /// Пресет каталога, если аккаунт создан из каталога.
  ProviderPreset? get preset =>
      presetId == null ? null : providerPresetById(presetId!);

  /// true, если заданы адрес и модель.
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && modelId.trim().isNotEmpty;

  /// Копия с изменёнными полями.
  ///
  /// `null` означает «не менять» (в том числе для новых nullable-полей
  /// возможностей: очистка значений — отдельная операция будущего UI).
  /// [presetId] не обнуляется: `null` означает «не менять» — для
  /// пользовательского аккаунта пресета и так нет.
  ProviderAccount copyWith({
    String? label,
    ProviderProtocol? protocol,
    String? baseUrl,
    String? modelId,
    int? contextTokens,
    bool? requiresApiKey,
    bool? supportsVision,
    int? maxOutputTokens,
    int? maxImagesPerRequest,
    int? maxImageBytes,
    int? maxRequestBytes,
    GenerationPricing? pricing,
    CapabilitySource? capabilitiesSource,
  }) {
    return ProviderAccount(
      id: id,
      label: label ?? this.label,
      presetId: presetId,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      modelId: modelId ?? this.modelId,
      contextTokens: contextTokens ?? this.contextTokens,
      requiresApiKey: requiresApiKey ?? this.requiresApiKey,
      supportsVision: supportsVision ?? this.supportsVision,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      maxImagesPerRequest: maxImagesPerRequest ?? this.maxImagesPerRequest,
      maxImageBytes: maxImageBytes ?? this.maxImageBytes,
      maxRequestBytes: maxRequestBytes ?? this.maxRequestBytes,
      pricing: pricing ?? this.pricing,
      capabilitiesSource: capabilitiesSource ?? this.capabilitiesSource,
    );
  }

  /// Представление для `app_settings.value_json` (без ключа API).
  ///
  /// Новые поля возможностей/цен пишутся всегда (в том числе `null`) —
  /// так форма JSON v2 однозначна; чтение v1 (без этих ключей) поддерживается.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'preset_id': presetId,
    'protocol': protocol.wireName,
    'base_url': baseUrl,
    'model': modelId,
    'context_tokens': contextTokens,
    'requires_api_key': requiresApiKey,
    'supports_vision': supportsVision,
    'max_output_tokens': maxOutputTokens,
    'max_images_per_request': maxImagesPerRequest,
    'max_image_bytes': maxImageBytes,
    'max_request_bytes': maxRequestBytes,
    'pricing': pricing?.toJson(),
    'capabilities_source': capabilitiesSource.wireName,
  };

  /// Разбирает аккаунт из JSON; `null` — запись некорректна и пропускается.
  ///
  /// Читает и v1 (без полей возможностей/цен), и v2 (раздел K.1 аудита):
  /// отсутствующие, нулевые и отрицательные значения остаются неизвестными
  /// (`null`), а не подменяются нулём.
  static ProviderAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? rawId = json['id'];
    final Object? rawProtocol = json['protocol'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    if (rawProtocol is! String) return null;
    final ProviderProtocol protocol;
    try {
      protocol = ProviderProtocol.fromWire(rawProtocol);
    } on FormatException {
      return null;
    }
    final Object? rawPreset = json['preset_id'];
    final String? presetId = rawPreset is String && rawPreset.isNotEmpty
        ? rawPreset
        : null;
    final Object? rawBaseUrl = json['base_url'];
    final Object? rawModel = json['model'];
    final Object? rawContext = json['context_tokens'];
    final Object? rawRequiresKey = json['requires_api_key'];
    final Object? rawLabel = json['label'];
    final String modelId = rawModel is String ? rawModel : '';
    final Object? rawVision = json['supports_vision'];
    final bool supportsVision = rawVision is bool
        ? rawVision
        : _supportsVisionFromLegacy(presetId, modelId);
    return ProviderAccount(
      id: rawId,
      label: rawLabel is String ? rawLabel : '',
      presetId: presetId,
      protocol: protocol,
      baseUrl: rawBaseUrl is String ? rawBaseUrl : '',
      modelId: modelId,
      contextTokens: rawContext is num && rawContext > 0
          ? rawContext.toInt()
          : kCustomProviderContextTokens,
      requiresApiKey: rawRequiresKey is bool ? rawRequiresKey : false,
      supportsVision: supportsVision,
      maxOutputTokens: _positiveIntFromJson(json['max_output_tokens']),
      maxImagesPerRequest: _positiveIntFromJson(json['max_images_per_request']),
      maxImageBytes: _positiveIntFromJson(json['max_image_bytes']),
      maxRequestBytes: _positiveIntFromJson(json['max_request_bytes']),
      pricing: GenerationPricing.fromJson(json['pricing']),
      capabilitiesSource: CapabilitySource.fromWire(
        json['capabilities_source'],
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderAccount &&
          other.id == id &&
          other.label == label &&
          other.presetId == presetId &&
          other.protocol == protocol &&
          other.baseUrl == baseUrl &&
          other.modelId == modelId &&
          other.contextTokens == contextTokens &&
          other.requiresApiKey == requiresApiKey &&
          other.supportsVision == supportsVision &&
          other.maxOutputTokens == maxOutputTokens &&
          other.maxImagesPerRequest == maxImagesPerRequest &&
          other.maxImageBytes == maxImageBytes &&
          other.maxRequestBytes == maxRequestBytes &&
          other.pricing == pricing &&
          other.capabilitiesSource == capabilitiesSource;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    presetId,
    protocol,
    baseUrl,
    modelId,
    contextTokens,
    requiresApiKey,
    supportsVision,
    maxOutputTokens,
    maxImagesPerRequest,
    maxImageBytes,
    maxRequestBytes,
    pricing,
    capabilitiesSource,
  );

  @override
  String toString() => 'ProviderAccount($id, ${protocol.wireName}, $modelId)';
}

/// Положительное целое из JSON; отсутствующее, нулевое и отрицательное —
/// «неизвестно» (`null`), а не 0.
int? _positiveIntFromJson(Object? value) {
  if (value is num && value.isFinite && value > 0) return value.toInt();
  return null;
}

/// Vision для старой записи без `supports_vision`: модель пресета или имя.
bool _supportsVisionFromLegacy(String? presetId, String modelId) {
  final ProviderPreset? preset = presetId == null
      ? null
      : providerPresetById(presetId);
  final ProviderPresetModel? model = preset?.modelById(modelId);
  if (model != null) return model.supportsVision;
  return inferSupportsVisionFromModelId(modelId);
}

/// Выводит поддержку изображений из имени модели для старой записи или
/// пользовательской модели: `gpt-4o`, `claude`, `gemini`, `flash`, `vision`,
/// `vl`, `llava`. Текстовые модели (`deepseek-chat`, `qwen2.5`, `llama`)
/// остаются без Vision; пользователь может включить его в настройках.
bool inferSupportsVisionFromModelId(String modelId) {
  final String id = modelId.trim().toLowerCase();
  if (id.isEmpty) return false;
  const List<String> markers = <String>[
    'gpt-4o',
    'gpt-4.1',
    'gpt-5',
    'claude',
    'gemini',
    'flash',
    'vision',
    'llava',
  ];
  if (markers.any(id.contains)) return true;
  return RegExp(r'(^|[^a-z0-9])vl([^a-z0-9]|$)').hasMatch(id);
}

/// Список настроенных провайдеров и выбранный основной аккаунт.
class ProviderAccounts {
  /// Создаёт список.
  const ProviderAccounts({
    this.accounts = const <ProviderAccount>[],
    this.activeAccountId,
  });

  /// Версия контракта JSON (`generation.providers`).
  ///
  /// v2 добавляет nullable-поля возможностей/цен (раздел K.1 аудита TASK 01).
  /// Чтение v1 поддерживается: отсутствующие поля остаются неизвестными.
  static const int version = 2;

  /// Пустой список.
  static const ProviderAccounts empty = ProviderAccounts();

  /// Настроенные аккаунты (порядок добавления).
  final List<ProviderAccount> accounts;

  /// id основного аккаунта; `null`/отсутствующий — первый из списка.
  final String? activeAccountId;

  /// true, если провайдеров нет.
  bool get isEmpty => accounts.isEmpty;

  /// Аккаунт по id или `null`.
  ProviderAccount? accountById(String id) {
    for (final ProviderAccount account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  /// Основной аккаунт: выбранный, иначе первый; `null` — провайдеров нет.
  ProviderAccount? get active {
    final String? id = activeAccountId;
    if (id != null) {
      final ProviderAccount? selected = accountById(id);
      if (selected != null) return selected;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  /// Список с добавленным или заменённым аккаунтом (по id).
  ProviderAccounts withAccount(ProviderAccount account) {
    final List<ProviderAccount> updated = <ProviderAccount>[
      for (final ProviderAccount item in accounts)
        if (item.id != account.id) item,
    ];
    final int existingIndex = accounts.indexWhere(
      (ProviderAccount item) => item.id == account.id,
    );
    if (existingIndex >= 0) {
      updated.insert(existingIndex, account);
    } else {
      updated.add(account);
    }
    return ProviderAccounts(
      accounts: List<ProviderAccount>.unmodifiable(updated),
      activeAccountId: activeAccountId ?? account.id,
    );
  }

  /// Список без аккаунта [id]; основной переключается на первый оставшийся.
  ProviderAccounts withoutAccount(String id) {
    final List<ProviderAccount> updated = <ProviderAccount>[
      for (final ProviderAccount item in accounts)
        if (item.id != id) item,
    ];
    final String? nextActive = activeAccountId == id
        ? (updated.isEmpty ? null : updated.first.id)
        : activeAccountId;
    return ProviderAccounts(
      accounts: List<ProviderAccount>.unmodifiable(updated),
      activeAccountId: nextActive,
    );
  }

  /// Список с другим основным аккаунтом (`null` — сбросить выбор).
  ProviderAccounts withActive(String? id) {
    return ProviderAccounts(
      accounts: accounts,
      activeAccountId: id != null && accountById(id) != null ? id : null,
    );
  }

  /// Представление для `app_settings.value_json`.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'accounts': <Object?>[
      for (final ProviderAccount account in accounts) account.toJson(),
    ],
    'active_id': activeAccountId,
  };

  /// Разбирает список из JSON; повреждённые записи пропускаются.
  static ProviderAccounts fromJson(Object? json) {
    if (json is! Map) return ProviderAccounts.empty;
    final Object? rawAccounts = json['accounts'];
    if (rawAccounts is! List) return ProviderAccounts.empty;
    final List<ProviderAccount> parsed = <ProviderAccount>[
      for (final Object? item in rawAccounts)
        if (ProviderAccount.fromJson(item) case final ProviderAccount account)
          account,
    ];
    final Object? rawActive = json['active_id'];
    final String? activeId = rawActive is String ? rawActive : null;
    final ProviderAccounts result = ProviderAccounts(
      accounts: List<ProviderAccount>.unmodifiable(parsed),
    );
    return activeId == null ? result : result.withActive(activeId);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderAccounts &&
          other.activeAccountId == activeAccountId &&
          _sameAccounts(other.accounts);

  bool _sameAccounts(List<ProviderAccount> other) {
    if (other.length != accounts.length) return false;
    for (int index = 0; index < other.length; index++) {
      if (other[index] != accounts[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(accounts), activeAccountId);

  @override
  String toString() =>
      'ProviderAccounts(${accounts.length}, active: '
      '$activeAccountId)';
}

/// Приводит строку к пригодному id аккаунта: латиница/цифры/дефис в нижнем
/// регистре. Кириллица и прочие символы отбрасываются (id — ключ хранилища).
String slugifyProviderId(String value) {
  final String lower = value.trim().toLowerCase();
  final StringBuffer buffer = StringBuffer();
  var lastWasDash = false;
  for (final int codeUnit in lower.codeUnits) {
    final bool isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final bool isLatin = codeUnit >= 0x61 && codeUnit <= 0x7A;
    if (isDigit || isLatin) {
      buffer.writeCharCode(codeUnit);
      lastWasDash = false;
    } else if (!lastWasDash && buffer.isNotEmpty) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  var slug = buffer.toString();
  while (slug.endsWith('-')) {
    slug = slug.substring(0, slug.length - 1);
  }
  return slug;
}

/// Уникальный id аккаунта: [base] или [base]-2, [base]-3, … среди [taken].
String uniqueProviderAccountId(String base, Iterable<String> taken) {
  final Set<String> used = <String>{...taken};
  final String slug = slugifyProviderId(base);
  final String root = slug.isEmpty ? 'provider' : slug;
  if (!used.contains(root)) return root;
  var counter = 2;
  while (used.contains('$root-$counter')) {
    counter++;
  }
  return '$root-$counter';
}
