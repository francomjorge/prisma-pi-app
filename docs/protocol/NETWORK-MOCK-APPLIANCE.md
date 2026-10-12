# PRISMA Protocol 2.0 — Network Mock Appliance

**Status:** IMPLEMENTED / validation pending CI  
**Purpose:** exercise the same HTTP + WebSocket control path that the Android app will use over LAN/Wi-Fi before a physical appliance implements Protocol 2.0.

## Why this exists

The in-memory Mock Appliance validates domain/session behavior but does not validate sockets, JSON transport, HTTP failures, WebSocket event delivery or network reconnect behavior. The network Mock Appliance adds that transport boundary without modifying the stable ESP32 firmware.

## Runtime topology

```text
PrismaSessionManager
        |
Protocol2LanConnector
        |
   HTTP + WebSocket
        |
PrismaMockApplianceServer
        |
MockPrismaConnector
        |
 authoritative PrismaState
```

This preserves the same product contracts on both sides of the transport.

## Control endpoints

Reference endpoints implemented by the mock server:

```text
GET  /healthz
GET  /v2/device
POST /v2/auth/session
GET  /v2/capabilities
GET  /v2/state
GET  /v2/media/endpoints
POST /v2/commands
POST /v2/request
WS   /v2/events
```

All endpoints except `/healthz`, `/v2/device` and `/v2/auth/session` require an appliance session token in the current reference implementation.

The development token used by the Mock Appliance is deliberately not a production security profile. Production pairing, credential rotation and TLS remain separate gates.

## Session sequence

```text
DISCOVERY RECORD
  -> GET /v2/device
  -> POST /v2/auth/session
  -> open WS /v2/events
  -> GET /v2/capabilities
  -> GET /v2/state
  -> GET /v2/media/endpoints
  -> READY
```

The WebSocket is established before the session is considered ready. This prevents a command-generated state event from being lost between bootstrap and subscription.

## State synchronization

`generation` remains authoritative.

- stale/duplicate event: ignore;
- next sequential event: accept and refresh authoritative snapshot;
- generation gap: mark session stale and force a new state/media snapshot;
- socket error/closure: connector becomes degraded and the session can enter recovery logic.

The current session runtime deliberately re-reads the authoritative snapshot after events. Typed reducers are an optimization to introduce only after event schemas are frozen.

## Media negotiation

`GET /v2/media/endpoints` returns typed endpoints for:

- `SOURCE_PREVIEW`;
- `PROCESSED_PREVIEW`;
- later `PROGRAM_OUTPUT` when advertised.

The mock currently advertises a synthetic `mock-frames` transport. Real appliances will advertise transports through capabilities; the app must not hardcode ESP32-specific media behavior into product code.

## Running locally

From `packages/prisma_mock_appliance`:

```bash
dart pub get
dart run bin/server.dart
```

Default port: `8791`.

An alternate port can be passed as the first argument:

```bash
dart run bin/server.dart 9008
```

For LAN tests on a development machine the server binds to all IPv4 interfaces. Automated tests bind to loopback on an ephemeral port.

## Automated integration coverage

The network integration suite validates:

1. seed discovery record;
2. device identity bootstrap;
3. appliance session creation;
4. capabilities/state/media decoding;
5. HTTP command submission;
6. WebSocket event delivery;
7. generation advancement;
8. injected generation-gap recovery;
9. authenticated generic request envelopes.

## Discovery boundary

`Protocol2LanConnector` currently receives discovery records through injected seeds. This is intentional: mDNS/DNS-SD is a platform discovery adapter and must not be coupled to the Protocol 2.0 transport client.

Android later supplies records through NSD/mDNS discovery; USB and legacy adapters can supply the same `DiscoveryRecord` shape.

## Security boundary

The Protocol 2.0 appliance session is not the PRISMA cloud account session.

Never send Google, Apple or PRISMA cloud access/refresh tokens to an appliance. Local appliance pairing establishes a distinct trust credential.

## Next extensions

Before physical Protocol 2.0 integration:

- explicit reconnect/backoff policy;
- event socket re-establishment;
- latency/timeouts and cancellation;
- malformed JSON/schema fault injection;
- command timeout and duplicate command-id behavior;
- media endpoint change/re-negotiation tests;
- mDNS discovery adapter;
- TLS/pairing security profile;
- legacy ESP32 adapter mapped into the same connector interface.
