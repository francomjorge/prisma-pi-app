# PRISMA-PI App — Processing Runtime Adapter

**Status:** IMPLEMENTED_PENDING_CURRENT_CI / physical GPU validation pending  
**Scope:** platform-neutral processing-plan boundary plus Android M0 adapter proof

## Purpose

PRISMA needs one ordered processing model that can execute on different backends without making product state depend on OpenGL ES, Vulkan, Metal, browser canvas or any specific decoder API.

The processing boundary is therefore split into three layers:

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

## ProcessingPlan schema v1

The platform boundary currently serializes a plan as control data only:

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
GLSL diagnostic processing
        ↓
native render target
```

The M0 Android adapter currently advertises only:

```text
POSTER
GRAYSCALE
```

and accepts at most one active node. This limit is intentional. The goal is to validate the architecture before implementing a production multi-pass chain.

The current POSTER diagnostic parameters are:

```text
amount = 0.85
levels = 6
```

The Android adapter parses the schema-versioned plan and rejects unknown node types instead of falling back silently.

## Next GPU-runtime step

The next implementation increment is an ordered multi-pass GPU chain.

For effects that cannot be fused safely into one shader, the expected topology is:

```text
OES decoder texture
    ↓
input conversion/sample pass
    ↓
FBO texture A
    ↓
node 1
    ↓
FBO texture B
    ↓
node 2
    ↓
FBO texture A
    ↓
...
    ↓
program output / preview sink
```

This ping-pong ownership must remain behind the native adapter. The domain/runtime plan must not expose OpenGL framebuffer IDs.

Before adding the full FX family, prove at least:

1. two ordered nodes execute in the requested order;
2. reorder changes output deterministically;
3. bypass removes one pass without rebuilding unrelated product state;
4. resource ownership returns to baseline after plan replacement;
5. no CPU readback is required for the normal video path.

## Effect-family direction

The runtime is generic enough to host the planned local chain:

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

This document does not yet freeze their parameter schemas. Shared effect semantics belong in the product/domain contract and must be aligned with PRISMA Core before production implementation.

Browser FX prototypes remain behavioral references only; their canvas implementation is not a native-runtime dependency.

## Non-claims

This increment does not yet prove:

- multi-node GPU execution;
- zero-copy on every Android codec/device;
- dynamic graph update on a physical phone;
- production Vulkan versus OpenGL ES selection;
- Metal implementation on iOS;
- HDR/color-management correctness;
- external-display or encoder output;
- hardware-tested resource stability.

The Flutter + native architecture ADR remains PROPOSED until the physical M0 acceptance gate is completed.
