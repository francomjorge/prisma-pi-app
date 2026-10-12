enum MediaAssetType { image, video, audioReserved }

enum AssetValidationState { ready }

class ContentHash {
  const ContentHash({required this.algorithm, required this.value});

  final String algorithm;
  final String value;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'value': value,
      };
}

class MediaProbeResult {
  const MediaProbeResult({
    required this.type,
    required this.mimeType,
    this.width,
    this.height,
    this.durationMs,
    this.hasAudio = false,
    this.frameRate,
    this.metadata = const {},
  });

  final MediaAssetType type;
  final String mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final bool hasAudio;
  final double? frameRate;
  final Map<String, dynamic> metadata;
}

class MediaAsset {
  const MediaAsset({
    required this.assetId,
    required this.type,
    required this.displayName,
    required this.managedLocation,
    required this.contentHash,
    required this.byteSize,
    required this.mimeType,
    required this.importedAtMs,
    required this.modifiedAtMs,
    required this.validationState,
    this.originalReference,
    this.width,
    this.height,
    this.durationMs,
    this.hasAudio = false,
    this.frameRate,
    this.metadata = const {},
  });

  final String assetId;
  final MediaAssetType type;
  final String displayName;

  /// Relative location inside the managed PRISMA storage root. Durable product
  /// state must not persist platform-specific absolute paths.
  final String managedLocation;
  final String? originalReference;
  final ContentHash contentHash;
  final int byteSize;
  final String mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final bool hasAudio;
  final double? frameRate;
  final int importedAtMs;
  final int modifiedAtMs;
  final AssetValidationState validationState;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'type': switch (type) {
          MediaAssetType.image => 'IMAGE',
          MediaAssetType.video => 'VIDEO',
          MediaAssetType.audioReserved => 'AUDIO_RESERVED',
        },
        'display_name': displayName,
        'managed_location': managedLocation,
        if (originalReference != null) 'original_reference': originalReference,
        'content_hash': contentHash.toJson(),
        'byte_size': byteSize,
        'mime_type': mimeType,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'duration_ms': durationMs,
        'has_audio': hasAudio,
        if (frameRate != null) 'frame_rate': frameRate,
        'imported_at_ms': importedAtMs,
        'modified_at_ms': modifiedAtMs,
        'validation_state': 'READY',
        'metadata': metadata,
      };
}

class StorageRecoveryReport {
  const StorageRecoveryReport({
    required this.removedStagingFiles,
    required this.orphanManagedFiles,
    required this.missingManagedAssets,
  });

  final List<String> removedStagingFiles;
  final List<String> orphanManagedFiles;
  final List<String> missingManagedAssets;

  bool get clean =>
      removedStagingFiles.isEmpty &&
      orphanManagedFiles.isEmpty &&
      missingManagedAssets.isEmpty;
}
