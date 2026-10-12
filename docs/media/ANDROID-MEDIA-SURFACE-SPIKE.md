# PRISMA-PI App — Android Native Media Surface Spike

**Status:** IMPLEMENTED / CI + physical-device validation pending  
**Target:** disposable Android M0 host only

## Purpose

Prove that PRISMA can keep Flutter as the application/presentation shell while native Android code owns heavy image/video decode and render resources.

This spike is not product UI. It exists to validate the media boundary, aspect/resolution semantics and deterministic resource release before the production media stack is frozen.

## Current path

```text
Android document picker
  -> ContentResolver
  -> importer-owned staging
  -> managed PRISMA media file
  -> native metadata/decode probe
  -> Android native platform view
       IMAGE: target-sized ImageDecoder/BitmapFactory -> ImageView
       VIDEO: Media3 ExoPlayer -> PlayerView/Surface
  -> explicit dispose()
  -> resource counters return toward zero
```

No raw full-resolution image or video frame is transferred through MethodChannel.

## Media3 baseline

The disposable spike compiles against AndroidX Media3 `1.11.1` for:

- `media3-exoplayer`;
- `media3-ui`.

This pins only the diagnostic host so CI can detect native API/Gradle breakage. It does not yet freeze the final production dependency version.

The video surface currently proves:

- managed local-file handoff;
- ExoPlayer construction;
- prepare/play lifecycle;
- mute;
- repeat-one loop configuration;
- aspect resize mapping;
- PlayerView/Surface ownership;
- explicit player release when the platform view is disposed.

Physical sustained-loop quality, hardware decoder use, dropped frames, external-display behavior and GPU processing interop remain unverified.

## Target-sized image decode

The image surface decodes near the requested viewport instead of blindly materializing the original source resolution.

On Android API 28+ the spike uses `ImageDecoder` with a requested target size. Older Android falls back to `BitmapFactory` with power-of-two sampling followed by bounded scaling.

Supported semantic fit mapping in the spike starts with:

```text
contain
cover
fill
fitWidth
fitHeight
nativePixels
scaleDown
```

The canonical geometry contract remains `MediaPresentationPolicy` in `prisma_media_runtime`; Android view classes are adapters only.

## Resource ownership

`prisma_media_runtime` now includes `MediaResourceRegistry` and `MediaResourceLease` so expensive resources have:

- one logical owner;
- explicit resource kind;
- optional byte accounting;
- duplicate-ownership rejection;
- idempotent release;
- aggregate snapshot;
- budget/pressure evaluation;
- selective or complete release.

Native M0 code additionally records diagnostic counters for:

```text
decoded_image_bytes
active_video_decoders
active_render_surfaces
```

The diagnostic Flutter screen can create/release/reopen a native surface and resample those counters. The acceptance expectation is that repeated source/surface disposal does not cause monotonic decoder/surface growth.

## CI scope

The foundation workflow now:

1. runs `prisma_media_runtime` analysis/tests including resource ownership;
2. generates the disposable Flutter Android host;
3. injects Media3 ExoPlayer/UI dependencies;
4. compiles the native media platform-view factory and resource tracker;
5. runs Flutter analysis/tests;
6. builds the debug APK.

CI proves compilation and platform-neutral semantics only. It cannot prove hardware decoder selection or runtime Surface behavior.

## Physical acceptance sequence

On a real Android device:

1. import a large portrait JPEG and a large landscape JPEG;
2. verify bounded target decode and correct aspect fit;
3. release/reopen the image surface repeatedly while sampling decoded bytes;
4. import an H.264/AAC MP4 known to be hardware-decodable on the device;
5. run repeat-one playback for at least 30 minutes;
6. perform rapid source switches;
7. repeatedly create/dispose the video surface;
8. verify decoder/surface counts return after release;
9. background/foreground the app repeatedly;
10. rotate the device and test surface recreation;
11. record CPU, Java/native heap, dropped frames and thermal behavior;
12. only after that evaluate SurfaceTexture/GPU-texture handoff for the processing graph.

## Non-goals

- no final visual design;
- no final media browser;
- no effect processing yet;
- no claim that PlayerView is the final GPU processing surface;
- no claim that every codec/container is supported;
- no acceptance of ADR-001/ADR-004 from CI alone.
