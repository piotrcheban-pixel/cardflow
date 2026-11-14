import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/file_picker_image_gateway.dart';
import 'package:cardflow/domain/cards/card_media.dart';

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({
    required this.name,
    required this.size,
    required this._bytes,
  });

  @override
  final String name;

  final int size;

  final Uint8List _bytes;

  @override
  Uri get uri => Uri.file(name);

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => size;

  @override
  Future<int?> length() async => size;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(_bytes);
}

class _FakeImagePickerPlatform extends FilePickerPlatform {
  List<PlatformFile> result = const <PlatformFile>[];
  FileType? pickedType;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickedType = type;
    return result;
  }
}

void main() {
  late FilePickerPlatform original;
  late _FakeImagePickerPlatform fake;
  late FilePickerImageGateway gateway;

  setUp(() {
    original = FilePickerPlatform.instance;
    fake = _FakeImagePickerPlatform();
    FilePickerPlatform.instance = fake;
    gateway = const FilePickerImageGateway();
  });

  tearDown(() {
    FilePickerPlatform.instance = original;
  });

  _FakePlatformFile file(String name, {required List<int> bytes, int? size}) =>
      _FakePlatformFile(
        name: name,
        size: size ?? bytes.length,
        bytes: Uint8List.fromList(bytes),
      );

  test('PNG выбирается как image/png, байты и тип пикера', () async {
    fake.result = <PlatformFile>[
      file('схема.PNG', bytes: <int>[1, 2, 3]),
    ];

    final upload = await gateway.pickImage();

    expect(fake.pickedType, FileType.image);
    expect(upload, isNotNull);
    expect(upload!.fileName, 'схема.PNG');
    expect(upload.mimeType, 'image/png');
    expect(upload.bytes, <int>[1, 2, 3]);
    expect(upload.extension, 'png');
  });

  test('JPEG распознаётся по .jpg и .jpeg', () async {
    fake.result = <PlatformFile>[
      file('фото.JPEG', bytes: <int>[4, 5]),
    ];
    final upload = await gateway.pickImage();
    expect(upload!.mimeType, 'image/jpeg');
    expect(upload.extension, 'jpg');
  });

  test('отмена выбора — null', () async {
    expect(await gateway.pickImage(), isNull);
  });

  test('файл больше 25 МБ отклоняется до чтения', () async {
    fake.result = <PlatformFile>[
      file(
        'large.png',
        bytes: <int>[1],
        size: CardImageGateway.maxImageBytes + 1,
      ),
    ];
    await expectLater(gateway.pickImage(), throwsStateError);
  });

  test('пустой файл и неподдерживаемый формат отклоняются', () async {
    fake.result = <PlatformFile>[file('empty.png', bytes: <int>[])];
    await expectLater(gateway.pickImage(), throwsStateError);

    fake.result = <PlatformFile>[
      file('anim.gif', bytes: <int>[1]),
    ];
    await expectLater(gateway.pickImage(), throwsFormatException);
  });
}
