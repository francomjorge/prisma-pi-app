import 'model.dart';

abstract interface class MediaMetadataRepository {
  Future<void> insertAsset(MediaAsset asset);
  Future<MediaAsset?> getAsset(String assetId);
  Future<List<MediaAsset>> listAssets();
  Future<void> deleteAsset(String assetId);
}

/// Deterministic repository used by storage/runtime tests. Production metadata
/// persistence will implement the same interface using the selected SQLite
/// adapter and migrations.
class InMemoryMediaMetadataRepository implements MediaMetadataRepository {
  final Map<String, MediaAsset> _assets = {};

  @override
  Future<void> insertAsset(MediaAsset asset) async {
    if (_assets.containsKey(asset.assetId)) {
      throw StateError('asset_id already exists: ${asset.assetId}');
    }
    _assets[asset.assetId] = asset;
  }

  @override
  Future<MediaAsset?> getAsset(String assetId) async => _assets[assetId];

  @override
  Future<List<MediaAsset>> listAssets() async =>
      List<MediaAsset>.unmodifiable(_assets.values);

  @override
  Future<void> deleteAsset(String assetId) async {
    _assets.remove(assetId);
  }
}
