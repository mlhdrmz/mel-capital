// Yeni sürüm bilgisi: GitHub'daki son resmi sürümün ("releases/latest") yanıtı okunur.
// Uygulama yalnızca sürüm bilgisini ister; hiçbir veri gönderilmez.

import 'version.dart';

const String kReleasesApi = 'https://api.github.com/repos/mlhdrmz/mel-capital/releases/latest';
const String kReleasesPage = 'https://github.com/mlhdrmz/mel-capital/releases/latest';

/// Resmi sürümlerin etiketi "s<derleme numarası>" biçimindedir (ör. s145).
int? buildFromTag(String? tag) {
  final m = RegExp(r'^s(\d+)$').firstMatch(tag?.trim() ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Bir sürüm dosyası (indirme bağlantısı, boyutu, özeti).
class ReleaseFile {
  const ReleaseFile({required this.name, required this.url, this.size, this.sha256});

  final String name;
  final String url;
  final int? size;

  /// SHA-256 özeti (küçük harf onaltılık); GitHub vermezse null.
  final String? sha256;
}

/// Kullanılan sürümden daha yeni bir sürüm.
class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.label,
    required this.pageUrl,
    this.updater,
    this.setup,
    this.apk,
    this.notes = '',
  });

  /// Derleme numarası.
  final int build;

  /// Tarih-saat etiketi ("05.11.2026-14.20"); bulunamazsa boş.
  final String label;

  /// Sürümün GitHub sayfası.
  final String pageUrl;

  /// "Mel Capital Güncelleme" dosyası (kurulu uygulamayı yeni sürümle değiştirir).
  final ReleaseFile? updater;

  /// "Mel Capital Kurulum" dosyası.
  final ReleaseFile? setup;

  /// Telefon uygulaması (APK).
  final ReleaseFile? apk;

  /// Sürüm notları (kısaltılmış).
  final String notes;
}

ReleaseFile? _file(Object? raw) {
  if (raw is! Map) return null;
  final name = raw['name']?.toString() ?? '';
  final url = raw['browser_download_url']?.toString() ?? '';
  if (name.isEmpty || !url.startsWith('https://')) return null;
  final size = raw['size'];
  final digest = raw['digest']?.toString() ?? '';
  final sha = digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null;
  return ReleaseFile(
    name: name,
    url: url,
    size: size is int && size > 0 ? size : null,
    sha256: sha != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
  );
}

/// GitHub'ın "son sürüm" yanıtını okur. Sürüm [current] derlemesinden yeniyse bilgisini,
/// değilse (ya da yanıt tanınmazsa) null döner. [current] 0 ise (geliştirme derlemesi) hep null.
UpdateInfo? parseRelease(Object? raw, {required int current}) {
  if (current <= 0 || raw is! Map) return null;
  if (raw['draft'] == true || raw['prerelease'] == true) return null;
  final build = buildFromTag(raw['tag_name']?.toString());
  if (build == null || build <= current) return null;
  ReleaseFile? updater;
  ReleaseFile? setup;
  ReleaseFile? apk;
  final assets = raw['assets'];
  if (assets is List) {
    for (final a in assets) {
      final f = _file(a);
      if (f == null || !f.name.startsWith('MelCapital')) continue;
      final name = f.name.toLowerCase();
      if (name.endsWith('.apk')) apk ??= f;
      if (!name.endsWith('.exe')) continue;
      if (f.name.startsWith('MelCapital-Guncelleme')) updater ??= f;
      if (f.name.startsWith('MelCapital-Kurulum')) setup ??= f;
    }
  }
  final page = raw['html_url']?.toString() ?? '';
  var notes = (raw['body']?.toString() ?? '').replaceAll('\r', '').trim();
  if (notes.length > 600) notes = '${notes.substring(0, 600).trimRight()}…';
  return UpdateInfo(
    build: build,
    label: findBuildLabel(raw['name']?.toString()) ?? findBuildLabel(updater?.name) ?? '',
    pageUrl: page.startsWith('https://') ? page : kReleasesPage,
    updater: updater,
    setup: setup,
    apk: apk,
    notes: notes,
  );
}
