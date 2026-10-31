import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın kendi pencere düğmeleri (Küçült / Kapat).
///
/// Pencere tam ekran ve başlık çubuğu olmadan açılır; bu düğmeler Windows tarafında
/// `windows/runner/flutter_window.cpp` içindeki "mel_capital/window" kanalına gider.
class NativeWindow {
  NativeWindow._();

  static const MethodChannel _channel = MethodChannel('mel_capital/window');

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<void> minimize() => _call('minimize');

  static Future<void> close() => _call('close');

  static Future<void> _call(String method) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Windows dışında bu kanal yoktur.
    } on PlatformException {
      // Pencere işlemi yapılamadıysa sessizce geç.
    }
  }
}
