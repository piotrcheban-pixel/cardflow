import 'package:xml/xml.dart';

/// Поиск XML-узлов по локальному имени без привязки к префиксу пространства имён.
///
/// OOXML/ODF используют разные префиксы (`w:`, `p:`, `text:`) и пространства
/// имён; парсерам нужны узлы по смыслу (`p`, `t`, `tr`), а не по точному
/// qualified name. Обход идёт в порядке документа.

/// Все элементы-потомки [node] с локальным именем [localName].
Iterable<XmlElement> descendantElementsByLocalName(
  XmlNode node,
  String localName,
) => node.descendantElements.where((XmlElement element) {
  return element.name.local == localName;
});

/// Первый элемент-потомок [node] с локальным именем [localName] (или `null`).
XmlElement? firstDescendantByLocalName(XmlNode node, String localName) {
  for (final XmlElement element in node.descendantElements) {
    if (element.name.local == localName) {
      return element;
    }
  }
  return null;
}

/// Значение атрибута элемента по локальному имени (или `null`).
String? attributeValueByLocalName(XmlElement element, String localName) {
  for (final XmlAttribute attribute in element.attributes) {
    if (attribute.name.local == localName) {
      return attribute.value;
    }
  }
  return null;
}

/// Значение атрибута [element] из пространства имён с префиксом [prefix].
///
/// Нужно для OOXML-атрибутов вида `r:id`, у которых локальное имя `id`
/// совпадает с обычным `id` (например, `<p:sldId id="256" r:id="rId1"/>`).
String? attributeValueByPrefix(
  XmlElement element,
  String localName,
  String prefix,
) {
  for (final XmlAttribute attribute in element.attributes) {
    if (attribute.name.local == localName && attribute.name.prefix == prefix) {
      return attribute.value;
    }
  }
  return null;
}

/// Сжимает последовательности пробельных символов в тексте в один пробел.
String collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+', unicode: true), ' ').trim();
