# PRISMA-PI App — Connector & Session Runtime

**Status:** Draft / IMPLEMENTED FOUNDATION  
**Date:** 2026-10-12

## 1. Purpose

Define how the mobile app discovers, connects to, authenticates with and synchronizes a PRISMA appliance without leaking transport-specific details into product features or UI.

The app talks to a logical `PrismaConnector`. Wi-Fi/LAN, USB/cable, legacy ESP32 and test/mock transports are adapters behind that contract.

## 2. Runtime ownership

```text
Feature/UI action
      ↓
Application Command Bus
      ↓
PrismaSessionManager
      ↓
PrismaConnector
      ↓
Transport adapter
      ↓
PRISMA appliance
```

The session manager owns connection/synchronization lifecycle only. It does **not** own authoritative synthesizer state. The controlled appliance remains authoritative in APPLIANCE mode.

## 3. Connector contract

Minimum operations:

```text
discover()
connect(record)
authenticate()
disconnect()
getCapabilities()
getState()
getMediaEndpoints()
request(type,payload)
sendCommand(command)
events()
```

Transport families currently reserved:

```text
LAN_WIFI
USB_CABLE
LEGACY_ESP32
MOCK
```

Adding Bluetooth, Ethernet-direct, WebRTC data channel or another future transport must not require changing feature code.

## 4. Discovery record

Discovery returns bootstrap metadata, not trust:

```text
DiscoveryRecord
├── device_id
├── display_name
├── host / transport address
├── control_port
├── protocol_version
├── pairing_required
└── capability_digest
```

Discovery is never authorization. A discovered device still passes through pairing/authentication policy.

## 5. Session lifecycle

```text
IDLE
 ↓
CONNECTING
 ↓
AUTHENTICATING
 ↓
SYNCHRONIZING
 ↓
READY
 │
 ├─ event gap / media-control fault → STALE → SYNCHRONIZING → READY
 ├─ transport loss               → RECONNECTING → SYNCHRONIZING → READY
 ├─ unrecoverable failure        → FAILED
 └─ explicit close               → CLOSED
```

Commands are permitted only in `READY`.

The UI may keep local navigation, selected panel and skin state while a remote session is stale. It must not present stale remote synthesis state as confirmed current state.

## 6. Bootstrap sequence

```text
1. Discover / resolve endpoint.
2. Connect transport.
3. Negotiate protocol/security profile.
4. Pair or authenticate local device trust.
5. Fetch DeviceCapabilities.
6. Fetch full PrismaState snapshot.
7. Fetch MediaEndpoint list.
8. Reset local generation cursor to snapshot generation.
9. Subscribe to event stream.
10. Enter READY.
```

A later optimization may overlap independent steps after protocol/security negotiation, but observable semantics remain the same.

## 7. Generation synchronization

The session tracks the appliance `generation`.

For an incoming authoritative event:

```text
incoming <= current     → stale/duplicate: ignore
incoming == current + 1 → accept
incoming > current + 1  → gap: mark STALE and fetch a full snapshot
```

The first implementation intentionally re-fetches the full authoritative snapshot after accepted state events until typed event reducers are frozen and comprehensively tested. Correctness takes precedence over premature delta optimization.

Later optimization may apply typed patches locally only when:

- event schema is versioned;
- reducer is deterministic;
- full-snapshot reconciliation remains available;
- test vectors prove equivalence.

## 8. Control vs media failure domains

Control and media are separate lifecycles.

A preview stream failure must not automatically destroy an authenticated control session. The app should attempt media renegotiation while keeping command/control alive.

Likewise a control reconnect requires a fresh state snapshot and media endpoint renegotiation even if a media transport appears to remain open.

## 9. Reconnection policy

Production connector adapters should implement bounded exponential reconnect with jitter and explicit terminal/auth states.

Recommended conceptual policy:

```text
immediate first retry
short retries: 0.5s, 1s, 2s
then bounded backoff up to ~10s
reset backoff after a stable session
```

Exact timing is adapter/configuration policy, not Core product semantics.

On successful reconnect:

1. re-establish transport;
2. re-authenticate stored local trust;
3. fetch capabilities when capability digest changed or session policy requires;
4. fetch full state;
5. reset generation cursor;
6. re-subscribe events;
7. renegotiate media endpoints;
8. return READY.

## 10. Account-cloud independence

`PrismaSessionManager` must not require Google/Apple/PRISMA cloud access to control an already paired local appliance.

Cloud account identity and appliance trust are deliberately separate:

```text
PRISMA cloud session ── licenses/account

Local appliance session ── control/media/pairing
```

A cloud outage may affect entitlement refresh according to offline-license policy, but does not invalidate a local transport trust session by itself.

## 11. Legacy ESP32 adapter

The legacy adapter may poll `/api/state` and map `/source/...` preview behavior internally. These mechanisms must stop at the adapter boundary.

The rest of the application sees the same:

- `DeviceDescriptor`;
- `DeviceCapabilities`;
- `PrismaState`;
- command interface;
- normalized session lifecycle;
- `MediaEndpoint` abstraction.

Legacy missing capabilities are explicit, never simulated silently.

## 12. Current implementation status

The repository now contains:

```text
packages/prisma_connector/
├── connector contract
├── session manager
├── deterministic MockPrismaConnector
└── integration tests
```

Current test coverage includes:

- bootstrap to READY;
- capability/state/media acquisition;
- command → event → authoritative resynchronization;
- generation conflict behavior;
- generation gap recovery.

## 13. Next implementation increments

Before production UI:

1. add explicit reconnect scheduler and transport-loss fault injection;
2. add typed Protocol 2.0 response/error objects instead of raw maps;
3. add pairing/trust adapter boundary;
4. implement LAN discovery adapter;
5. implement WebSocket Protocol 2.0 connector against Mock Appliance server;
6. implement Legacy ESP32 connector;
7. add media-channel lifecycle abstraction;
8. physically validate legacy connector against protected ESP32 baseline.
