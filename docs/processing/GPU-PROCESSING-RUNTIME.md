# PRISMA-PI App — Processing Runtime Adapter

**Status:** platform-neutral runtime STATICALLY_VERIFIED / Android ordered multi-pass BUILT_SPIKE / physical GPU validation pending  
**Scope:** platform-neutral processing-plan boundary plus Android M0 execution-adapter proof

## Purpose

PRISMA needs one ordered processing model that can execute on different backends without making product state depend on OpenGL ES, Vulkan, Metal, browser canvas or any specific decoder API.

The processing boundary is split into these layers:

```text
PrismaState / ProcessingGraph
        ↓
ProcessingGraphCompiler
        ↓
ProcessingPlan
        ↓
ProcessingRuntimeAdapter
        ↓
Android GPU / future Vulkan / future Metal / appliance runtime
```

The domain graph remains the product truth. A native backend is an execution adapter, not the owner of effect state.

## Package

`packages/prisma_processing_runtime`

The package depends on `prisma_domain` and contains no Android, iOS, Flutter, OpenGL, Vulkan or Metal types.

It owns:

- backend capability descriptions;
- opaque frame transport categories;
- input/output binding contracts;
- deterministic runtime-node plans;
- graph compilation;
- strict unsupported-node handling;
- optional explicit bypass-with-diagnostic behavior;
- active-node limit enforcement;
- runtime adapter/session interfaces;
- schema-versioned platform serialization.

## Graph compilation

`ProcessingGraphCompiler.compileLocal(...)` compiles only nodes whose execution target is:

```text
MOBILE
BOTH
```

Nodes targeted only at the appliance are intentionally excluded from the local plan.

A local node is omitted when it is:

- disabled; or
- explicitly bypassed.

For active nodes, compilation checks:

1. node type supported by the backend;
2. required backend capabilities;
3. maximum active-node count;
4. deterministic graph order.

Unsupported active nodes fail closed by default. They are never silently ignored.

An explicit `UnsupportedNodePolicy.bypass` exists for controlled compatibility/degraded modes. When used, every skipped node produces a diagnostic.

Automated tests now explicitly prove that:

- compiled node order follows the authoritative domain graph;
- `ProcessingGraph.reorder(...)` changes the emitted plan order deterministically;
- bypass removes a supported node while the remaining nodes are renumbered contiguously;
- backend capability and node-count limits remain enforced.

These tests prove plan semantics, not visual Android GPU output.

## ProcessingPlan schema v1

The platform boundary serializes a plan as control data only:

```text
{
  schema_version: 1,
  nodes: [
    {
      node_id: "...",
      type: "POSTER",
      order: 0,
      parameters: { ... }
    }
  ]
}
```

No image or video frame data is serialized in this map.

Node type identifiers are normalized to uppercase at the runtime boundary so adapters do not depend on presentation spelling.

## Frame transport contract

The runtime distinguishes transport categories from product media semantics.

Current transport vocabulary:

```text
opaqueGpuTexture
opaqueNativeSurface
cpuBuffer
remoteStream
```

`opaqueGpuTexture` and `opaqueNativeSurface` are deliberately opaque. A portable project must never persist native texture IDs, Android Surface instances, file descriptors or platform pointers.

A runtime locator is ephemeral adapter state only.

## Runtime adapter contract

A backend implements `ProcessingRuntimeAdapter`.

It declares `ProcessingBackendCapabilities`, then opens a `ProcessingRuntimeSession` using:

```text
ProcessingSessionRequest
  ├── ProcessingPlan
  ├── ProcessingInputBinding
  └── ProcessingOutputBinding
```

A session exposes only lifecycle/control operations:

```text
updatePlan(...)
close()
```

There is intentionally no Dart-level `processFrame(bytes)` API. Sustained video must stay in native/GPU media paths rather than copying per-frame payloads through Flutter channels.

## Android M0 integration

The disposable Android spike now follows this path:

```text
Domain ProcessingGraph
        ↓
prisma_processing_runtime compiler
        ↓
ProcessingPlan schema v1
        ↓
Flutter AndroidView creation control data
        ↓
AndroidGpuVideoSurfaceFactory
        ↓
Media3 decoder
        ↓
SurfaceTexture / GL_TEXTURE_EXTERNAL_OES
        ↓
OES input/aspect pass
        ↓
2D texture / FBO A
        ↓
ordered node pass
        ↓
2D texture / FBO B
        ↓
ordered node pass
        ↓
...
        ↓
native render target
```

The native adapter owns all OpenGL resource identifiers. No texture name or framebuffer ID enters Dart, `ProcessingPlan`, `PrismaState` or portable project state.

## Ordered ping-pong implementation

The Android diagnostic adapter now allocates two reusable RGBA 2D textures and two framebuffers when at least one processing node is active.

The execution rule is:

```text
OES decoder texture
    ↓
input pass → FBO A
    ↓
node 0 → FBO B
    ↓
node 1 → FBO A
    ↓
node 2 → FBO B
    ↓
...
    ↓
last node → screen
```

Only two intermediate render targets are needed regardless of diagnostic chain length because source and destination alternate. The final node renders directly to the native output target.

The input pass performs the `SurfaceTexture` transform and presentation fit before the regular 2D effect passes. Subsequent passes therefore sample normal `sampler2D` textures rather than the external OES texture.

The current M0 parser:

- requires `schema_version == 1`;
- requires contiguous `order` values matching the received node list;
- rejects unknown node types;
- supports at most four active diagnostic nodes;
- currently maps only `POSTER` and `GRAYSCALE`;
- never silently falls back when an active node is unsupported.

## Current two-node diagnostic plan

The Android spike now compiles this domain graph through the neutral runtime:

```text
0  POSTER
   amount = 0.85
   levels = 6

1  GRAYSCALE
   amount = 0.35
```

The native GPU adapter consumes exactly that emitted order.

This is deliberately a diagnostic chain. The parameter vocabulary for the production FX family is not frozen by this spike.

## GPU resource ownership

`AndroidMediaResourceTracker` now includes process-local counters for:

```text
active_gpu_textures
active_gpu_framebuffers
```

The diagnostic UI exposes those counters beside decoded-image, decoder and render-surface counters.

The GPU adapter accounts for:

- the external OES decoder texture;
- the two ping-pong 2D textures;
- the two ping-pong framebuffers;
- input and effect shader programs through explicit native ownership;
- `SurfaceTexture` and decoder `Surface` lifecycle.

Intermediate textures/framebuffers are recreated when viewport dimensions change and released when the platform view is disposed.

This instrumentation is intended to make repeated open/release and plan-recreation leaks visible during physical M0 testing. CI cannot prove that Android actually allocates/releases the underlying GPU memory correctly on a device.

## CI evidence boundary

The green Android gate proves:

- Dart graph compiler analysis/tests;
- order/reorder/bypass plan tests;
- Kotlin parser/API compilation;
- GLES2 texture/FBO API compilation;
- Media3 + OES + ping-pong shader path compilation;
- Flutter diagnostic host analysis/tests;
- complete debug APK build.

It does not execute an Android GPU driver.

## Physical-device acceptance gate

Before the multi-pass path can become `HARDWARE_TESTED`, validate on Android hardware:

1. H.264/MP4 reaches the OES texture and renders through both diagnostic passes;
2. POSTER → GRAYSCALE output is visually correct;
3. reversing the plan order produces the corresponding different execution order;
4. bypassing either node removes exactly one GPU pass;
5. no CPU image-buffer/readback path is required during normal playback;
6. `active_gpu_textures` / `active_gpu_framebuffers` return to baseline after close/reopen cycles;
7. viewport/rotation changes recreate intermediate targets without monotonic resource growth;
8. background/foreground does not leave stale decoder, SurfaceTexture, texture or FBO ownership;
9. 30+ minute processed loop has no monotonic Java/native/GPU memory growth;
10. dropped frames and thermal behavior are recorded;
11. corrupt/unsupported sources do not poison the next GPU session.

## Effect-family direction

The runtime remains generic enough to host the planned local chain:

```text
PIXEL
GLITCH
POSTER
HUE
MIRROR
masks
keying
compositing
future generators
```

Shared parameter semantics must be aligned with PRISMA Core before the production implementation expands this family. Browser FX prototypes remain behavioral references only; their canvas implementation is not a native-runtime dependency.

## Next processing-runtime step

The architecture needed for ordered multi-pass execution is now present and builds. The next meaningful gates are:

1. physical validation of the two-node chain and GPU resource lifecycle;
2. production-shaped plan replacement/update semantics after device behavior is measured;
3. effect-parameter alignment with Core;
4. only then expansion to PIXEL/GLITCH/HUE/MIRROR and compositing nodes.

Do not add more effect types merely to increase feature count before the runtime path is physically validated.

## Non-claims

This increment does not yet prove:

- that decoded frames actually traverse both passes on a physical phone;
- zero-copy behavior on every Android codec/device;
- physical reorder/bypass output correctness;
- dynamic plan updates without session recreation;
- production Vulkan versus OpenGL ES selection;
- Metal implementation on iOS;
- HDR/color-management correctness;
- external-display or encoder output;
- hardware-tested resource stability.

The Flutter + native architecture ADR remains PROPOSED until the physical M0 acceptance gate is completed.
