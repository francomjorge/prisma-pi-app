import 'dart:io';

import 'package:path/path.dart' as p;

class ManagedStorageLayout {
  ManagedStorageLayout(this.rootPath);

  final String rootPath;

  String get mediaDir => p.join(rootPath, 'library', 'media');
  String get recordingsDir => p.join(rootPath, 'library', 'recordings');
  String get projectsDir => p.join(rootPath, 'library', 'projects');
  String get skinsDir => p.join(rootPath, 'library', 'skins');
  String get importStagingDir => p.join(rootPath, 'staging', 'imports');
  String get transferStagingDir => p.join(rootPath, 'staging', 'transfers');
  String get thumbnailCacheDir => p.join(rootPath, 'cache', 'thumbnails');
  String get decodedCacheDir => p.join(rootPath, 'cache', 'decoded');
  String get remotePreviewCacheDir => p.join(rootPath, 'cache', 'remote-preview');
  String get logsDir => p.join(rootPath, 'logs');

  Future<void> initialize() async {
    for (final directory in [
      mediaDir,
      recordingsDir,
      projectsDir,
      skinsDir,
      importStagingDir,
      transferStagingDir,
      thumbnailCacheDir,
      decodedCacheDir,
      remotePreviewCacheDir,
      logsDir,
    ]) {
      await Directory(directory).create(recursive: true);
    }
  }

  /// Converts a relative managed location back into a runtime absolute path.
  /// Rejects traversal/absolute paths so serialized metadata cannot escape the
  /// managed root.
  String resolveManagedLocation(String managedLocation) {
    if (managedLocation.trim().isEmpty || p.isAbsolute(managedLocation)) {
      throw ArgumentError.value(managedLocation, 'managedLocation');
    }
    final normalized = p.normalize(managedLocation);
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(managedLocation, 'managedLocation');
    }
    final absolute = p.normalize(p.join(rootPath, normalized));
    final normalizedRoot = p.normalize(p.absolute(rootPath));
    final normalizedAbsolute = p.normalize(p.absolute(absolute));
    if (normalizedAbsolute != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedAbsolute)) {
      throw ArgumentError.value(managedLocation, 'managedLocation');
    }
    return absolute;
  }

  String mediaManagedLocation(String fileName) =>
      p.join('library', 'media', fileName);
}
