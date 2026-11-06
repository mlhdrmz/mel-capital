// Arka plan fotoğrafları (Unsplash), eski Mel Capital'deki gibi: her sekmede farklı fotoğraf, 4 saatte
// bir hepsi kayar; akşam 19.00–07.00 arası (İstanbul saati) gece şehir ve lobi fotoğrafları öne çıkar.
// Favoriler daha sık gelir, gizlenenler hiç gelmez. Fotoğraflar henüz bu cihazda yoksa uygulamaya gömülü
// kapaklar döner. Seçim eski uygulamanın seçimiyle birebir aynıdır (test/photos_test.dart).

/// Unsplash fotoğrafı: kimlik, fotoğrafçı ve tema (gece, lobi, havuz…; yoksa parlaklığına göre ayrılır).
class Photo {
  const Photo(this.id, this.by, [this.theme]);
  final String id;
  final String by;
  final String? theme;
}

const List<Photo> kPhotos = [
  Photo('1790276317950-cd0cad99655d', 'Rosemary Media'),
  Photo('1774423864869-702b21c2490a', 'Polina Kuzovkova'),
  Photo('1748063578185-3d68121b11ff', 'Arthur Baudry'),
  Photo('1494526585095-c41746248156', 'Brian Babb'),
  Photo('1760824951703-9b63c7cfdf86', 'Pradeep Sus'),
  Photo('1694057545160-e4b0deffe34a', 'Nguyen Phan Nam Anh'),
  Photo('1640829327404-343a637b18fc', 'Joe Han'),
  Photo('1688383213635-9bc2fc25103d', 'Tobias Reich'),
  Photo('1688019983766-216c6a06fe0d', 'Tobias Reich'),
  Photo('1785301973694-d95aebf5bdb8', 'Dylan Taylor'),
  Photo('1765318491150-1efebd26e757', 'Lumin Osity'),
  Photo('1718939043195-da296f62d3f2', 'Michael Lock'),
  Photo('1765421617367-4b6f88423be9', 'Leonardo Vargas'),
  Photo('1707189856923-46dd41ea2bdc', 'Cesar Cid'),
  Photo('1783696137750-9c658a8dd256', 'Tommaso Ubezio'),
  Photo('1638886976308-e5b9cfb6b35b', 'set.sj'),
  Photo('1763831781185-2290dd2ad87f', 'Matthias Cooper'),
  Photo('1559310589-2673bfe16970', 'Adam Vradenburg'),
  Photo('1542751675-5bd6665a0f2b', 'Elisa Kerschbaumer'),
  Photo('1551801319-ca06060f3fcc', 'Bjorn Snelders'),
  Photo('1530735606451-8f5f13955328', 'Mike L'),
  Photo('1735770517146-e95c872226fc', 'Meg von Haartman', 'havuz'),
  Photo('1598924957326-0446ac30341e', 'Kevin Doran', 'havuz'),
  Photo('1644027613475-6bf8ac889599', 'Johnny Africa', 'havuz'),
  Photo('1790276319227-993348bb36c7', 'Rosemary Media', 'havuz'),
  Photo('1790276319737-a22b1c378f9b', 'Rosemary Media', 'havuz'),
  Photo('1760943006664-3278c14068d6', 'Ron Fijian', 'havuz'),
  Photo('1790276319819-124404931132', 'Rosemary Media', 'havuz'),
  Photo('1790276319291-333b451300ce', 'Rosemary Media', 'havuz'),
  Photo('1760943013869-65a30a4fafd1', 'Ron Fijian', 'havuz'),
  Photo('1588504633950-9dc518941e93', 'Anine Beetge', 'havuz'),
  Photo('1758551139137-5cad5a98e99f', 'Nhi Ly', 'gece'),
  Photo('1724795550603-a9678f5f16cc', 'Artem Zhukov', 'gece'),
  Photo('1585412168334-8fa91429cc64', 'Mayank Sehgal', 'gece'),
  Photo('1743020951770-9bc006005c4a', 'Kirill Rahcheev', 'gece'),
  Photo('1724795550603-4476007e4611', 'Artem Zhukov', 'gece'),
  Photo('1681097459634-b93348522bfc', 'Anky Lau', 'gece'),
  Photo('1732123197858-3200cfa9097c', 'HANVIN CHEONG', 'gece'),
  Photo('1694263004826-ff9bf220448d', 'M. İkbal K', 'gece'),
  Photo('1666884257245-7bfcf6e4fc1e', 'Fahrul Razi', 'gece'),
  Photo('1717256770124-e053bebb13b2', 'Joydeep Sensarma', 'gece'),
  Photo('1625244724120-1fd1d34d00f6', 'Oswald Elsaboath', 'lobi'),
  Photo('1590381105924-c72589b9ef3f', 'Rod Long', 'lobi'),
  Photo('1702814160779-4a88cfb330c7', 'Marek Okon', 'lobi'),
  Photo('1677129667171-92abd8740fa3', 'Quang Nguyen Vinh', 'lobi'),
  Photo('1600435335786-d74d2bb6de37', 'reisetopia', 'lobi'),
  Photo('1742844552193-2fd3425cd26d', 'Zoshua Colah', 'lobi'),
  Photo('1742844552700-3926862c5311', 'Zoshua Colah', 'lobi'),
  Photo('1761501989065-7c98a5d1f773', 'HsinKai Tai', 'lobi'),
  Photo('1774192621035-20d11389f781', 'Josh Hild', 'lobi'),
  Photo('1678126581945-0de543dc46b7', 'Carl Gelin', 'lobi'),
  Photo('1697898109604-e06e88b15271', 'Matheen Faiz', 'maldivler'),
  Photo('1662792721650-545a15f07ff6', 'Saffu', 'maldivler'),
  Photo('1743356174397-d6da6f014f8f', 'Ish Consul', 'maldivler'),
  Photo('1743356174408-a4d2dd23230e', 'Ish Consul', 'maldivler'),
  Photo('1743356174523-b04efcc66b46', 'Ish Consul', 'maldivler'),
  Photo('1777199663418-3dd126c9fd40', 'vatsa', 'maldivler'),
  Photo('1693942864574-2d8efeb5cf57', 'Diego Allen', 'bogaz'),
  Photo('1661585115697-67a90d16c7d8', 'Jordi Vich Navarro', 'bogaz'),
  Photo('1785433080117-8d31d0ef9031', 'Nil Gül', 'bogaz'),
  Photo('1785433080236-65577086f750', 'Nil Gül', 'bogaz'),
  Photo('1790255757292-2a9ff25a7dda', 'Halil Celik', 'bogaz'),
  Photo('1562281302-809108fd533c', 'Eugene Chystiakov', 'yat'),
  Photo('1569282066844-679ec34e3416', 'Ender Vatan', 'yat'),
  Photo('1681331325415-a497fd712ee6', 'Catrin Ellis', 'yat'),
  Photo('1570422774250-c951ec3ef74c', 'Herry Sutanto', 'yat'),
  Photo('1590473713374-dc331cb3f60e', 'Colin Chong', 'yat'),
  Photo('1558196876-76dcb9d1993f', 'Janis Kikans', 'dag'),
  Photo('1761477728758-186afe49ab16', 'Luka Peters', 'dag'),
  Photo('1781458366690-2e95ce1bd818', 'Barney Goodman', 'dag'),
  Photo('1768162238254-a7ec8ca9b16b', 'Ioana Trandafir', 'dag'),
  Photo('1674534627228-ebd30de6dc40', 'Madison Kuhn', 'dag'),
  Photo('1579285014902-da8d2ba6007b', 'D Jonez', 'amalfi'),
  Photo('1588729626382-17a7cbc3e2f1', 'Mike Morgan', 'amalfi'),
  Photo('1681942181105-48f0f4a91c6f', 'Nicole Arango Lang', 'amalfi'),
];

/// Fotoğraflar inmemişken kullanılan, uygulamaya gömülü kapaklar (assets/images/cover_<ad>.webp).
/// "lobby" kapağı çıkarıldı: içinde insan vardı (Melih'in isteği); yerine "highrise" kullanılır.
const List<String> kCovers = ['courtyard', 'mountain', 'villa', 'highrise', 'palm', 'santorini', 'lock'];

/// Sekme sayısı: her sekmede farklı fotoğraf olabilmesi için havuzda en az bu kadar fotoğraf gerekir.
/// İçinde insan görünen fotoğraflar: arka planda hiç gösterilmez (kullanıcının isteği).
const Set<String> kPeoplePhotos = {
  '1625244724120-1fd1d34d00f6', // lobi, resepsiyonda çalışanlar
  '1735770517146-e95c872226fc', // sonsuzluk havuzunda yüzen biri
};

const int kPhotoPages = 7;
const int kPhotoSlotMs = 4 * 3600 * 1000;
const Set<String> kNightThemes = {'gece', 'lobi'};

/// Teması belirtilmemiş fotoğraflarda: ortalama parlaklığı bundan düşükse "akşam" fotoğrafı sayılır.
const double kNightLum = 0.36;
const String kUnsplashRef = 'https://unsplash.com/?utm_source=mel_capital&utm_medium=referral';
final RegExp kPhotoIdRe = RegExp(r'^[0-9]{10,13}-[0-9a-f]{12}$');

Photo? photoById(String? id) {
  for (final p in kPhotos) {
    if (p.id == id) return p;
  }
  return null;
}

/// Fotoğrafçılar (her biri bir kez), Ayarlar'daki teşekkür yazısı için.
List<String> photoCredits() {
  final out = <String>[];
  for (final p in kPhotos) {
    if (!out.contains(p.by)) out.add(p.by);
  }
  return out;
}

/// Akşam mı? (İstanbul saatiyle 19.00 – 07.00)
bool isEveningIst(DateTime now) {
  final h = now.toUtc().add(const Duration(hours: 3)).hour;
  return h >= 19 || h < 7;
}

bool photoIsNight(Photo p, Map<String, double> lum) {
  final t = p.theme;
  if (t != null) return kNightThemes.contains(t);
  final l = lum[p.id];
  return l != null && l >= 0 && l < kNightLum;
}

/// Bu cihazda olan, gizlenmemiş fotoğraflar; akşam teması açıksa saate uygun olanlar (yeterince varsa).
/// Favoriler listede iki kez yer alır: daha sık gelir.
List<Photo> photoPool({
  required Set<String> avail,
  required Map<String, double> lum,
  required Set<String> hide,
  required Set<String> fav,
  required bool night,
  required DateTime now,
}) {
  final av = [
    for (final p in kPhotos)
      if (avail.contains(p.id) && !hide.contains(p.id)) p,
  ];
  var pool = av;
  if (night) {
    final ev = isEveningIst(now);
    final themed = [
      for (final p in av)
        if (photoIsNight(p, lum) == ev) p,
    ];
    if (themed.length >= kPhotoPages) pool = themed;
  }
  return [
    for (final p in pool) ...[p, if (fav.contains(p.id)) p],
  ];
}

/// Arka planın seçimi: fotoğraf ya da (havuzda yeterince fotoğraf yoksa) gömülü kapak.
class BgPick {
  const BgPick.photo(Photo this.photo) : cover = null;
  const BgPick.cover(String this.cover) : photo = null;
  final Photo? photo;
  final String? cover;

  String get key => photo?.id ?? 'kapak-$cover';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// Sekmenin ([page], 0'dan) arka planı: her sekmede farklı; 4 saatte bir hepsi kayar.
BgPick bgPick(List<Photo> pool, int page, DateTime now) {
  final photos = pool.length >= kPhotoPages;
  final n = photos ? pool.length : kCovers.length;
  final i = page < 0 ? 0 : page;
  final slot = (now.millisecondsSinceEpoch + 3 * 3600 * 1000) ~/ kPhotoSlotMs;
  var step = n > 8 ? 5 : 3;
  while (_gcd(step, n) != 1) {
    step++;
  }
  int at(int k) => (k % n + n) % n;
  var idx = at(slot * 3 + i * step);
  // Favori listede iki kez: komşu sekmelerde aynı fotoğraf çıkarsa bir sonrakini al
  if (photos && n > kPhotoPages && i > 0 && pool[at(slot * 3 + (i - 1) * step)].id == pool[idx].id) {
    idx = at(slot * 3 + i * step + 1);
  }
  return photos ? BgPick.photo(pool[idx]) : BgPick.cover(kCovers[idx]);
}
