# PRISMA-PI App — Managed Storage Runtime

**Status:** Partial implementation / CI validation pending  
**Date:** 2026-10-12

## Purpose

Turn the Mobile Storage 2.0 design into testable non-UI runtime behavior before Android file-picker/media UI work begins.

## Implemented package

```text
packages/prisma_storage/
├── ManagedStorageLayout
├── MediaAsset / ContentHash / MediaProbeResult
├── AssetImportSource
├── FileAssetImportSource
├── MediaProbe interface
├── MediaMetadataRepository interface
├── InMemoryMediaMetadataRepository
├── MediaImporter
└── recovery/integrity tests
```

## Managed layout

The runtime materializes the logical structure:

```text
app-data/
├── library/
│   ├── media/
│   ├── recordings/
│   ├── projects/
│   └── skins/
├── staging/
│   ├── imports/
│   └── transfers/
├── cache/
│   ├── thumbnails/
│   ├── decoded/
│   └── remote-preview/
└── logs/
```

`MediaAsset.managedLocation` is always relative to this root. The resolver rejects absolute paths and parent traversal so durable product data never depends on or escapes through arbitrary platform filesystem paths.

## Import transaction implemented

```text
ImportSource stream
  ↓
staging/<asset-id>.part
  ↓
reject empty bytes
  ↓
SHA-256 over staged bytes
  ↓
MediaProbe
  ↓
validate IMAGE / VIDEO metadata
  ↓
atomic same-root rename into library/media
  ↓
metadata repository insert
  ↓
READY MediaAsset
```

If validation/probing fails, no managed media file or metadata row is published.

If metadata commit fails after file rename, the managed file is rolled back.

This provides application-level atomicity for the normal import path. A process/device crash between filesystem rename and metadata commit may still leave an orphan file; startup recovery detects that condition.

## Initial media policy

Committed import types currently supported by the contract:

```text
IMAGE
VIDEO
```

`AUDIO_RESERVED` exists in the model but standalone audio import fails explicitly in this phase. Video metadata already preserves `has_audio` so adding audio-reactive processing later does not require redefining the asset model.

Actual media decoding/probing is intentionally an injected `MediaProbe`. Android Media3/MediaMetadataRetriever or another native implementation can satisfy the same boundary later.

## Integrity vs deduplication

Every import receives SHA-256 metadata.

Hash equality does **not** currently force deduplication. Two explicit user imports of identical bytes may create two logical assets with the same content hash. This is deliberate: integrity identity and product deduplication policy remain separate concerns.

A future deduplication feature may use the hash but must define reference/deletion semantics before automatically coalescing assets.

## Recovery behavior

`recoverInterruptedImports()` currently:

1. removes leftover import staging files;
2. compares metadata rows against managed media bytes;
3. reports metadata assets whose managed bytes are missing;
4. reports managed media files that have no metadata record;
5. does **not** silently delete orphan durable media.

The recovery report lets a later repair policy quarantine, reconstruct or ask the user before destroying durable content.

## Storage security boundary

This package never stores:

- Google/Apple credentials;
- PRISMA cloud access/refresh tokens;
- appliance pairing secrets;
- private keys;
- appliance session tokens.

Those belong to secure credential storage (`prisma_security` + platform Keystore/Keychain adapter).

## Tests implemented

- successful image import;
- successful video import with duration/audio/frame-rate metadata;
- invalid image rejection;
- metadata-commit rollback;
- identical-content hashing without forced deduplication;
- interrupted-staging cleanup;
- orphan managed-file reporting;
- missing managed-asset reporting;
- managed-path traversal rejection.

## Still pending

Before this subsystem can become the production storage baseline:

1. SQLite implementation of `MediaMetadataRepository`;
2. ordered schema migrations;
3. Android content-URI streaming adapter;
4. native image/video `MediaProbe` implementation;
5. real JPEG/PNG/video decode validation;
6. project repository/save/load/migration;
7. reference-aware asset deletion;
8. recording finalization and quarantine;
9. remote-asset transfer transactions;
10. disk-full and I/O fault injection;
11. Android process-kill/restart recovery test;
12. physical-device validation.
