// Yeni sürüm denetimi ve güncelleme dosyasının indirilip başlatılması.
// Windows'ta GitHub'a bağlanılır; web önizlemesinde yoktur.

import '../core/update.dart';
import 'updater_stub.dart' if (dart.library.io) 'updater_io.dart' as platform;

abstract class Updater {
  /// GitHub'daki son resmi sürümün bilgisi (ham JSON). Henüz resmi sürüm yoksa null;
  /// internet yoksa hata fırlatır. Yalnızca sürüm bilgisi istenir, veri gönderilmez.
  Future<Object?> fetchLatest();

  /// Bu kopya kurulum programıyla mı kurulmuş (yanında Kaldır.exe var mı)?
  /// Kuruluysa güncelleme tek tıkla yapılır; değilse sürüm sayfası açılır.
  bool get installed;

  /// Güncelleme dosyasını geçici klasöre indirir, boyutunu ve özetini denetler; yolunu döner.
  Future<String> download(UpdateInfo info, void Function(double progress) onProgress);

  /// Güncelleme dosyasını başlatır. Uygulamayı o kapatır, yeni sürümü kurar ve yeniden açar.
  Future<void> launch(String path);
}

/// Bu platformun güncelleyicisi (web'de null).
Updater? createUpdater() => platform.createPlatformUpdater();
