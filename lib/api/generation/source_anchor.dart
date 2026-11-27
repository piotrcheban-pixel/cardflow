import 'content_model.dart';
import 'content_normalizer.dart';

/// Якорь карточки в источнике: блок текста, а не склеенная цитата.
///
/// «Почему?» в предпросмотре показывает [text] — ровно `Block.text` из
/// [Document] (TASK «Срез 9», п. 3). [blockId] — стабильный id блока
/// (`doc:<файл>#<раздел>#<номер>`), [sectionTitle] — заголовок его раздела.
class SourceAnchor {
  /// Создаёт якорь.
  const SourceAnchor({
    required this.blockId,
    required this.fileName,
    required this.text,
    this.sectionTitle,
  });

  /// id блока `ContentModel` — тот же, что у `KnowledgeAnchor.blockId`.
  final String blockId;

  /// Имя файла-источника.
  final String fileName;

  /// Текст блока дословно, без склейки соседних строк.
  final String text;

  /// Заголовок раздела блока (`null` — у раздела нет заголовка).
  final String? sectionTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceAnchor &&
          other.blockId == blockId &&
          other.fileName == fileName &&
          other.text == text &&
          other.sectionTitle == sectionTitle;

  @override
  int get hashCode => Object.hash(blockId, fileName, text, sectionTitle);
}

/// Разрешение цитаты/выдержки карточки в блок `ContentModel`.
///
/// Правило: сначала ищется блок, **содержащий** цитату; если цитата собрана из
/// нескольких строк (склеенный текст — то, что запрещено показывать), берётся
/// самый длинный блок, который целиком входит в цитату. Ничего не найдено —
/// `null`: кнопка «Почему?» не показывается, выдуманный текст не подставляется.
class SourceAnchorResolver {
  /// Создаёт резолвер; [minNeedleLength] отсекает слишком короткие цитаты.
  const SourceAnchorResolver({
    this.normalizer = const ContentNormalizer(),
    this.minNeedleLength = 8,
  });

  /// Нормализатор сравнения (не меняет offsets блоков).
  final ContentNormalizer normalizer;

  /// Минимальная длина цитаты для поиска.
  final int minNeedleLength;

  /// Ищет якорь по [quote] (дословная цитата v3) или [excerpt] (v5–v9).
  ///
  /// [fileName] — подсказка «этот файл первым»: одинаковый текст в разных
  /// файлах не должен переключать источник карточки.
  SourceAnchor? resolve(
    List<Document> documents, {
    String? quote,
    String? excerpt,
    String? fileName,
  }) {
    final List<Document> ordered = _order(documents, fileName);
    for (final String? candidate in <String?>[quote, excerpt]) {
      if (candidate == null) continue;
      final String needle = normalizer
          .normalize(candidate.trim())
          .toLowerCase();
      if (needle.length < minNeedleLength) continue;
      final SourceAnchor? anchor = _find(ordered, needle);
      if (anchor != null) return anchor;
    }
    return null;
  }

  List<Document> _order(List<Document> documents, String? fileName) {
    if (fileName == null || documents.length < 2) return documents;
    final List<Document> first = <Document>[
      for (final Document document in documents)
        if (document.fileName == fileName) document,
    ];
    if (first.isEmpty) return documents;
    return <Document>[
      ...first,
      for (final Document document in documents)
        if (document.fileName != fileName) document,
    ];
  }

  SourceAnchor? _find(List<Document> documents, String needle) {
    Document? containedDoc;
    Block? contained;
    for (final Document document in documents) {
      for (final Block block in document.contentBlocks) {
        final String text = block.normalizedText.toLowerCase();
        if (text.isEmpty) continue;
        if (text.contains(needle)) return _anchor(document, block);
        if (needle.contains(text) && text.length >= minNeedleLength) {
          if (contained == null ||
              text.length > contained.normalizedText.length) {
            contained = block;
            containedDoc = document;
          }
        }
      }
    }
    if (contained == null || containedDoc == null) return null;
    return _anchor(containedDoc, contained);
  }

  SourceAnchor _anchor(Document document, Block block) {
    return SourceAnchor(
      blockId: block.id,
      fileName: document.fileName,
      text: block.text,
      sectionTitle: document.section(block.sectionId)?.title,
    );
  }
}
