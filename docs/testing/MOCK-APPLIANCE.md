# PRISMA-PI Mock Appliance

**Status:** Networked deterministic implementation  
**Date:** 2026-10-12

## 1. Purpose

The Mock Appliance is the reference non-hardware target for the mobile controller. It lets protocol/session/storage/media work be tested without changing or depending on the physically validated ESP32 firmware.

It is not a visual simulator. It is a deterministic behavioral test double for the appliance contract.

## 2. Required behaviors

The Mock Appliance must eventually cover:

- discovery descriptor;
- Protocol 2.0 version negotiation;
- local trust/authentication states;
- capabilities;
- full state snapshots;
- command validation;
- optimistic generation conflicts;
- event publication;
- deliberate event gaps;
- disconnect/reconnect;
- capability changes;
- media endpoint changes;
- file library operations;
- transfer failures and integrity failures;
- device-busy/resource-exhausted failures;
- fault raised/cleared events.

## 3. Current implementations

PRISMA now has two complementary mock layers.

### In-memory Mock Connector

`MockPrismaConnector` provides fast deterministic Dart tests with no sockets:

```text
device_id         stable deterministic UUID
protocol          PRISMA 2.0
control events    yes
expected gen      yes
media image       yes
media video       yes
preview source    yes
preview processed yes
processing graph  advertised
mock media        RGBA frame endpoint descriptors
```

Initial command set:

```text
SET_POWER
SET_INTENSITY
SET_MODE
```

### Network Protocol Mock Server

`PrismaMockApplianceServer` exposes a real loopback HTTP/WebSocket Protocol 2.0 target:

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

It deliberately uses a development-only mock session token. It is not the production pairing/security mechanism.

## 4. Fault injection

Current deterministic hooks now include:

```text
In-memory:
injectEventChannelFailure()
injectGenerationGap()
injectMediaEndpointChange()

Network server:
disconnectEventClients()
setResponseLatency(duration)
failNextRequest(path, status/code/retryable)
injectGenerationGap()
injectMediaEndpointChange()
```

These hooks let tests reproduce failures without random sleeps or destructive hardware experiments.

Planned hooks:

```text
stopAcceptingConnections()
restoreSameEndpoint()
expireTrust()
changeCapabilityDigest()
rejectNextCommand(code)
corruptNextTransfer()
fillStorage(percent)
raiseFault(code)
clearFault(code)
```

Fault injection must remain explicit and deterministic.

## 5. Test matrix

Minimum pre-UI matrix:

| Scenario | Expected client behavior | Current |
|---|---|---|
| clean connect | READY with descriptor/capabilities/state/media | implemented |
| valid command | generation increments and state reconciles | implemented |
| stale command generation | explicit `GENERATION_CONFLICT` | implemented |
| duplicate event | ignored | domain behavior implemented |
| event generation gap | mark stale and full resync | implemented |
| event WebSocket loss | RECONNECTING then fresh READY | implemented |
| command after reconnect | control/event flow continues | implemented |
| transient HTTP failure | typed retryable error | implemented |
| response latency | protocol remains correct | implemented |
| request timeout | typed retryable transport error | implemented |
| complete server outage | bounded reconnect until endpoint returns | pending |
| media-only loss | control stays READY, media renegotiates | pending |
| trust revoked | pairing/auth required, no silent fallback | pending |
| capability digest changes | capabilities refreshed | pending |
| unsupported media endpoint | choose next compatible endpoint | pending |
| corrupt file upload | no published asset | pending |
| storage full | explicit `STORAGE_FULL` | pending |

## 6. Why both mock layers remain necessary

The in-memory connector is optimized for fast logic tests. The network server is optimized for serialization, sockets, HTTP, WebSocket, timeout and reconnect behavior.

Both use the same domain contracts and must converge on the same state transitions. A feature is not considered network-ready merely because the in-memory mock passes.

## 7. Protected hardware boundary

The Mock Appliance is specifically intended to absorb experimentation that must **not** be performed against the current protected ESP32 baseline.

Only after behavior passes deterministic mock tests should the equivalent physical adapter be implemented and physically validated.
