// Arka plan, eski Mel Capital'deki gibi: sekmenin Unsplash fotoğrafı (her sekmede farklı, 4 saatte bir kayar,
// akşamları gece fotoğrafları), fotoğraflar henüz inmemişse uygulamaya gömülü kapaklar. Fotoğraf
// değişince yumuşakça (kısa) geçer; üstüne karartma ya da buğu konmaz. Gösterilen fotoğrafın bulanık
// kopyası bir kez hazırlanır (bulanik.dart): yazıların arkasındaki bulanıklık onu kullanır. Sağ altta fotoğrafçının adı, favori ve
// "Gösterme" düğmeleri.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/photos.dart';
import '../storage/photos.dart';
import 'bulanik.dart';
import 'i18n.dart';
import 'pages/alisveris.dart' show openLink;
import 'photo_image_stub.dart' if (dart.library.io) 'photo_image_io.dart';
import 'state.dart';
import 'ui.dart' show isPhoneLayout, toast;

/// Fotoğrafın ekrandaki yeri: yatayda ortada, dikeyde biraz yukarıda (eski uygulamada "center 42%").
const Alignment kPhotoAlignment = Alignment(0, -0.16);

class Background extends StatefulWidget {
  const Background({super.key, required this.page, required this.cover, this.rotate = false});

  /// Sekmenin sırası (sekme dışı ekranlarda 0).
  final int page;

  /// Fotoğraf yokken (ve fotoğraf yüklenirken) görünen gömülü kapak.
  final String cover;

  /// Sekmelerde fotoğraf yokken kapaklar da eski uygulamadaki gibi dönsün mü.
  final bool rotate;

  @override
  State<Background> createState() => _BackgroundState();
}

class _BackgroundState extends State<Background> {
  Timer? _timer;
  bool _started = false;
  String? _shownKey;
  ImageProvider? _shown;
  String? _loadingKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final st = AppScope.of(context);
    if (st.photoStore == null) return;
    if (!_started) {
      _started = true;
      // Ekranın gerçek çözünürlüğünde indirilsin (bilgisayarda 1920/2560/3840, telefonda ekranın kendisi)
      final view = View.of(context);
      Size logical;
      double dpr;
      try {
        final d = view.display;
        dpr = d.devicePixelRatio;
        logical = d.size / dpr;
      } catch (_) {
        dpr = view.devicePixelRatio;
        logical = view.physicalSize / dpr;
      }
      unawaited(st.startPhotos(PhotoSize.forScreen(width: logical.width, height: logical.height, dpr: dpr, phone: st.phone)));
    }
    // 4 saatlik dilim ve akşam teması saatle değişir: ara ara yeniden bakılır.
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show(String key, ImageProvider image, Photo? photo) {
    if (key == _shownKey || key == _loadingKey) return;
    // İlk açılışta ve kapaklarda beklemeden; fotoğraflar yüklenince geçer.
    if (_shown == null && photo == null) {
      _shownKey = key;
      _shown = image;
      return;
    }
    _loadingKey = key;
    var failed = false;
    precacheImage(image, context, onError: (_, __) => failed = true).then((_) {
      if (!mounted || _loadingKey != key) return;
      _loadingKey = null;
      if (failed) return;
      setState(() {
        _shownKey = key;
        _shown = image;
      });
      AppScope.of(context).shownPhoto.value = photo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: st.photoTick,
      builder: (context, _, __) {
        final pick = st.bgPickFor(widget.page, DateTime.now());
        final photo = pick.photo;
        final src = photo == null ? null : st.photoSrc(photo.id);
        final image = src == null ? null : photoImage(src);
        if (photo != null && image != null) {
          _show(photo.id, image, photo);
        } else {
          final cover = widget.rotate && pick.cover != null ? pick.cover! : widget.cover;
          final key = 'kapak-$cover';
          if (key != _shownKey) {
            _loadingKey = null;
            _shownKey = key;
            _shown = AssetImage('assets/images/cover_$cover.webp');
            // Kapak görünürken fotoğrafçı yazısı gizlenir
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _shownKey == key) st.shownPhoto.value = null;
            });
          }
        }
        final shown = _shown ?? AssetImage('assets/images/cover_${widget.cover}.webp');
        // Yazıların arkasındaki bulanıklık için bu fotoğrafın bulanık kopyası (bir kez hazırlanır)
        unawaited(bulanikKopyaHazirla(_shownKey ?? 'kapak-${widget.cover}', shown, createLocalImageConfiguration(context)));
        return AnimatedSwitcher(
          // Kısa geçiş: sayfa değişirken uygulama takılmasın
          duration: const Duration(milliseconds: 400),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          child: Image(
            key: ValueKey<String>(_shownKey ?? 'kapak-${widget.cover}'),
            image: shown,
            fit: BoxFit.cover,
            alignment: kPhotoAlignment,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      },
    );
  }
}

/// Sağ altta: fotoğrafçının adı (Unsplash'e bağlantı), favori ve "Gösterme" düğmeleri. Yalnızca arka
/// planda bir fotoğraf varken görünür.
class PhotoBar extends StatefulWidget {
  const PhotoBar({super.key});

  @override
  State<PhotoBar> createState() => _PhotoBarState();
}

class _PhotoBarState extends State<PhotoBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final phone = isPhoneLayout(context);
    return ValueListenableBuilder<Photo?>(
      valueListenable: st.shownPhoto,
      builder: (context, photo, _) {
        if (photo == null) return const SizedBox.shrink();
        final fav = st.isPhotoFav(photo.id);
        final dim = _hover || phone ? 1.0 : 0.55;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: InkWell(
                key: const ValueKey<String>('photo-credit'),
                onTap: () => openLink(context, kUnsplashRef),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    s.pick('Fotoğraf: ${photo.by} · Unsplash', 'Photo: ${photo.by} · Unsplash'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      color: Color.fromRGBO(243, 236, 224, _hover ? 0.85 : 0.42),
                      shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 2, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _BarButton(
              key: const ValueKey<String>('photo-fav'),
              icon: fav ? Icons.favorite : Icons.favorite_border,
              on: fav,
              opacity: fav ? 1 : dim,
              tooltip: fav ? s.pick('Favorilerden çıkar', 'Remove from favourites') : s.pick('Favori: daha sık gelsin', 'Favourite: show it more often'),
              onTap: () {
                final now = st.togglePhotoFav(photo.id);
                setState(() {});
                toast(context, now ? s.pick('Favorilere eklendi; daha sık gelecek.', 'Added to favourites; it will show more often.') : s.pick('Favorilerden çıkarıldı.', 'Removed from favourites.'));
              },
            ),
            const SizedBox(width: 6),
            _BarButton(
              key: const ValueKey<String>('photo-hide'),
              icon: Icons.visibility_off_outlined,
              label: phone ? null : s.pick('Gösterme', 'Hide'),
              opacity: dim,
              tooltip: s.pick('Bu fotoğrafı bir daha gösterme', "Don't show this photo again"),
              onTap: () {
                final id = photo.id;
                st.hidePhoto(id);
                toast(context, s.pick('Bu fotoğraf bir daha gösterilmeyecek.', 'This photo will not be shown again.'), undo: () => st.unhidePhoto(id));
              },
            ),
          ]),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.label, this.on = false, this.opacity = 1});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final String? label;
  final bool on;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFEF8F9F);
    final fg = on ? pink : const Color(0x8CF3ECE0);
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: opacity,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: const Color(0x590A0908),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? const Color(0x80EF8F9F) : const Color(0x24FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: fg),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(label!, style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, color: fg)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
