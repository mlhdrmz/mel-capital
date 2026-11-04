import '../core/sync/api.dart';
import 'sync_stub.dart' if (dart.library.io) 'sync_io.dart' as platform;

/// Bu platformun eşitleme arabirimi (web önizlemesinde null).
SyncApi? createSyncApi() => platform.createPlatformSyncApi();
