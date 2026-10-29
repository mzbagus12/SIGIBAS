import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

Future<String> saveExcelReport(Uint8List bytes) async {
  final name = 'sigibas-agregat-${DateTime.now().microsecondsSinceEpoch}.xlsx';
  if (Platform.isAndroid) {
    // Native adapter writes a private temporary file and grants read access only
    // to the share-sheet recipient through FileProvider.
    final result = await const MethodChannel('sigibas/reports')
        .invokeMethod<String>('shareExcel', {
          'bytes': bytes,
          'name': name,
          'mime': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        });
    if (result != 'shared') {
      throw StateError('Lembar berbagi Excel tidak dapat dibuka. Coba lagi.');
    }
    return 'lembar berbagi Android dibuka; pilih aplikasi atau Simpan ke File';
  }
  final directory = await getApplicationDocumentsDirectory();
  final path = '${directory.path}${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
