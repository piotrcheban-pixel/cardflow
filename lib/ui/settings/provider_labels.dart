/// Подписи и иконки провайдеров (ADR-020).
///
/// Единственное место, где протокол/аккаунт превращается в пользовательский
/// текст: названия брендов из каталога не переводятся (SPEC 3.1), служебные
/// подписи — только из ARB.
library;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/sourced.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Локализованная подпись протокола.
String providerProtocolLabel(AppLocalizations l10n, ProviderProtocol protocol) {
  return switch (protocol) {
    ProviderProtocol.openaiCompletions => l10n.providersProtocolOpenAi,
    ProviderProtocol.openai => l10n.generationProviderOpenAi,
    ProviderProtocol.anthropicMessages => l10n.providersProtocolAnthropic,
    ProviderProtocol.geminiGenerateContent => l10n.providersProtocolGemini,
  };
}

/// Подпись аккаунта: бренд каталога или введённое пользователем название.
String providerAccountLabel(AppLocalizations l10n, ProviderAccount account) {
  return account.label.trim().isEmpty ? l10n.providersAddCustom : account.label;
}

/// Сводка аккаунта одной строкой: подпись и модель (если задана).
String providerSummary(AppLocalizations l10n, ProviderAccount account) {
  final String label = providerAccountLabel(l10n, account);
  final String model = account.modelId.trim();
  return model.isEmpty ? label : '$label, $model';
}

/// Иконка протокола для карточек и списков.
IconData providerProtocolIcon(ProviderProtocol protocol) {
  return switch (protocol) {
    ProviderProtocol.openaiCompletions => Icons.dns_outlined,
    ProviderProtocol.openai => Icons.auto_awesome_outlined,
    ProviderProtocol.anthropicMessages => Icons.psychology_outlined,
    ProviderProtocol.geminiGenerateContent => Icons.diamond_outlined,
  };
}
/// Подпись источника характеристики модели (ADR-039 §6).
String capabilitySourceLabel(AppLocalizations l10n, CapabilitySource source) {
  return switch (source) {
    CapabilitySource.userConfigured => l10n.settingsCapabilitiesSourceUser,
    CapabilitySource.providerApi => l10n.settingsCapabilitiesSourceApi,
    CapabilitySource.officialCatalog => l10n.settingsCapabilitiesSourceCatalog,
    CapabilitySource.assumption => l10n.settingsCapabilitiesSourceAssumption,
    CapabilitySource.unknown => l10n.settingsCapabilitiesUnknown,
  };
}