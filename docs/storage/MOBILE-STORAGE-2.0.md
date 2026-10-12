# PRISMA-PI App — Mobile Storage 2.0

**Status:** Draft / DESIGNED

## 1. Purpose

Define durable storage before UI implementation. Goals: predictable media handling, crash-safe imports, schema migration, project portability and platform-independent logical IDs.

## 2. Storage principles

1. Product state never depends on a volatile Android/iOS external path.
2. Imported assets receive immutable logical IDs.
3. File bytes and metadata commit atomically from the application's point of view.
4. Partial or invalid files are never exposed as valid sources.
5. Database and project schemas are explicitly versioned.
6. Cache is disposable; library assets and projects are durable.
7. Credentials never live in media/project databases.
8. Deleting a project does not implicitly delete shared media assets.
9. Deleting media requires reference checks.
10. Platform-specific URIs remain adapter details.

## 3. Logical storage model

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

Actual Android/iOS paths are selected by the platform storage adapter.

## 4. Metadata database

SQLite is the initial persistence target for structured local metadata.

Minimum logical entities:

```text
assets
projects
project_asset_refs
recordings
skins
paired_devices_public_metadata
app_settings
migrations
```

Sensitive pairing material is stored only through the secure credential adapter.

## 5. MediaAsset

```text
MediaAsset
├── asset_id: UUID
├── type: IMAGE | VIDEO | AUDIO_RESERVED
├── display_name
├── managed_location
├── original_reference?
├── content_hash
├── byte_size
├── mime_type
├── width?
├── height?
├── duration_ms?
├── has_audio
├── frame_rate?
├── imported_at
├── modified_at
├── validation_state
└── metadata_json
```

Portable projects never serialize a device-specific absolute managed path.

## 6. Asset import transaction

```text
REQUEST IMPORT
      ↓
CREATE STAGING ID
      ↓
COPY/STREAM TO STAGING
      ↓
VERIFY READABILITY
      ↓
HASH CONTENT
      ↓
PROBE MEDIA METADATA
      ↓
VALIDATE TYPE/LIMITS
      ↓
MOVE/COMMIT MANAGED FILE
      ↓
COMMIT METADATA ROW
      ↓
PUBLISH LIBRARY_CHANGED
```

Failure before publish cleans staging data and creates no valid asset record.

Startup recovery reconciles interrupted transactions and orphaned managed/staging files.

## 7. Initial media requirements

Infrastructure baseline requires:

- still images via reliable platform-compatible JPEG/PNG decoding;
- at least one production video container/codec combination reliable on target Android devices;
- looping-video playback metadata;
- embedded-audio metadata even when visual processing initially ignores audio.

Exact codecs are platform capabilities, not universal guarantees.

## 8. Integrity hashes

A content hash records both algorithm and value.

```text
ContentHash
├── algorithm
└── value
```

Integrity verification and deduplication policy are separate concerns.

## 9. Projects

```text
PrismaProject
├── schema_version
├── project_id
├── name
├── created_at
├── modified_at
├── selected_source_asset_id
├── processing_graph
├── module_state
├── output_routes
├── runtime_preferences
└── required_assets[]
```

JSON is acceptable as the initial portable reference format if deterministic and migratable.

## 10. Recordings

Recordings are promoted into the media library only after finalization succeeds.

```text
PENDING → RECORDING → FINALIZING → READY
                         └──────→ FAILED
```

Incomplete recordings are quarantined unless the chosen container/codec supports safe recovery.

## 11. Remote appliance assets

Remote assets are references until explicitly transferred.

```text
RemoteAssetRef
├── device_id
├── remote_asset_id
├── metadata
├── availability
└── revision/hash?
```

Explicit transfer creates a local `MediaAsset` after integrity verification.

## 12. Cache policy

- cache may be deleted at any time;
- cache is never the sole copy of user content;
- cache keys include revision/hash where needed;
- application correctness never depends on cache survival.

## 13. Skin packages

Skins are data, not executable plugins.

Initial package:

```text
skin.json
assets/
  textures/
  images/
```

Arbitrary executable code is prohibited in skin packages.

## 14. Migration

Every durable schema uses ordered monotonic migrations.

```text
open metadata store
→ inspect schema version
→ create recovery checkpoint where appropriate
→ apply ordered migrations
→ verify invariants
→ expose library to runtime
```

Migration failure stops writes and produces a recoverable diagnostic state.

## 15. Future backup/export boundary

Portable bundles may contain project document, referenced local media, skin references/packages, hashes and schema versions.

Pairing credentials and secrets are never exported.

## 16. Tests required before UI

- successful image import;
- successful video import;
- corrupt/unsupported rejection;
- interrupted import cleanup;
- duplicate-content behavior;
- project save/reload;
- project migration;
- missing asset detection;
- recording finalize/failure;
- cache deletion with no data loss;
- restart after partial transaction;
- remote asset transfer integrity failure.
