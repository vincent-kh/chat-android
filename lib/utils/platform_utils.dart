import 'package:flutter/foundation.dart' show kIsWeb;

// 非Web平台的實現
class PlatformUtils {
  static void performAction() {
    // 移動平台實現
    print('使用移動平台的實現');
  }
}