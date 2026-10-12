# PRISMA-PI App Repository Layout

**Status:** partially implemented infrastructure layout

The repository separates product/domain logic from platform adapters and presentation so Android-first work does not make iOS a rewrite.

```text
prisma-pi-app/
├── README.md
├── docs/
│   ├── architecture/
│   ├── accounts/
│   ├── connectivity/
│   ├── decisions/
│   ├── media/
│   ├── processing/
│   ├── protocol/
│   ├── storage/
│   ├── testing/
│   └── validation/
├── app/                              # production app shell intentionally not started
├── packages/
│   ├── prisma_domain/                # implemented
│   ├── prisma_connector/             # implemented
│   ├── prisma_security/              # implemented contract
│   ├── prisma_storage/               # implemented runtime + SQLite metadata
│   ├── prisma_media_runtime/         # implemented contract
│   ├── prisma_processing_runtime/    # implemented adapter/compiler contract
│   └── prisma_mock_appliance/        # implemented test server
├── spikes/
│   └── android_flutter/              # disposable M0 Flutter/Kotlin validation host
├── native/                           # reserved for production native media backends
│   ├── android_media/
│   └── ios_media/
├── tools/                            # future developer tooling/fixtures
└── tests/                            # future cross-package integration suites
```

The conceptual `prisma_protocol` package has not been split out; shared Protocol 2.0 models still live in `prisma_domain` until a stronger implementation boundary requires a separate package.

Processing now has two deliberately separate ownership layers:

- `prisma_domain` owns `ProcessingGraph` as product semantics;
- `prisma_processing_runtime` owns compilation and execution-adapter contracts.

This keeps OpenGL/Vulkan/Metal concerns out of the authoritative product graph.

## Ownership rules

### `prisma_domain`

Owns platform-neutral synthesizer state, commands, events, device/capability descriptors, Protocol 2.0 envelope models, authoritative processing-graph contracts, account identity and entitlement contracts.

It imports no Android/iOS implementation package.

### `prisma_connector`

Owns connector interfaces and connection/session lifecycle. Current concrete/reference adapters include:

```text
Protocol2LanConnector
LegacyEsp32Connector
MockConnector
```

Future transports such as USB must implement the same application-facing connector boundary.

### `prisma_security`

Owns appliance trust-state, security-profile selection and secure credential/pairing adapter contracts. It does not contain Google account identity or store licensing logic.

### `prisma_storage`

Owns managed-library layout, transactional import semantics, integrity hashing, recovery, metadata repository interfaces and the current SQLite metadata implementation.

Platform-owned media bytes can enter through a materialization callback without moving full payloads through the application/UI layer.

### `prisma_media_runtime`

Owns platform-neutral local image/video runtime lifecycle and capability contracts. It does not own Android/iOS decoder implementations and never makes raw frame buffers a Dart/domain contract.

### `prisma_processing_runtime`

Owns the platform-neutral execution boundary between the domain `ProcessingGraph` and concrete processing backends.

It provides:

- backend capability declarations;
- local graph compilation;
- schema-versioned `ProcessingPlan` control data;
- opaque input/output transport categories;
- unsupported-node/capability policy;
- active-node limits;
- runtime adapter/session interfaces.

It does not own Android `Surface`, OpenGL texture/FBO identifiers, Vulkan resources, Metal textures or raw video frames.

### `prisma_mock_appliance`

Reference device implementation for Protocol 2.0/connector integration tests. It can simulate disconnects, generation gaps, transient failures, latency and media-endpoint behavior.

### `spikes/android_flutter`

Disposable M0 validation host. It is allowed to use Flutter/Kotlin diagnostic controls, Android NSD, Keystore, SAF and media APIs because its purpose is to prove platform boundaries before ADR-001 is accepted.

The current GPU spike also consumes a neutral `ProcessingPlan` and maps the supported diagnostic node to Media3 + SurfaceTexture/OES + GLSL. Code here is not automatically production application code.

### `native/android_media`

Reserved production Android media/processing backend. Candidate APIs must be validated by the M0 spike before this directory becomes the production implementation.

### `native/ios_media`

Equivalent iOS media/processing backend when the iOS phase starts.

## Dependency direction

```text
Presentation
     ↓
Application
     ↓
Domain / runtime contracts
  ↙        ↘
Ports     protocol models
  ↑
Adapters / platform implementations
```

For processing specifically:

```text
prisma_domain ProcessingGraph
        ↓
prisma_processing_runtime ProcessingPlan
        ↓
native backend adapter
```

Platform SDK objects must not cross into domain contracts. Platform-specific paths/URIs and native resource locators may exist only as ephemeral adapter/runtime state; portable project state stores logical IDs.

## Test placement

- pure package tests stay next to package code;
- protocol/connector integration tests use Mock Appliance;
- storage tests use temporary filesystems + SQLite;
- processing compiler/adapter-contract tests stay in `prisma_processing_runtime`;
- Android stack compilation/runtime probes live under `spikes/android_flutter`;
- future deterministic media fixtures belong under `tests/media` or `tools/fixtures` once sustained playback tests exist;
- physical Android/ESP32 evidence is tracked separately from automated simulation results.
