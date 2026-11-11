/// Слой M3 Expressive (ADR-001): единственная точка импорта community-библиотеки.
///
/// UI-код импортирует M3E-компоненты только из этого файла, поэтому библиотеку
/// можно заменить, не трогая экраны. Две M3E-библиотеки в одном виджете
/// смешивать запрещено (docs/agent-prompt.md).
library;

export 'package:material_3_expressive/material_3_expressive.dart';
