import 'dart:io';

import 'package:prisma_storage/prisma_storage.dart';
import 'package:test/test.dart';

void main() {
  MediaAsset sampleAsset({
    String id = 'asset-1',
    String location = 'library/media/asset-1.jpg',
  }) {
    return MediaAsset(
      assetId: id,
      type: MediaAssetType.image,
      displayName: 'moon.jpg',
      managedLocation: location,
      originalReference: 'content://media/external/images/42',
      contentHash: const ContentHash(
        algorithm: 'SHA-256',
        value: 'abc123',
      ),
      byteSize: 1234,
      mimeType: 'image/jpeg',
      width: 640,
      height: 480,
      hasAudio: false,
      importedAtMs: 100,
      modifiedAtMs: 101,
      validationState: AssetValidationState.ready,
      metadata: const {
        'orientation': 1,
        'source': 'test',
      },
    );
  }

  test('schema migration creates version 1 and persists assets across reopen', () async {
    final temp = await Directory.systemTemp.createTemp('prisma-sqlite-test-');
    final databasePath = '${temp.path}/metadata.sqlite3';

    try {
      var repository = SqliteMediaMetadataRepository.open(databasePath);
      expect(repository.schemaVersion, 1);

      await repository.insertAsset(sampleAsset());
      repository.close();

      repository = SqliteMediaMetadataRepository.open(databasePath);
      expect(repository.schemaVersion, 1);

      final restored = await repository.getAsset('asset-1');
      expect(restored, isNotNull);
      expect(restored!.displayName, 'moon.jpg');
      expect(restored.managedLocation, 'library/media/asset-1.jpg');
      expect(restored.originalReference, 'content://media/external/images/42');
      expect(restored.contentHash.algorithm, 'SHA-256');
      expect(restored.contentHash.value, 'abc123');
      expect(restored.byteSize, 1234);
      expect(restored.mimeType, 'image/jpeg');
      expect(restored.width, 640);
      expect(restored.height, 480);
      expect(restored.hasAudio, isFalse);
      expect(restored.metadata['source'], 'test');

      repository.close();
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('duplicate asset IDs fail and delete removes metadata', () async {
    final repository = SqliteMediaMetadataRepository.inMemory();
    try {
      final asset = sampleAsset();
      await repository.insertAsset(asset);

      await expectLater(
        repository.insertAsset(asset),
        throwsA(isA<StateError>()),
      );

      expect(await repository.listAssets(), hasLength(1));
      await repository.deleteAsset(asset.assetId);
      expect(await repository.getAsset(asset.assetId), isNull);
    } finally {
      repository.close();
    }
  });

  test('managed locations remain unique', () async {
    final repository = SqliteMediaMetadataRepository.inMemory();
    try {
      await repository.insertAsset(sampleAsset());
      await expectLater(
        repository.insertAsset(
          sampleAsset(
            id: 'asset-2',
            location: 'library/media/asset-1.jpg',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      repository.close();
    }
  });
}
