/// Версия кода живого замера (TASK срез 15, часть 1, п. 3).
///
/// В каждой строке `matrix.jsonl` — короткий хеш коммита, на котором снята
/// ячейка. Строки без него считаются `legacy-schema` и в сравнение не идут:
/// иначе числа с разного кода стояли бы в одной таблице.
library;

import 'dart:io';

/// Версия кода: короткий хеш и признак изменённого рабочего дерева.
class CodeVersion {
  /// Создаёт версию.
  const CodeVersion({required this.commit, required this.dirty});

  /// Короткий хеш коммита (`cb8373bd`) или `unknown`, если git недоступен.
  final String commit;

  /// true — рабочее дерево было изменено: хеш не описывает код полностью.
  final bool dirty;

  /// Значение для `code_version` в матрице: хеш, у грязного дерева — `+dirty`.
  String get value => dirty ? '$commit+dirty' : commit;

  /// Определяет версию текущего рабочего дерева (git в PATH).
  static CodeVersion detect() {
    try {
      final ProcessResult head = Process.runSync('git', <String>[
        'rev-parse',
        '--short=8',
        'HEAD',
      ]);
      if (head.exitCode != 0)
        return const CodeVersion(commit: 'unknown', dirty: true);
      final String commit = (head.stdout as String).trim();
      final ProcessResult status = Process.runSync('git', <String>[
        'status',
        '--porcelain',
        '--untracked-files=no',
      ]);
      final bool dirty =
          status.exitCode != 0 || (status.stdout as String).trim().isNotEmpty;
      return CodeVersion(
        commit: commit.isEmpty ? 'unknown' : commit,
        dirty: dirty,
      );
    } on Object {
      return const CodeVersion(commit: 'unknown', dirty: true);
    }
  }
}
