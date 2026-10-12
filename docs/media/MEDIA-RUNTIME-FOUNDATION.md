# PRISMA-PI App — Local Media Runtime Foundation

**Status:** DESIGNED + INITIAL CONTRACT IMPLEMENTED

## Purpose

Define the mobile local-media boundary before production UI or effect processing is built. The objective is to keep decoding/playback lifecycle, managed storage and future GPU processing separable so Android-first implementation does not make iOS a rewrite.

## Core rule

The application never treats a volatile user-selected path as durable media state.

```text
Android SAF / iOS picker
        ↓
Platform byte materializer
        ↓
Importer-owned staging file
        ↓
Native media probe
        ↓
Managed library asset + integrity hash + metadata
        ↓
Ephemeral runtime locator
        ↓
Local Media Runtime
        ↓
Processing Graph
        ↓
Preview / Recorder / Output Router
```

Portable projects store logical asset IDs only. Absolute paths and platform URI grants are runtime adapter details.

## Import boundary

`prisma_storage` supports two source styles:

- `StreamingAssetImportSource` for byte streams available directly to Dart/runtime code;
- `MaterializingAssetImportSource` for platform-owned sources such as Android `content://` URIs.

For platform materialization, the importer owns the staging destination and the platform adapter only writes bytes into that path. Validation, SHA-256 hashing, native probing, final file promotion and metadata commit remain controlled by the storage runtime.

This avoids moving large media payloads through Flutter method-channel messages.

## Android M0 path

The current Android diagnostic spike implements:

```text
ACTION_OPEN_DOCUMENT
  → content:// URI
  → ContentResolver metadata inspection
  → ContentResolver stream copied directly to importer staging
  → native image/video probe
  → PRISMA managed file
  → metadata repository
  → native decode probe
```

No product screen depends on this spike.

The diagnostic adapter currently uses an in-memory metadata repository after import. Durable SQLite is implemented and tested separately in `prisma_storage`; the exact Android packaging/runtime adapter for SQLite remains a separate validation point.

## Native probe and decode responsibilities

Android native code currently demonstrates:

- image metadata probing with `BitmapFactory.Options.inJustDecodeBounds`;
- video metadata probing with `MediaMetadataRetriever`;
- full still-image decode with `BitmapFactory.decodeFile`;
- diagnostic video-frame decode with `MediaMetadataRetriever.getFrameAtTime`;
- no full image/video frame payload is copied into Dart.

The frame-decode probe is **not** the final looping-video runtime. Continuous playback must use a sustained decode/render path appropriate for target devices and future GPU processing.

## Platform-neutral runtime contract

`packages/prisma_media_runtime` defines the lifecycle expected from native implementations.

Main concepts:

```text
LocalMediaSource
├── asset_id
├── runtime_locator      # ephemeral, never portable
├── kind                 # IMAGE | VIDEO
├── mime_type
├── width / height
├── duration_ms?
└── has_audio

MediaOpenOptions
├── loop
├── autoplay
├── start_position_ms
└── muted

MediaSessionSnapshot
├── session_id
├── source_asset_id
├── state
├── position_ms
├── duration_ms?
├── loop
├── muted
├── decode_backend?
└── fault_code?
```

Session lifecycle:

```text
OPENING
  ├──→ READY
  ├──→ PLAYING
  ├──→ FAILED
  └──→ CLOSED

READY ↔ PLAYING ↔ PAUSED
PLAYING/PAUSED → ENDED
ENDED → PLAYING           # replay / loop restart
ANY ACTIVE STATE → FAILED or CLOSED
FAILED → CLOSED
CLOSED is terminal
```

## Required Android production spike

Before the media stack ADR can be accepted, Android must prove on a physical device:

1. import JPEG and PNG through SAF;
2. import at least one supported production video container/codec combination;
3. persistent managed bytes survive app restart;
4. SQLite metadata survives app restart;
5. native image decode succeeds without Dart pixel copies;
6. native video playback can sustain looping without pathological CPU/memory growth;
7. playback can expose a render surface suitable for downstream GPU processing;
8. seek, pause, resume and loop transitions are deterministic;
9. app background/foreground lifecycle does not corrupt media state;
10. unsupported/corrupt media fails closed and does not become a valid source.

## Continuous video direction

The final Android video implementation is intentionally not frozen by the current frame probe. The production backend must be chosen after measurement of:

- decoder availability and hardware acceleration;
- surface/texture interop with the processing graph;
- copy count per frame;
- sustained FPS and latency;
- memory pressure;
- loop discontinuity behavior;
- audio-track handling even if audio processing is initially unused;
- external-display/output routing compatibility.

Candidate Android APIs may include Media3/MediaCodec and GPU surface APIs. Selection requires the M0 physical spike rather than assumption.

## iOS boundary

The same platform-neutral lifecycle must later map to an AVFoundation/Metal implementation without changing application/domain contracts.

## Explicit non-goals in this phase

- no production media browser UI;
- no effect rendering yet;
- no browser canvas reuse;
- no raw frame transport through Dart;
- no final recorder/output implementation;
- no final audio-processing implementation;
- no claim that a single video codec works on every Android device.

## Validation status

Current automated validation can prove contract correctness, storage semantics and Android compilation. It cannot prove physical decoder performance, hardware acceleration, loop quality or device lifecycle behavior. Those remain `HARDWARE_TESTED` gates.
