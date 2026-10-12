# PRISMA-PI App — Android GPU Texture Video Spike

**Status:** IMPLEMENTED_PENDING_CURRENT_CI / physical validation pending  
**Scope:** M0 Android diagnostic infrastructure only

## Purpose

Prove the first no-Dart-frame-copy path from a local video decoder into a GPU-sampleable texture before the PRISMA processing graph starts implementing real FX.

The spike deliberately does not claim that OpenGL ES is the final production GPU backend. It proves the architectural handoff that any final backend must preserve.

## Implemented path

```text
managed PRISMA video file
        ↓
Media3 / ExoPlayer
        ↓
android.view.Surface
        ↓
android.graphics.SurfaceTexture
        ↓
GL_TEXTURE_EXTERNAL_OES
        ↓
GLSL pass-through shader
        ↓
native render target
```

Flutter/Dart receives control/state only. No per-frame RGBA/YUV payload crosses a MethodChannel.

## Why SurfaceTexture

Android documents `SurfaceTexture` specifically as a consumer for image streams such as video decode. A `Surface` created from it can be used as a decoder output destination. The latest available frame is attached to an OpenGL ES external texture by calling `updateTexImage()` on the thread that owns the GL context.

The texture target is `GL_TEXTURE_EXTERNAL_OES`, sampled in GLSL with `samplerExternalOES`.

The spike therefore establishes the exact seam needed by the future processing graph:

```text
video clock / demux / decode
        !=
GPU effect processing
        !=
Flutter presentation state
```

## Current implementation

`spikes/android_flutter/android/AndroidGpuVideoSurfaceFactory.kt` provides a Flutter Android platform view backed by a `GLSurfaceView`.

The renderer:

1. creates one `GL_TEXTURE_EXTERNAL_OES` texture;
2. creates a `SurfaceTexture` bound to that texture;
3. creates an Android `Surface` from the `SurfaceTexture`;
4. gives that Surface to Media3 through `ExoPlayer.setVideoSurface(...)`;
5. receives frame-available callbacks;
6. schedules rendering without calling `updateTexImage()` from the callback thread;
7. calls `updateTexImage()` only on the GL render thread;
8. refreshes the SurfaceTexture transform matrix for the current frame;
9. samples the external texture in a pass-through fragment shader;
10. applies PRISMA contain/cover/fill-style geometry without changing decoder resolution.

The fragment shader is intentionally simple. It is a replaceable insertion point for later PRISMA shader/effect work, not a final FX engine.

## Aspect-ratio separation

Video decode resolution remains independent from presentation geometry.

The GPU renderer currently applies presentation scale after decode:

```text
source aspect
    ↓
Media3 decode
    ↓
external OES texture
    ↓
PRISMA fit geometry
    ↓
viewport
```

This preserves the architecture rule that `SOURCE`, `DECODE`, `PREVIEW`, `PROCESSING` and `PROGRAM OUTPUT` resolutions are separate concerns.

## Resource ownership

The platform view owns:

- Media3 `ExoPlayer`;
- decoder output `Surface` association;
- `SurfaceTexture`;
- OES texture name;
- GL shader program;
- native render view.

Disposal is explicit:

```text
clearVideoSurface()
release ExoPlayer
release Android media-resource accounting
queue GL-thread Surface/SurfaceTexture/texture/program release
pause GLSurfaceView
```

`AndroidMediaResourceTracker` remains the diagnostic process-local counter. The platform-neutral production ownership model remains `MediaResourceRegistry` / `MediaResourceLease` in `prisma_media_runtime`.

## CI can prove

CI may prove:

- Kotlin/Android API compatibility;
- Media3 dependency resolution;
- Flutter platform-view registration;
- GLSurfaceView / SurfaceTexture / OES shader compilation;
- Dart media-resource contracts and tests;
- debug APK build.

CI cannot prove actual decoded frames reach the GPU on a phone.

## Physical-device acceptance gate

Before this path can become `HARDWARE_TESTED`, validate on Android hardware:

1. H.264/MP4 loop plays through the OES texture path;
2. `onFrameAvailable` continues for sustained playback;
3. `updateTexImage()` remains on the GL thread and raises no context errors;
4. orientation/SurfaceTexture transform matrix is correct;
5. contain/cover/fill behavior is visually correct for portrait, landscape and square video;
6. repeated open/release cycles return decoder/surface counts to baseline;
7. 30+ minute loop does not show monotonic Java/native/GPU memory growth;
8. pause/background/foreground does not leak the player or SurfaceTexture;
9. source switching does not leave stale GL textures;
10. unsupported/corrupt video fails without poisoning the next session;
11. thermal behavior and dropped frames are recorded;
12. the OES texture can feed at least one real shader effect without a CPU readback.

## Next processing step

Once physical validation succeeds, add one deliberately trivial GPU effect in the shader path, for example grayscale or posterization, solely to prove:

```text
Media3 decode
  → OES texture
  → PRISMA shader stage
  → native render target
```

After that, define the reusable GPU processing-node adapter used by PIXEL, GLITCH, POSTER, HUE, MIRROR, masks and compositing.

Do not port browser-canvas FX code directly.

## Official references

- Android `SurfaceTexture`: https://developer.android.com/reference/android/graphics/SurfaceTexture
- Android `Surface(SurfaceTexture)`: https://developer.android.com/reference/android/view/Surface
- Media3 `ExoPlayer.setVideoSurface`: https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer

## Non-claims

This spike does **not** yet prove:

- zero-copy on every codec/device implementation;
- hardware decoder selection on every device;
- production-quality color management/HDR;
- final OpenGL ES versus Vulkan backend selection;
- external-display routing;
- recorder/encoder interoperability;
- final GPU FX architecture.
