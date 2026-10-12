# PRISMA-PI App — Mobile Foundation 2.0

**Status:** Draft foundation / DESIGNED  
**Target:** Android first, iOS second

## 1. Purpose

This document defines the infrastructure boundary for the PRISMA-PI mobile controller. It does not define final visual screens. The mobile application is the primary controller and local processing host; the web controller remains an optional compatibility/secondary surface.

## 2. Non-negotiable architecture rules

1. `PrismaState` remains the single authoritative synthesizer state for a controlled appliance session.
2. All state mutations are commands.
3. UI navigation and skin state are not synthesizer state.
4. Device support is capability-driven, not model-name-driven.
5. Source Preview, Processed Preview and Program Output are separate media concepts.
6. Mobile processing and appliance processing are separate execution runtimes.
7. The mobile app must support image and video sources from the first production-capable build.
8. Audio is reserved as a first-class future source/modulation path.
9. File storage, device identity, security, discovery, transport, synchronization and media contracts must be stable before product UI implementation begins.
10. Visual styling must be tokenized so skins can replace colors, typography, spacing, radius, texture and component treatment without changing behavior.
11. The mobile application must not be implemented as a WebView wrapper around the legacy controller.
12. Legacy appliance behavior is isolated behind compatibility adapters.

## 3. Runtime topology

```text
Mobile App
├── Presentation Runtime
│   ├── Skin Engine
│   ├── Input Mapper
│   └── View Navigation
├── Application Runtime
│   ├── Command Bus
│   ├── Session Manager
│   ├── Device Manager
│   ├── Library Manager
│   └── Project Manager
├── Prisma Domain/Core Contracts
│   ├── State Model
│   ├── Command Model
│   ├── Capability Model
│   └── Module/FX Model
├── Connector Layer
│   ├── Wi-Fi/LAN Connector
│   ├── USB/Cable Connector
│   ├── Legacy ESP32 Connector
│   └── Future Connectors
├── Media Runtime
│   ├── Source Decoder
│   ├── Processing Graph
│   ├── Preview Renderer
│   ├── Recorder
│   └── Output Router
└── Platform Services
    ├── Secure Credential Store
    ├── Filesystem
    ├── Database
    ├── Network Discovery
    └── Hardware Acceleration
```

## 4. Device model

A remote device is represented as a `PrismaDevice`, never as a hard-coded ESP32/Raspberry-Pi class.

```text
PrismaDevice
├── device_id
├── display_name
├── model
├── firmware_version
├── protocol_version
├── capabilities
├── endpoints
├── paired
├── trust_state
└── health
```

Logical services:

```text
DeviceInfoService
CapabilityService
ControlService
StateEventService
FileService
PreviewService
OutputService
DiagnosticsService
```

Not every appliance must implement every service. Availability is declared through capabilities.

## 5. Connector contract

```text
PrismaConnector
├── discover()
├── connect(device)
├── pair(device)
├── authenticate(device)
├── disconnect(device)
├── request(...)
├── subscribe(...)
├── open_media_channel(...)
└── transfer_file(...)
```

Initial connector families:

- `LAN_WIFI`
- `USB_CABLE`
- `LEGACY_ESP32`

Feature code must never depend directly on transport details.

## 6. Control direction

Protocol 2.0 separates request/response operations from live state events.

Request/response handles device information, capabilities, initial full state, file operations, settings, diagnostics and pairing/bootstrap.

The live event channel handles authoritative state changes, sources, effects/modules, processing state, outputs, health, faults and media-channel state.

Repeated short-interval HTTP polling is legacy-only. Preferred IP synchronization uses a persistent event transport.

Every authoritative state mutation increments `generation`.

## 7. Security baseline

Production behavior must not rely on an open AP plus unauthenticated HTTP control.

Required properties:

- stable per-device identity;
- explicit first-pairing flow;
- per-client authorization material;
- credentials stored in Android Keystore / iOS Keychain;
- authenticated control requests;
- replay-resistant session establishment;
- trust revocation/reset path;
- no plaintext password persistence in app data;
- no globally shared permanent appliance password;
- development legacy mode clearly marked and isolated.

The exact cryptographic profile remains gated by real target-device constraints and official SDK support.

## 8. Discovery

For LAN operation the app should discover compatible appliances without manual IP entry.

```text
DiscoveryRecord
├── device_id
├── display_name
├── host
├── control_port
├── protocol_version
├── pairing_required
└── capability_digest
```

Preferred LAN discovery: mDNS/DNS-SD where supported. Manual IP remains a diagnostic fallback.

## 9. Media endpoint model

Control protocol does not assume a single preview encoding.

```text
MediaEndpoint
├── purpose
├── transport
├── codec_or_format
├── width
├── height
├── fps
├── audio
├── latency_class
└── uri/session descriptor
```

Purposes:

- `SOURCE_PREVIEW`
- `PROCESSED_PREVIEW`
- `PROGRAM_OUTPUT`

Possible transports may include legacy JPEG/MJPEG, WebRTC, RTSP or future mechanisms. Selection is capability-based.

## 10. Local media library

The application owns a managed library rather than depending on arbitrary external file paths.

```text
library/
  media/
  recordings/
  projects/
  skins/
staging/
cache/
logs/
```

Each media asset has an immutable logical ID plus metadata. Imports are transactional: ingest → validate → hash → probe metadata → commit managed file → commit metadata → publish library event.

## 11. Projects

```text
PrismaProject
├── project_id
├── name
├── created_at
├── modified_at
├── selected_source
├── processing_graph
├── output_routes
├── module_state
├── ui_preferences
└── schema_version
```

Projects reference logical asset IDs, never volatile filesystem paths.

## 12. Processing graph

Effects, Motion and advanced FX are represented in one ordered processing graph.

```text
Source
  -> Transform
  -> Visual FX
  -> Motion FX
  -> Modules
  -> Composite/Mix
  -> Output Router
```

```text
ProcessingNode
├── node_id
├── type
├── enabled
├── bypass
├── parameters
├── execution_targets    MOBILE | APPLIANCE | BOTH
├── required_capabilities
└── order
```

The processing graph is infrastructure shared by simplified FX Rack and advanced FX Lab. UI never owns processing order.

## 13. Execution modes

### LOCAL

Source and processing live on the phone/tablet. The mobile Media Runtime decodes, processes, previews, records and routes output.

### APPLIANCE

The app controls a remote PRISMA device. The appliance owns authoritative processing state and media execution; the app consumes state, diagnostics and preview/media services.

### HYBRID — reserved

The architecture must permit future source transfer, distributed processing or mixed routing between mobile and appliance runtimes.

## 14. Input abstraction

```text
Touch / Mouse / Hardware Keyboard / Future input
                         ↓
                    Input Mapper
                         ↓
                     Command Bus
```

Keyboard shortcuts therefore use the same command path as touch controls.

## 15. Skin architecture

Behavior must not contain hard-coded presentation decisions.

Minimum token groups:

- colors;
- typography;
- spacing;
- radii;
- borders;
- shadows;
- textures;
- control dimensions;
- animation timings;
- state styles.

First product skin target: warm vintage photographic/electronic equipment aesthetic, inspired by analog film-era hardware without copying a specific brand identity.

## 16. Functional UI boundaries

Expected feature areas:

```text
Performance / PiCore
Live View
FX Rack
FX Lab
Library
Devices & Routing
System
```

These are functional boundaries, not frozen screen layouts.

## 17. Infrastructure gates before product UI

The Android product UI does not begin until these are independently validated:

- Core/domain contracts;
- Protocol 2.0 envelope and compatibility strategy;
- LAN discovery;
- pairing and secure credential lifecycle;
- live state synchronization and reconnection;
- managed media import/storage;
- image decode;
- looping video decode;
- processing graph contract;
- media endpoint negotiation;
- connector abstraction;
- capability negotiation;
- Mock Appliance;
- skin token schema;
- structured logging and diagnostics.

## 18. Legacy compatibility

Existing `/api/state`, `/source/...`, browser-side FX and the current web surfaces are compatibility inputs and test vectors, not the final mobile architecture.

No physically validated appliance baseline is overwritten while Protocol 2.0 is being developed.
