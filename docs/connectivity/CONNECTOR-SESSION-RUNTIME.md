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
 ├─ transport loss               → RECONNECTING → AUTHENTICATING → SYNCHRONIZING → READY
 ├─ retry budget exhausted       → FAILED
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

`PrismaSessionManager` now owns a transport-independent bounded exponential reconnect policy. The current default is:

```text
attempt 1   1s
attempt 2   2s
attempt 3   4s
attempt 4   8s
attempt 5+  capped at 16s
retry budget: 8 attempts
```

The policy is injectable, so deterministic tests use millisecond delays while product builds use conservative timings. A successful session resets the attempt counter.

A WebSocket/event-channel failure, failed authoritative resync or equivalent control-plane loss moves the session out of `READY`, schedules reconnect and blocks new commands until synchronization succeeds.

On reconnect the runtime:

1. preserves the last snapshot only as stale local context;
2. cancels the failed event subscription;
3. tears down the connector transport best-effort;
4. reconnects to the same discovered device identity;
5. re-authenticates local appliance trust;
6. re-fetches capabilities;
7. fetches full authoritative state;
8. resets the generation cursor;
9. fetches media endpoints again;
10. subscribes a fresh event channel;
11. returns to `READY`.

`reconnectNow()` exists for explicit user retry and deterministic testing. It bypasses the current backoff delay but does not bypass authentication or synchronization.

## 10. Transport timeouts and errors

`Protocol2LanConnector` now applies explicit timeouts to HTTP operations and the event WebSocket bootstrap. Socket and timeout failures are normalized as `Protocol2TransportException` with a `retryable` flag.

HTTP/application failures remain `Protocol2HttpException`, preserving:

```text
statusCode
code
message
retryable
```

This distinction matters because a generation conflict, authentication rejection and network timeout require different recovery behavior.

Default reference timeouts are currently 5 seconds for HTTP and 5 seconds for WebSocket establishment. These are adapter defaults, not Core semantics, and can be tuned after Android/Wi-Fi measurements.

## 11. Account-cloud independence

`PrismaSessionManager` must not require Google/Apple/PRISMA cloud access to control an already paired local appliance.

Cloud account identity and appliance trust are deliberately separate:

```text
PRISMA cloud session ── licenses/account

Local appliance session ── control/media/pairing
```

A cloud outage may affect entitlement refresh according to offline-license policy, but does not invalidate a local transport trust session by itself.

## 12. Legacy ESP32 adapter

The legacy adapter may poll `/api/state` and map `/source/...` preview behavior internally. These mechanisms must stop at the adapter boundary.

The rest of the application sees the same:

- `DeviceDescriptor`;
- `DeviceCapabilities`;
- `PrismaState`;
- command interface;
- normalized session lifecycle;
- `MediaEndpoint` abstraction.

Legacy missing capabilities are explicit, never simulated silently.

## 13. Current implementation status

The repository now contains:

```text
packages/prisma_connector/
├── connector contract
├── session manager
├── bounded reconnect/backoff policy
├── deterministic MockPrismaConnector
├── Protocol2LanConnector (HTTP + WebSocket)
├── typed HTTP/transport exceptions
└── unit/integration tests

packages/prisma_mock_appliance/
├── real loopback HTTP server
├── authenticated Protocol 2.0 endpoints
├── WebSocket event channel
└── deterministic fault injection
```

Current test coverage includes:

- bootstrap to READY;
- capability/state/media acquisition;
- command → event → authoritative resynchronization;
- generation conflict behavior;
- generation gap recovery;
- in-memory event-channel failure and automatic reconnect;
- real WebSocket disconnect and session recovery;
- command/event flow after reconnect;
- retryable HTTP fault propagation;
- artificial response latency;
- request timeout normalization.

## 14. Next implementation increments

Before production UI:

1. add reconnect jitter and stable-session reset metrics after mobile measurements;
2. replace remaining raw Protocol 2.0 response maps with typed envelopes/results;
3. add pairing/trust adapter boundary;
4. implement LAN discovery adapter (Android NSD / mDNS-DNS-SD);
5. implement full server-down / same-endpoint restart fault tests;
6. implement Legacy ESP32 connector;
7. add media-channel lifecycle abstraction;
8. physically validate legacy connector against protected ESP32 baseline.
