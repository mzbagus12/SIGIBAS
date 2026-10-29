// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveExcelReport(Uint8List bytes) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([
      bytes,
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  );
  final name = 'sigibas-agregat-${DateTime.now().microsecondsSinceEpoch}.xlsx';
  final anchor = html.AnchorElement(href: url)..download = name;
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future.delayed(
    const Duration(seconds: 30),
    () => html.Url.revokeObjectUrl(url),
  );
  return name;
}
