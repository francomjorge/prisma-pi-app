import 'package:flutter/services.dart';
import 'package:prisma_storage/prisma_storage.dart';

/// M0-only orchestration proving the production boundary shape:
///
/// Android SAF URI -> platform materializer -> importer-owned staging -> native
/// media probe -> managed PRISMA file -> metadata repository.
///
/// The metadata repository remains in-memory in this disposable spike. Durable
/// SQLite is validated separately by `prisma_storage`; Android SQLite packaging
/// is intentionally not coupled to the stack decision until the physical M0
/// run is complete.
class AndroidMediaImportDiagnostic {
  AndroidMediaImportDiagnostic(this.channel);

  final MethodChannel channel;
  final InMemoryMediaMetadataRepository _repository =
      InMemoryMediaMetadataRepository();
  ManagedStorageLayout? _layout;

  Future<MediaAsset?> pickAndImport() async {
    final uri = await channel.invokeMethod<String>('pickMedia');
    if (uri == null || uri.isEmpty) return null;

    final info = await channel.invokeMapMethod<String, dynamic>(
      'inspectUri',
      {'uri': uri},
    );
    final paths = await channel.invokeMapMethod<String, dynamic>('appPaths');
    final filesDir = paths?['files_dir'] as String?;
    if (filesDir == null || filesDir.isEmpty) {
      throw StateError('Android media bridge returned no private files directory');
    }

    final displayName = _displayName(info, uri);
    final layout = _layout ??= ManagedStorageLayout('$filesDir/prisma-m0');
    final importer = MediaImporter(
      layout: layout,
      repository: _repository,
      probe: _AndroidChannelMediaProbe(channel),
    );

    return importer.import(CallbackAssetImportSource(
      displayName: displayName,
      originalReference: uri,
      materializer: (targetPath) async {
        final result = await channel.invokeMapMethod<String, dynamic>(
          'copyUriToFile',
          {
            'uri': uri,
            'target_path': targetPath,
          },
        );
        if (result?['exists'] != true) {
          throw StateError('Android materializer did not create staging bytes');
        }
      },
    ));
  }

  Future<List<MediaAsset>> listImportedAssets() => _repository.listAssets();

  String _displayName(Map<String, dynamic>? info, String uri) {
    final fromProvider = info?['display_name'];
    if (fromProvider is String && fromProvider.trim().isNotEmpty) {
      return fromProvider.trim();
    }

    final parsed = Uri.tryParse(uri);
    final fallback = parsed?.pathSegments.isNotEmpty == true
        ? parsed!.pathSegments.last
        : null;
    return fallback == null || fallback.trim().isEmpty
        ? 'picked-media'
        : fallback.trim();
  }
}

class _AndroidChannelMediaProbe implements MediaProbe {
  const _AndroidChannelMediaProbe(this.channel);

  final MethodChannel channel;

  @override
  Future<MediaProbeResult> probe({
    required String filePath,
    required String displayName,
  }) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'probeManagedFile',
      {'path': filePath},
    );
    if (result == null) {
      throw StateError('Android media probe returned no result');
    }

    final type = switch (result['type']) {
      'IMAGE' => MediaAssetType.image,
      'VIDEO' => MediaAssetType.video,
      final Object? unsupported =>
        throw StateError('Unsupported Android media type: $unsupported'),
    };

    return MediaProbeResult(
      type: type,
      mimeType: (result['mime_type'] as String?) ?? 'application/octet-stream',
      width: _asInt(result['width']),
      height: _asInt(result['height']),
      durationMs: _asInt(result['duration_ms']),
      hasAudio: result['has_audio'] == true,
      frameRate: _asDouble(result['frame_rate']),
      metadata: {
        'probe_backend': 'ANDROID_NATIVE_M0',
        'original_display_name': displayName,
      },
    );
  }

  int? _asInt(Object? value) => value is num ? value.toInt() : null;

  double? _asDouble(Object? value) => value is num ? value.toDouble() : null;
}
