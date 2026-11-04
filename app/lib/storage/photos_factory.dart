import 'photos.dart';
import 'photos_stub.dart' if (dart.library.io) 'photos_io.dart' as platform;

/// Bu platformun fotoğraf yeri. Web önizlemesinde yalnızca [network] istenirse (Unsplash adresleri).
PhotoStore? createPhotoStore({bool network = false}) => platform.createPlatformPhotoStore(network: network);
