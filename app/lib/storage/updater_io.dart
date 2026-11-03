import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../core/update.dart';
import 'updater.dart';

/// Windows: GitHub'a sorar, güncelleme dosyasını indirir ve başlatır.
/// Telefonda yalnızca sorar; yeni APK tarayıcıda indirilir (Android kurulumu kendisi sorar).
Updater? createPlatformUpdater() => Platform.isWindows || Platform.isAndroid ? IoUpdater() : null;

class IoUpdater implements Updater {
  static const String _agent = 'MelCapital';

  @override
  Future<Object?> fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(kReleasesApi));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, _agent);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null; // henüz resmi sürüm yok
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('GitHub ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  String get _exeDir => File(Platform.resolvedExecutable).parent.path;

  @override
  bool get installed => Platform.isWindows && File('$_exeDir${Platform.pathSeparator}Kaldır.exe').existsSync();

  @override
  Future<String> download(UpdateInfo info, void Function(double progress) onProgress) async {
    final file = info.updater;
    if (file == null) throw StateError('Bu sürümde güncelleme dosyası yok.');
    final sep = Platform.pathSeparator;
    final dir = Directory('${Directory.systemTemp.path}${sep}Mel Capital');
    await dir.create(recursive: true);
    final label = info.label.isEmpty ? '${info.build}' : info.label;
    final path = '${dir.path}${sep}Mel Capital Güncelleme $label.exe';
    final part = File('$path.indiriliyor');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(file.url));
      req.headers.set(HttpHeaders.userAgentHeader, _agent);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('İndirme ${res.statusCode}');
      }
      final total = file.size ?? (res.contentLength > 0 ? res.contentLength : 0);
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got >= total ? 1.0 : got / total);
        }
      } finally {
        await sink.close();
      }
      if (file.size != null && got != file.size) {
        throw StateError('İndirilen dosya eksik ($got / ${file.size} bayt).');
      }
      if (file.sha256 != null) {
        final digest = crypto.sha256.convert(await part.readAsBytes()).toString();
        if (digest != file.sha256) throw StateError('İndirilen dosya bozuk (özet tutmadı).');
      }
      final out = File(path);
      if (await out.exists()) await out.delete();
      await part.rename(path);
      return path;
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> launch(String path) async {
    await Process.start(
      path,
      const ['--uygulamadan'],
      mode: ProcessStartMode.detached,
      workingDirectory: File(path).parent.path,
    );
  }
}
