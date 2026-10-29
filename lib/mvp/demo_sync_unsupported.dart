bool get demoSyncSupported => false;
Future<Map<String, dynamic>> sendDemoRequest(
  String role,
  String path,
  Map<String, dynamic> body,
) => Future.error(
  UnsupportedError('Pengiriman demo hanya tersedia di browser lokal.'),
);
