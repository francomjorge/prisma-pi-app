import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'layout.dart';
import 'model.dart';
import 'repository.dart';

/// Logical source metadata shared by all import adapters.
///
/// A source may expose its bytes as a Dart stream or may ask a platform adapter
/// to materialize those bytes directly into the importer-owned staging path.
/// The latter avoids copying large Android/iOS media payloads through a method
/// channel or Dart heap merely to reach managed storage.
abstract interface class AssetImportSource {
  String get displayName;
  String? get originalReference;
}

abstract interface class StreamingAssetImportSource implements AssetImportSource {
  Stream<List<int>> openRead();
}

abstract interface class MaterializingAssetImportSource implements AssetImportSource {
  Future<void> materializeTo(String targetPath);
}

class FileAssetImportSource
    implements StreamingAssetImportSource, MaterializingAssetImportSource {
  FileAssetImportSource(
    this.path, {
    String? displayName,
    this.originalReference,
  }) : displayName = displayName ?? p.basename(path);

  final String path;

  @override
  final String displayName;

  @override
  final String? originalReference;

  @override
  Stream<List<int>> openRead() => File(path).openRead();

  @override
  Future<void> materializeTo(String targetPath) async {
    await File(targetPath).parent.create(recursive: true);
    await File(path).copy(targetPath);
  }
}

typedef AssetMaterializer = Future<void> Function(String targetPath);

/// Adapter-friendly source for platform-owned content such as Android
/// `content://` URIs. The storage runtime still owns the staging path and all
/// validation/commit semantics; the callback owns only byte materialization.
class CallbackAssetImportSource implements MaterializingAssetImportSource {
  const CallbackAssetImportSource({
    required this.displayName,
    required this.materializer,
    this.originalReference,
  });

  @override
  final String displayName;

  @override
  final String? originalReference;

  final AssetMaterializer materializer;

  @override
  Future<void> materializeTo(String targetPath) => materializer(targetPath);
}

abstract interface class MediaProbe {
  Future<MediaProbeResult> probe({
    required String filePath,
    required String displayName,
  });
}

class MediaImportException implements Exception {
  const MediaImportException(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MediaImportException($code): $message';
}

typedef AssetIdFactory = String Function();
typedef ClockMs = int Function();

class MediaImporter {
  MediaImporter({
    required this.layout,
    required this.repository,
    required this.probe,
    AssetIdFactory? assetIdFactory,
    ClockMs? clockMs,
  })  : assetIdFactory = assetIdFactory ?? const Uuid().v4,
        clockMs = clockMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ManagedStorageLayout layout;
  final MediaMetadataRepository repository;
  final MediaProbe probe;
  final AssetIdFactory assetIdFactory;
  final ClockMs clockMs;

  Future<MediaAsset> import(AssetImportSource source) async {
    await layout.initialize();

    final assetId = assetIdFactory();
    if (assetId.trim().isEmpty) {
      throw const MediaImportException('INVALID_ASSET_ID', 'Asset ID is empty');
    }

    final stagingPath = p.join(layout.importStagingDir, '$assetId.part');
    final stagingFile = File(stagingPath);
    String? committedPath;
    var metadataCommitted = false;

    try {
      await _copyToStaging(source, stagingFile);
      final byteSize = await stagingFile.length();
      if (byteSize <= 0) {
        throw const MediaImportException(
          'EMPTY_MEDIA',
          'Imported media is empty',
        );
      }

      final digest = await sha256.bind(stagingFile.openRead()).first;
      final probeResult = await probe.probe(
        filePath: stagingPath,
        displayName: source.displayName,
      );
      _validateProbe(probeResult);

      final extension = _safeExtension(source.displayName);
      final managedFileName = '$assetId$extension';
      final managedLocation = layout.mediaManagedLocation(managedFileName);
      final destinationPath = layout.resolveManagedLocation(managedLocation);
      final destination = File(destinationPath);
      if (await destination.exists()) {
        throw MediaImportException(
          'ASSET_COLLISION',
          'Managed destination already exists for asset $assetId',
        );
      }

      await stagingFile.rename(destinationPath);
      committedPath = destinationPath;

      final now = clockMs();
      final asset = MediaAsset(
        assetId: assetId,
        type: probeResult.type,
        displayName: source.displayName,
        managedLocation: managedLocation,
        originalReference: source.originalReference,
        contentHash: ContentHash(
          algorithm: 'SHA-256',
          value: digest.toString(),
        ),
        byteSize: byteSize,
        mimeType: probeResult.mimeType,
        width: probeResult.width,
        height: probeResult.height,
        durationMs: probeResult.durationMs,
        hasAudio: probeResult.hasAudio,
        frameRate: probeResult.frameRate,
        importedAtMs: now,
        modifiedAtMs: now,
        validationState: AssetValidationState.ready,
        metadata: Map<String, dynamic>.unmodifiable(probeResult.metadata),
      );

      try {
        await repository.insertAsset(asset);
        metadataCommitted = true;
      } catch (error) {
        throw MediaImportException(
          'METADATA_COMMIT_FAILED',
          'Media bytes were committed but metadata commit failed',
          cause: error,
        );
      }

      return asset;
    } on MediaImportException {
      rethrow;
    } catch (error) {
      throw MediaImportException(
        'IMPORT_FAILED',
        'Media import failed',
        cause: error,
      );
    } finally {
      await _deleteIfExists(stagingFile);
      if (committedPath != null && !metadataCommitted) {
        await _deleteIfExists(File(committedPath));
      }
    }
  }

  Future<StorageRecoveryReport> recoverInterruptedImports() async {
    await layout.initialize();

    final removedStaging = <String>[];
    await for (final entity in Directory(layout.importStagingDir).list()) {
      if (entity is File) {
        removedStaging.add(p.basename(entity.path));
        await entity.delete();
      }
    }

    final assets = await repository.listAssets();
    final expectedByPath = <String, MediaAsset>{};
    final missingAssets = <String>[];
    for (final asset in assets) {
      final absolute = layout.resolveManagedLocation(asset.managedLocation);
      expectedByPath[p.normalize(p.absolute(absolute))] = asset;
      if (!await File(absolute).exists()) {
        missingAssets.add(asset.assetId);
      }
    }

    final orphanManaged = <String>[];
    await for (final entity in Directory(layout.mediaDir).list()) {
      if (entity is! File) continue;
      final absolute = p.normalize(p.absolute(entity.path));
      if (!expectedByPath.containsKey(absolute)) {
        orphanManaged.add(p.basename(entity.path));
      }
    }

    return StorageRecoveryReport(
      removedStagingFiles: List.unmodifiable(removedStaging),
      orphanManagedFiles: List.unmodifiable(orphanManaged),
      missingManagedAssets: List.unmodifiable(missingAssets),
    );
  }

  Future<void> _copyToStaging(
    AssetImportSource source,
    File stagingFile,
  ) async {
    await stagingFile.parent.create(recursive: true);
    await _deleteIfExists(stagingFile);

    if (source is MaterializingAssetImportSource) {
      await source.materializeTo(stagingFile.path);
      if (!await stagingFile.exists()) {
        throw const MediaImportException(
          'SOURCE_MATERIALIZATION_FAILED',
          'Import source did not materialize a staging file',
        );
      }
      return;
    }

    if (source is StreamingAssetImportSource) {
      final sink = stagingFile.openWrite(mode: FileMode.writeOnly);
      try {
        await sink.addStream(source.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
      return;
    }

    throw const MediaImportException(
      'UNSUPPORTED_IMPORT_SOURCE',
      'Import source exposes neither a stream nor a platform materializer',
    );
  }

  void _validateProbe(MediaProbeResult result) {
    if (result.mimeType.trim().isEmpty) {
      throw const MediaImportException(
        'INVALID_MEDIA_METADATA',
        'Media probe returned an empty MIME type',
      );
    }
    switch (result.type) {
      case MediaAssetType.image:
        if ((result.width ?? 0) <= 0 || (result.height ?? 0) <= 0) {
          throw const MediaImportException(
            'INVALID_IMAGE',
            'Image dimensions are invalid',
          );
        }
        break;
      case MediaAssetType.video:
        if ((result.width ?? 0) <= 0 ||
            (result.height ?? 0) <= 0 ||
            (result.durationMs ?? 0) <= 0) {
          throw const MediaImportException(
            'INVALID_VIDEO',
            'Video dimensions or duration are invalid',
          );
        }
        break;
      case MediaAssetType.audioReserved:
        throw const MediaImportException(
          'AUDIO_NOT_ENABLED',
          'Standalone audio assets are reserved but not enabled in this phase',
        );
    }
  }

  String _safeExtension(String displayName) {
    final extension = p.extension(displayName).toLowerCase();
    if (extension.isEmpty) return '';
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) return '';
    return extension;
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Recovery scan will surface any leftover file on next startup.
    }
  }
}
