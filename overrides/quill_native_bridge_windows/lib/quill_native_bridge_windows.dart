library quill_native_bridge_windows;

import 'package:quill_native_bridge_platform_interface/quill_native_bridge_platform_interface.dart';

class QuillNativeBridgeWindows extends QuillNativeBridgePlatform {
  static void registerWith(dynamic registrar) {}
  
  @override
  Future<bool> isSupported() async => false;
}
