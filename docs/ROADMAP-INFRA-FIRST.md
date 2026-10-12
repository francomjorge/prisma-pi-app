# Infrastructure-First Roadmap

## Phase 0 — Repository & contract baseline

- initialize app repository;
- import/adapt Core mobile foundation documentation;
- document legacy web behavior;
- define engineering status vocabulary;
- block product UI implementation until foundation gates pass.

**Exit:** architecture documents reviewed and repository structure frozen enough to begin non-UI code.

## Phase 1 — Domain/client core

Implement platform-independent app models for:

- PrismaState client representation;
- commands/events;
- capabilities;
- device descriptors;
- sessions;
- processing graph;
- media endpoint descriptors;
- logical asset/project models.

**Tests:** serialization, command validation, generation ordering, capability parsing.

## Phase 2 — Storage foundation

Implement:

- managed app directories;
- SQLite metadata layer;
- migrations;
- image import transaction;
- video import transaction;
- hash/integrity validation;
- project persistence;
- recovery from interrupted staging/import.

**Exit:** media can be imported/reopened after restart with no UI dependency.

## Phase 3 — Connector framework + Mock Appliance

Implement:

- `PrismaConnector` interface;
- connector lifecycle/state machine;
- Mock Appliance server/runtime;
- Protocol 2.0 request/response;
- event channel;
- capability negotiation;
- reconnect and event-gap recovery.

**Exit:** automated integration tests can run without physical hardware.

## Phase 4 — Security & discovery

Implement/validate:

- mDNS/DNS-SD discovery on Android;
- manual endpoint diagnostic fallback;
- secure storage adapter;
- production pairing profile selected from validated appliance constraints;
- pairing/authentication lifecycle;
- forget/revoke/reset behavior.

**Exit:** trusted mock/reference device survives app restart and reconnect securely.

## Phase 5 — Media runtime foundation

Implement:

- local image decoder;
- local looping video decoder;
- preview renderer;
- frame timing;
- MediaEndpoint selection;
- legacy remote preview adapter;
- local recorder foundation;
- output-router interfaces.

**Exit:** local and remote previews work through the same app abstractions.

## Phase 6 — Processing graph runtime

Implement graph engine contracts and first reference nodes.

Required initially:

- ordered nodes;
- enable/bypass;
- parameter updates;
- execution-target metadata;
- graph serialization;
- mobile backend interface;
- deterministic graph rebuild/update behavior.

Do not reproduce every legacy effect at once. Prove the runtime with minimal reference processors first.

## Phase 7 — Legacy ESP32 compatibility

Implement `LegacyEsp32Connector` without changing feature/UI code.

Map:

- legacy `/api/state` → app state snapshot;
- legacy `/source/...` → compatibility MediaEndpoint;
- supported control endpoints as commands where physically validated;
- missing Protocol 2.0 capabilities as explicitly unavailable.

**Exit:** current appliance can be controlled/monitored by infrastructure APIs before the final UI exists.

## Phase 8 — Skin tokens + input actions

Implement:

- token schema;
- `Vintage Analog` reference skin data;
- input action registry;
- keyboard mapping model;
- drag/drop action contracts.

**Exit:** presentation code can be written without hard-coded visual constants or feature-specific keyboard logic.

## Phase 9 — Android product UI

Only now build production screens/features:

```text
Performance / PiCore
Live View
FX Rack
FX Lab
Library
Devices & Routing
System
```

Start with functional layout and interaction correctness before final visual polish.

## Phase 10 — Android distribution

- signed Android App Bundle;
- Google Play internal testing;
- crash/diagnostic pipeline;
- update/install validation;
- device compatibility matrix.

## Phase 11 — iOS port

Reuse shared domain/application/UI architecture while supplying iOS-specific adapters for:

- secure storage;
- discovery/network permissions;
- files/media import;
- AVFoundation/Metal media backends as required;
- TestFlight distribution.

## Phase 12 — Hybrid/distributed expansion

Reserved for later:

- mobile asset transfer to appliance;
- distributed processing;
- multiple appliances;
- richer audio input/modulation;
- external display/program output workflows;
- additional controller transports.
