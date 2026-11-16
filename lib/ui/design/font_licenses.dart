import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:cardflow/ui/design/tokens/nc_typography.dart';

/// Регистрация лицензий шрифтов Nocturne (REDESIGN-SPEC §2.1, ADR-035).
///
/// Файлы шрифтов — локальные ассеты (OFL 1.1), лицензии лежат рядом в
/// `assets/fonts/LICENSES/` и показываются на экране лицензий Flutter.
/// Вызывается при старте приложения (до `runApp`), без побочной логики.
const Map<String, String> ncFontLicenses = <String, String>{
  NcTypography.sansFamily: 'assets/fonts/LICENSES/Onest-OFL.txt',
  NcTypography.serifFamily: 'assets/fonts/LICENSES/Literata-OFL.txt',
  NcTypography.monoFamily: 'assets/fonts/LICENSES/JetBrainsMono-OFL.txt',
};

/// Добавляет лицензии Onest / Literata / JetBrains Mono в `LicenseRegistry`.
void registerNcFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry<String, String> entry in ncFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks(<String>[
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
}
