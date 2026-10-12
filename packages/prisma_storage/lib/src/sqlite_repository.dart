import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'model.dart';
import 'repository.dart';

/// Durable SQLite implementation of [MediaMetadataRepository].
///
/// The database owns only structured metadata. Media bytes remain in managed
/// application storage and are referenced by logical relative locations.
class SqliteMediaMetadataRepository implements MediaMetadataRepository {
  SqliteMediaMetadataRepository._(this._db);

  static const int currentSchemaVersion = 1;

  final Database _db;
  bool _closed = false;

  static SqliteMediaMetadataRepository open(String path) {
    final db = sqlite3.open(path);
    final repository = SqliteMediaMetadataRepository._(db);
    repository._configure();
    repository._migrate();
    return repository;
  }

  static SqliteMediaMetadataRepository inMemory() {
    final db = sqlite3.openInMemory();
    final repository = SqliteMediaMetadataRepository._(db);
    repository._configure();
    repository._migrate();
    return repository;
  }

  int get schemaVersion {
    _ensureOpen();
    final rows = _db.select(
      'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1',
    );
    if (rows.isEmpty) return 0;
    return rows.first['version'] as int;
  }

  @override
  Future<void> insertAsset(MediaAsset asset) async {
    _ensureOpen();
    final statement = _db.prepare('''
      INSERT INTO assets (
        asset_id,
        type,
        display_name,
        managed_location,
        original_reference,
        content_hash_algorithm,
        content_hash_value,
        byte_size,
        mime_type,
        width,
        height,
        duration_ms,
        has_audio,
        frame_rate,
        imported_at_ms,
        modified_at_ms,
        validation_state,
        metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      statement.execute([
        asset.assetId,
        _encodeType(asset.type),
        asset.displayName,
        asset.managedLocation,
        asset.originalReference,
        asset.contentHash.algorithm,
        asset.contentHash.value,
        asset.byteSize,
        asset.mimeType,
        asset.width,
        asset.height,
        asset.durationMs,
        asset.hasAudio ? 1 : 0,
        asset.frameRate,
        asset.importedAtMs,
        asset.modifiedAtMs,
        _encodeValidation(asset.validationState),
        jsonEncode(asset.metadata),
      ]);
    } on SqliteException catch (error) {
      throw StateError(
        'Failed to insert asset ${asset.assetId}: ${error.message}',
      );
    } finally {
      statement.dispose();
    }
  }

  @override
  Future<MediaAsset?> getAsset(String assetId) async {
    _ensureOpen();
    final rows = _db.select(
      'SELECT * FROM assets WHERE asset_id = ?',
      [assetId],
    );
    if (rows.isEmpty) return null;
    return _decodeAsset(rows.first);
  }

  @override
  Future<List<MediaAsset>> listAssets() async {
    _ensureOpen();
    final rows = _db.select(
      'SELECT * FROM assets ORDER BY imported_at_ms ASC, asset_id ASC',
    );
    return List<MediaAsset>.unmodifiable(rows.map(_decodeAsset));
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    _ensureOpen();
    _db.execute('DELETE FROM assets WHERE asset_id = ?', [assetId]);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.dispose();
  }

  void _configure() {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = FULL');
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at_ms INTEGER NOT NULL
      )
    ''');

    final installed = schemaVersion;
    if (installed > currentSchemaVersion) {
      throw StateError(
        'Storage schema $installed is newer than supported '
        '$currentSchemaVersion',
      );
    }

    if (installed < 1) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('''
          CREATE TABLE assets (
            asset_id TEXT PRIMARY KEY NOT NULL,
            type TEXT NOT NULL,
            display_name TEXT NOT NULL,
            managed_location TEXT NOT NULL UNIQUE,
            original_reference TEXT,
            content_hash_algorithm TEXT NOT NULL,
            content_hash_value TEXT NOT NULL,
            byte_size INTEGER NOT NULL CHECK (byte_size >= 0),
            mime_type TEXT NOT NULL,
            width INTEGER,
            height INTEGER,
            duration_ms INTEGER,
            has_audio INTEGER NOT NULL CHECK (has_audio IN (0, 1)),
            frame_rate REAL,
            imported_at_ms INTEGER NOT NULL,
            modified_at_ms INTEGER NOT NULL,
            validation_state TEXT NOT NULL,
            metadata_json TEXT NOT NULL
          )
        ''');
        _db.execute('''
          CREATE INDEX assets_content_hash_idx
          ON assets(content_hash_algorithm, content_hash_value)
        ''');
        _db.execute('''
          INSERT INTO schema_migrations(version, applied_at_ms)
          VALUES (1, ?)
        ''', [DateTime.now().millisecondsSinceEpoch]);
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  MediaAsset _decodeAsset(Row row) {
    final metadataText = row['metadata_json'] as String;
    final decodedMetadata = jsonDecode(metadataText);
    if (decodedMetadata is! Map) {
      throw const FormatException('Asset metadata_json must decode to object');
    }

    return MediaAsset(
      assetId: row['asset_id'] as String,
      type: _decodeType(row['type'] as String),
      displayName: row['display_name'] as String,
      managedLocation: row['managed_location'] as String,
      originalReference: row['original_reference'] as String?,
      contentHash: ContentHash(
        algorithm: row['content_hash_algorithm'] as String,
        value: row['content_hash_value'] as String,
      ),
      byteSize: row['byte_size'] as int,
      mimeType: row['mime_type'] as String,
      width: row['width'] as int?,
      height: row['height'] as int?,
      durationMs: row['duration_ms'] as int?,
      hasAudio: (row['has_audio'] as int) == 1,
      frameRate: (row['frame_rate'] as num?)?.toDouble(),
      importedAtMs: row['imported_at_ms'] as int,
      modifiedAtMs: row['modified_at_ms'] as int,
      validationState: _decodeValidation(row['validation_state'] as String),
      metadata: Map<String, dynamic>.from(decodedMetadata),
    );
  }

  String _encodeType(MediaAssetType value) => switch (value) {
        MediaAssetType.image => 'IMAGE',
        MediaAssetType.video => 'VIDEO',
        MediaAssetType.audioReserved => 'AUDIO_RESERVED',
      };

  MediaAssetType _decodeType(String value) => switch (value) {
        'IMAGE' => MediaAssetType.image,
        'VIDEO' => MediaAssetType.video,
        'AUDIO_RESERVED' => MediaAssetType.audioReserved,
        _ => throw FormatException('Unknown media asset type: $value'),
      };

  String _encodeValidation(AssetValidationState value) => switch (value) {
        AssetValidationState.ready => 'READY',
      };

  AssetValidationState _decodeValidation(String value) => switch (value) {
        'READY' => AssetValidationState.ready,
        _ => throw FormatException('Unknown validation state: $value'),
      };

  void _ensureOpen() {
    if (_closed) throw StateError('SQLite metadata repository is closed');
  }
}
