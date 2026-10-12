import 'dart:io';

import 'package:prisma_storage/prisma_storage.dart';
import 'package:test/test.dart';

class _FixedProbe implements MediaProbe {
  _FixedProbe(this.result);
  final MediaProbeResult result;

  @override
  Future<MediaProbeResult> probe({
    required String filePath,
    required String displayName,
  }) async => result;
}

class _FailingRepository implements MediaMetadataRepository {
  @override
  Future<void> insertAsset(MediaAsset asset) async {
    throw StateError('injected metadata failure');
  }

  @override
  Future<MediaAsset?> getAsset(String assetId) async => null;

  @override
  Future<List<MediaAsset>> listAssets() async => const [];

  @override
  Future<void> deleteAsset(String assetId) async {}
}

Future<File> _sourceFile(Directory root, String name, List<int> bytes) async {
  final file = File('${root.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  late Directory temp;
  late ManagedStorageLayout layout;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('prisma-storage-test-');
    layout = ManagedStorageLayout('${temp.path}/managed');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('successful image import commits bytes and metadata atomically', () async {
    final repository = InMemoryMediaMetadataRepository();
    final source = await _sourceFile(temp, 'moon.JPG', [1, 2, 3, 4, 5]);
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/jpeg',
        width: 640,
        height: 480,
      )),
      assetIdFactory: () => 'asset-image-1',
      clockMs: () => 1234,
    );

    final asset = await importer.import(FileAssetImportSource(
      source.path,
      originalReference: 'content://picker/moon',
    ));

    expect(asset.assetId, 'asset-image-1');
    expect(asset.type, MediaAssetType.image);
    expect(asset.displayName, 'moon.JPG');
    expect(asset.managedLocation, 'library/media/asset-image-1.jpg');
    expect(asset.contentHash.algorithm, 'SHA-256');
    expect(asset.contentHash.value, hasLength(64));
    expect(asset.byteSize, 5);
    expect(asset.width, 640);
    expect(asset.height, 480);
    expect(asset.originalReference, 'content://picker/moon');
    expect(asset.importedAtMs, 1234);

    final managed = File(layout.resolveManagedLocation(asset.managedLocation));
    expect(await managed.readAsBytes(), [1, 2, 3, 4, 5]);
    expect((await repository.getAsset(asset.assetId))?.assetId, asset.assetId);
    expect(await Directory(layout.importStagingDir).list().toList(), isEmpty);
  });

  test('successful video import preserves duration audio and frame rate', () async {
    final repository = InMemoryMediaMetadataRepository();
    final source = await _sourceFile(temp, 'loop.mp4', [9, 8, 7, 6]);
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.video,
        mimeType: 'video/mp4',
        width: 1920,
        height: 1080,
        durationMs: 4200,
        hasAudio: true,
        frameRate: 29.97,
      )),
      assetIdFactory: () => 'asset-video-1',
    );

    final asset = await importer.import(FileAssetImportSource(source.path));
    expect(asset.type, MediaAssetType.video);
    expect(asset.durationMs, 4200);
    expect(asset.hasAudio, isTrue);
    expect(asset.frameRate, 29.97);
  });

  test('platform materializer writes directly into importer-owned staging', () async {
    final repository = InMemoryMediaMetadataRepository();
    final platformFile = await _sourceFile(temp, 'picked.png', [8, 6, 7, 5, 3, 0, 9]);
    String? stagingPathSeenByAdapter;

    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/png',
        width: 320,
        height: 240,
      )),
      assetIdFactory: () => 'content-uri-asset',
    );

    final asset = await importer.import(CallbackAssetImportSource(
      displayName: 'picked.png',
      originalReference: 'content://documents/picked',
      materializer: (targetPath) async {
        stagingPathSeenByAdapter = targetPath;
        await platformFile.copy(targetPath);
      },
    ));

    expect(stagingPathSeenByAdapter, endsWith('content-uri-asset.part'));
    expect(asset.assetId, 'content-uri-asset');
    expect(asset.originalReference, 'content://documents/picked');
    expect(asset.byteSize, 7);
    expect(await repository.getAsset(asset.assetId), isNotNull);
    expect(await Directory(layout.importStagingDir).list().toList(), isEmpty);
  });

  test('platform materializer that produces no file fails closed', () async {
    final repository = InMemoryMediaMetadataRepository();
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      )),
      assetIdFactory: () => 'missing-platform-bytes',
    );

    await expectLater(
      importer.import(CallbackAssetImportSource(
        displayName: 'missing.png',
        originalReference: 'content://documents/missing',
        materializer: (_) async {},
      )),
      throwsA(
        isA<MediaImportException>().having(
          (e) => e.code,
          'code',
          'SOURCE_MATERIALIZATION_FAILED',
        ),
      ),
    );

    expect(await repository.listAssets(), isEmpty);
    expect(await Directory(layout.importStagingDir).list().toList(), isEmpty);
    expect(await Directory(layout.mediaDir).list().toList(), isEmpty);
  });

  test('invalid media never becomes a library asset', () async {
    final repository = InMemoryMediaMetadataRepository();
    final source = await _sourceFile(temp, 'broken.jpg', [1, 2, 3]);
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/jpeg',
        width: 0,
        height: 0,
      )),
      assetIdFactory: () => 'invalid-image',
    );

    await expectLater(
      importer.import(FileAssetImportSource(source.path)),
      throwsA(
        isA<MediaImportException>()
            .having((e) => e.code, 'code', 'INVALID_IMAGE'),
      ),
    );

    expect(await repository.listAssets(), isEmpty);
    expect(await Directory(layout.importStagingDir).list().toList(), isEmpty);
    expect(await Directory(layout.mediaDir).list().toList(), isEmpty);
  });

  test('metadata failure rolls managed bytes back', () async {
    final source = await _sourceFile(temp, 'rollback.png', [5, 4, 3, 2, 1]);
    final importer = MediaImporter(
      layout: layout,
      repository: _FailingRepository(),
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/png',
        width: 32,
        height: 32,
      )),
      assetIdFactory: () => 'rollback-asset',
    );

    await expectLater(
      importer.import(FileAssetImportSource(source.path)),
      throwsA(
        isA<MediaImportException>()
            .having((e) => e.code, 'code', 'METADATA_COMMIT_FAILED'),
      ),
    );

    expect(await Directory(layout.importStagingDir).list().toList(), isEmpty);
    expect(await Directory(layout.mediaDir).list().toList(), isEmpty);
  });

  test('same content may be imported twice but keeps identical integrity hash',
      () async {
    final repository = InMemoryMediaMetadataRepository();
    final source = await _sourceFile(temp, 'same.jpg', [4, 4, 4, 4]);
    final ids = ['asset-a', 'asset-b'].iterator;
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/jpeg',
        width: 10,
        height: 10,
      )),
      assetIdFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );

    final first = await importer.import(FileAssetImportSource(source.path));
    final second = await importer.import(FileAssetImportSource(source.path));

    expect(first.assetId, isNot(second.assetId));
    expect(first.contentHash.value, second.contentHash.value);
    expect(await repository.listAssets(), hasLength(2));
  });

  test('startup recovery removes staging and reports orphan/missing managed files',
      () async {
    final repository = InMemoryMediaMetadataRepository();
    final source = await _sourceFile(temp, 'tracked.jpg', [7, 7, 7]);
    final importer = MediaImporter(
      layout: layout,
      repository: repository,
      probe: _FixedProbe(const MediaProbeResult(
        type: MediaAssetType.image,
        mimeType: 'image/jpeg',
        width: 20,
        height: 20,
      )),
      assetIdFactory: () => 'tracked-asset',
    );

    final tracked = await importer.import(FileAssetImportSource(source.path));
    await File(layout.resolveManagedLocation(tracked.managedLocation)).delete();
    await File('${layout.importStagingDir}/interrupted.part')
        .writeAsBytes([1, 2]);
    await File('${layout.mediaDir}/orphan.jpg').writeAsBytes([3, 4]);

    final report = await importer.recoverInterruptedImports();

    expect(report.removedStagingFiles, contains('interrupted.part'));
    expect(report.orphanManagedFiles, contains('orphan.jpg'));
    expect(report.missingManagedAssets, contains('tracked-asset'));
    expect(await File('${layout.importStagingDir}/interrupted.part').exists(), isFalse);
    // Recovery reports orphan durable content; it does not destroy it silently.
    expect(await File('${layout.mediaDir}/orphan.jpg').exists(), isTrue);
  });

  test('managed-location resolver rejects absolute paths and traversal', () {
    expect(() => layout.resolveManagedLocation('/tmp/escape'), throwsArgumentError);
    expect(() => layout.resolveManagedLocation('../escape'), throwsArgumentError);
    expect(
      layout.resolveManagedLocation('library/media/ok.jpg'),
      contains('library/media/ok.jpg'),
    );
  });
}
