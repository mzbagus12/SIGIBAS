// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickProfilePhoto() async {
  final input = html.FileUploadInputElement()..accept = 'image/png,image/jpeg';
  final selected = Completer<Uint8List?>();
  input.onChange.listen((_) async {
    try {
      final files = input.files;
      if (files == null || files.isEmpty) {
        selected.complete(null);
        return;
      }
      if (files.first.size > 262144) {
        throw const FormatException('Foto maksimal 256 KB');
      }
      final reader = html.FileReader()..readAsArrayBuffer(files.first);
      await reader.onLoad.first;
      final result = reader.result;
      selected.complete(
        result is ByteBuffer ? result.asUint8List() : result as Uint8List,
      );
    } catch (e, st) {
      selected.completeError(e, st);
    }
  });
  input.on['cancel'].listen((_) {
    if (!selected.isCompleted) selected.complete(null);
  });
  input.click();
  return selected.future;
}
