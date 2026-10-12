# ADR-004 — Media, Image, UI and Resource-Management Stack

**Status:** PROPOSED / implementation contracts started  
**Date:** 2026-10-12

## Context

PRISMA-PI is a visual-performance application, not a conventional CRUD/mobile app. Image/video handling, aspect-ratio correctness, resolution control, GPU interop, UI responsiveness and deterministic resource release are product-critical.

A library that is convenient for displaying thumbnails must not become the processing engine by accident. Likewise, a UI animation package must not own synthesizer state or media lifetime.

This ADR defines the selection strategy and boundaries. It does **not** freeze every dependency before physical-device measurement.

## Decision summary

Use a layered stack:

```text
Flutter presentation / PRISMA skin system
        ↓
platform-neutral media presentation policy
        ↓
LocalMediaRuntime contract
        ↓
Android native media adapter
        ↓
Media3 / platform decoders / Surface-GPU path
```

Image-display convenience libraries may be used at the presentation edge only. Full-resolution media processing remains native/GPU-oriented.

## 1. Flutter UI foundation

### Baseline

Use Flutter's own widget/rendering stack plus PRISMA semantic design tokens as the production UI foundation.

- Material 3 primitives may be used for accessibility, interaction semantics and platform-consistent controls.
- Visual identity comes from the PRISMA skin/token system, not from a third-party component suite.
- The first skin remains the vintage/analog photographic direction already defined by the product.
- No WebView wrapper.
- No UI package may become the owner of synthesizer or media state.

This keeps Android and future iOS behavior consistent while allowing the entire visual treatment to change without rewriting application logic.

### Optional UI animation helper

`flutter_animate` is a candidate for non-critical interface motion and micro-interactions. It must remain behind PRISMA animation helpers so it can be removed without changing feature code.

Do not use UI animation packages for the actual video/FX processing pipeline.

### Optional advanced image-view/editor helper

`extended_image` is a candidate for presentation-only features such as:

- zoom/pan;
- crop/rotate/flip tools;
- image-view transitions;
- bounded image cache behavior.

It is **not** the authoritative decoder, processing runtime or output renderer. Adoption requires a small memory/performance spike first.

## 2. Aspect ratio is a product contract

PRISMA must explicitly model fit behavior instead of relying on ad-hoc widget defaults.

Supported semantic modes begin with:

```text
CONTAIN
COVER
FILL
FIT_WIDTH
FIT_HEIGHT
NATIVE_PIXELS
SCALE_DOWN
```

`packages/prisma_media_runtime` now owns `MediaPresentationPolicy` and decode-size planning independently of Flutter `BoxFit` or Android view classes.

Flutter may map these semantics to `BoxFit`/`applyBoxFit` where appropriate, but the product contract is platform-neutral.

Important separation:

```text
SOURCE RESOLUTION
    !=
DECODE RESOLUTION
    !=
PREVIEW RESOLUTION
    !=
PROCESSING RESOLUTION
    !=
PROGRAM OUTPUT RESOLUTION
```

A 6000×4000 JPEG shown in a 320×180 library card must not be fully decoded merely because the source is high resolution.

Likewise, preview resolution must not silently determine final program-output resolution.

## 3. Resolution policy

Resolution decisions are capability- and purpose-driven.

### Thumbnail

Decode near the actual bounded thumbnail target. Never decode original-size media for a small grid cell.

### Preview

Decode/render at a resolution appropriate for the viewport and device pixel ratio, subject to a runtime pixel/memory budget.

### Processing source

Preserve enough source resolution for the active processing graph and requested output. Do not upscale during decode by default; scaling belongs later in the render path unless measurement proves otherwise.

### Program output

Uses the explicit output route/resolution contract. It is not inferred from the phone preview size.

## 4. Android still-image stack

Preferred direction:

- modern Android image decoder APIs when available;
- `BitmapFactory` fallback where required by target API/device behavior;
- decode-time target sizing/downsampling;
- no raw full-resolution pixel transfer through Flutter MethodChannel.

The current M0 bridge already uses bounded metadata probing. The next native spike must compare target-size decoding, format coverage and memory behavior.

Potential formats to validate include JPEG, PNG, WebP and HEIF where supported by the target device/OS. Unsupported/corrupt media must fail closed.

## 5. Android video stack

### Playback/loop baseline

Jetpack Media3 / ExoPlayer is the preferred first production candidate for reliable playback, seek, repeat/loop and codec/device abstraction.

At the time of this ADR, Android's official Media3 release documentation reports stable `1.11.1`. The exact dependency version must be selected when implementation is committed, not copied permanently from this research note.

### Processing integration

For PRISMA's frame-level visual processing, the implementation may need to descend below the convenience player layer into:

- `MediaCodec`;
- `Surface` / `SurfaceTexture`;
- GPU texture interop;
- OpenGL ES / Vulkan or another measured Android GPU path.

Media3 may remain responsible for demux/playback timing while a lower layer owns the render target. This must be proven by a physical spike.

The architecture therefore depends on `LocalMediaRuntime`, not directly on ExoPlayer classes.

## 6. Flutter rendering / Impeller

Flutter/Impeller is appropriate for application UI, overlays, controls and PRISMA visual chrome.

It is **not automatically assumed** to be the final high-bandwidth video-processing engine. The media/FX pipeline must be selected by measuring frame copies, texture interop, sustained FPS, latency and memory pressure.

Raw RGBA video frames must not cross Dart method channels frame-by-frame.

## 7. Resource ownership

Every expensive resource must have one explicit owner and one idempotent release path.

Examples:

```text
Video decoder
Render surface
SurfaceTexture / texture handle
Decoded still image
Thumbnail cache entry
Recorder encoder
Remote preview transport
```

The platform-neutral media package now defines:

- `MediaResourceBudget`;
- `MediaResourceSnapshot`;
- `ResourcePressureLevel`;
- `ResourceReleasePolicy`;
- `ReleasableMediaResource`.

Exact byte/decoder limits are determined from device capability measurement rather than hard-coded as universal constants.

## 8. Cache policy

Use separate caches for separate purposes.

```text
Thumbnail cache          bounded by bytes
Decoded still cache      bounded by bytes
GPU texture/surface pool explicitly bounded
Video decoder pool       explicitly bounded
Network/live-view cache  transport-specific and bounded
```

Do not use a single unbounded image cache for the whole application.

Flutter's `ImageCache.maximumSizeBytes` can be configured as part of the presentation cache budget. Native media caches remain outside Flutter's image cache.

## 9. Android memory-pressure behavior

The Android adapter must translate platform memory/lifecycle pressure into the platform-neutral release policy.

Expected behavior:

### NORMAL

Keep actively useful caches and sessions.

### ELEVATED

- evict disposable thumbnail cache;
- release idle decoded stills;
- release non-program render surfaces;
- preserve the active performance path where possible.

### CRITICAL

- perform all elevated-pressure actions;
- release paused/nonessential video decoders;
- aggressively drop recreatable GPU resources;
- preserve only the minimum resources necessary for the active program-output path.

The app must recover resources lazily after pressure subsides rather than immediately rebuilding everything.

## 10. Lifecycle rules

- `open()` acquires only resources required for the requested media session.
- `close()` is deterministic and idempotent.
- navigation away from a view does not automatically imply media destruction; application/session ownership decides that.
- conversely, an invisible UI widget is never sufficient justification to keep a decoder alive.
- Android foreground/background transitions must have explicit media policy.
- native player/decoder `release()` calls are mandatory when ownership ends.
- temporary import/decode resources must be released on both success and error paths.

## 11. UI performance rules

- expensive image decode does not run synchronously on Flutter's UI thread;
- large images are decoded near target size;
- list/grid thumbnails use bounded cache and lazy construction;
- waveform/thumbnail generation, when added, is cancellable and backpressured;
- animated UI never controls authoritative media clock;
- visual effects in the product UI are disabled/reduced automatically if they threaten playback/render deadlines;
- accessibility and touch-target behavior remain intact under every skin.

## 12. Libraries explicitly not allowed to own core architecture

A package may be useful without becoming architectural infrastructure.

Do not couple Core/Domain to:

- `extended_image`;
- `flutter_animate`;
- Media3/ExoPlayer classes;
- Android `Bitmap`;
- Android `Surface`;
- Flutter `ui.Image`;
- any specific GPU API.

All of those stay behind adapters or presentation wrappers.

## 13. Physical acceptance matrix

Before accepting the final media stack, test at minimum:

1. portrait, landscape, square and extreme-aspect images;
2. source smaller and larger than viewport;
3. contain/cover/fill/native-pixel behavior;
4. 720p, 1080p and higher-resolution sources allowed by the target device;
5. rapid source switching;
6. repeated open/close cycles with no decoder/surface growth;
7. 30+ minute video loop with stable memory;
8. app background/foreground cycles;
9. rotation and external-display changes;
10. Android memory-pressure callbacks;
11. corrupt/unsupported media;
12. simultaneous library thumbnails + active preview + program output;
13. GPU/decoder resource exhaustion behavior;
14. thermal throttling behavior during sustained processing.

Record CPU, Java/native heap, GPU memory where measurable, dropped frames, frame latency, decoder count and surface count.

## 14. Dependency policy

New visual/media packages require:

- active maintenance check;
- compatible license;
- Android/iOS support where relevant;
- measured memory behavior;
- no hidden full-resolution decode for thumbnail use;
- explicit disposal/lifecycle behavior;
- ability to wrap behind a PRISMA-owned interface;
- removal path without rewriting domain/application code.

## References used for this decision

- Flutter `BoxFit` / `applyBoxFit`: https://api.flutter.dev/flutter/painting/BoxFit.html
- Flutter image cache byte limit: https://api.flutter.dev/flutter/painting/ImageCache/maximumSizeBytes.html
- Flutter Impeller documentation: https://docs.flutter.dev/perf/antialiasing
- Android bitmap/memory guidance: https://developer.android.com/topic/performance/memory/guide/bitmaps
- Android Media3 releases: https://developer.android.com/jetpack/androidx/releases/media3
- Android Media3 playback guide: https://developer.android.com/media/implement/playback-app
- `extended_image` candidate: https://pub.dev/packages/extended_image
- `flutter_animate` candidate: https://pub.dev/packages/flutter_animate

## Decision state

The boundaries and resource-management rules are accepted as implementation requirements.

The concrete third-party libraries remain **PROPOSED** until M0/M1 physical-device measurements justify them.
