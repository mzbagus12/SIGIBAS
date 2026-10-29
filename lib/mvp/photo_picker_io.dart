import 'package:flutter/services.dart';

Future<Uint8List?> pickProfilePhoto() =>
    const MethodChannel('sigibas/photos').invokeMethod<Uint8List>('pick');
