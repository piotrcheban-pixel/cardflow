import 'package:cardflow/api/parsers/pdf_page_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Классификация страниц PDF (итерация L76, ADR-037): один документ может
/// сочетать текстовые страницы и сканы.
void main() {
  test('страница с текстом ≥ порога — текстовая', () {
    final PdfPageClassification page = classifyPdfPage(
      page: 1,
      text: 'Первая страница с полноценным текстовым слоем лекции.',
      imageCount: 2,
    );
    expect(page.kind, PdfPageKind.textLayer);
    expect(page.hasTextLayer, isTrue);
    expect(page.needsRendering, isFalse);
    expect(page.textLength, greaterThan(kPdfPageTextMinLength));
    expect(page.imageCount, 2);
  });

  test('короткий текст без изображений — пустая страница (нужен рендер)', () {
    final PdfPageClassification page = classifyPdfPage(page: 2, text: '  ');
    expect(page.kind, PdfPageKind.blank);
    expect(page.hasTextLayer, isFalse);
    expect(page.needsRendering, isFalse);
  });

  test('короткий текст с изображением — скан/рисунок', () {
    final PdfPageClassification page = classifyPdfPage(
      page: 3,
      text: 'Стр. 3',
      imageCount: 1,
    );
    expect(page.kind, PdfPageKind.scanned);
    expect(page.needsRendering, isTrue);
    expect(page.textLength, 6);
  });

  test('порог текста настраивается', () {
    final PdfPageClassification page = classifyPdfPage(
      page: 1,
      text: 'Короткий текст',
      minTextLength: 5,
    );
    expect(page.kind, PdfPageKind.textLayer);
  });

  test('classifyPdfPages сопоставляет тексты и изображения по страницам', () {
    final List<PdfPageClassification> pages = classifyPdfPages(
      pageTexts: <String>[
        'Длинная текстовая страница с описанием схемы и пояснениями.',
        '',
        'Подпись',
      ],
      imageCounts: <int>[1, 0, 2],
    );
    expect(pages, hasLength(3));
    expect(pages[0].kind, PdfPageKind.textLayer);
    expect(pages[1].kind, PdfPageKind.blank);
    expect(pages[2].kind, PdfPageKind.scanned);
    expect(pages[2].page, 3);
  });

  test('нехватка счётчиков изображений не ломает классификацию', () {
    final List<PdfPageClassification> pages = classifyPdfPages(
      pageTexts: <String>['Первый', 'Второй'],
      imageCounts: const <int>[],
    );
    expect(pages, hasLength(2));
    expect(pages.every((PdfPageClassification p) => p.imageCount == 0), isTrue);
  });
}
