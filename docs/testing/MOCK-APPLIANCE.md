# PRISMA-PI Mock Appliance

**Status:** Initial deterministic implementation  
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

## 3. Current in-memory implementation

`MockPrismaConnector` currently provides:

```text
device_id        stable deterministic UUID
protocol         PRISMA 2.0
control events   yes
expected gen     yes
media image      yes
media video      yes
preview source   yes
preview processed yes
processing graph advertised
mock media       RGBA frame endpoint descriptors
```

The initial command set is intentionally small:

```text
SET_POWER
SET_INTENSITY
SET_MODE
```

This is enough to prove session synchronization before expanding the command matrix.

## 4. Fault injection

Current hooks:

```text
injectGenerationGap()
injectMediaEndpointChange()
```

Planned hooks:

```text
dropControlTransport()
restoreControlTransport()
expireTrust()
changeCapabilityDigest()
rejectNextCommand(code)
delayNextResponse(duration)
corruptNextTransfer()
fillStorage(percent)
raiseFault(code)
clearFault(code)
```

Fault injection must be explicit and deterministic so integration tests do not depend on random timing.

## 5. Test matrix

Minimum pre-UI matrix:

| Scenario | Expected client behavior |
|---|---|
| clean connect | READY with descriptor/capabilities/state/media |
| valid command | generation increments and state reconciles |
| stale command generation | explicit `GENERATION_CONFLICT` |
| duplicate event | ignored |
| event generation gap | mark stale and full resync |
| control transport loss | remote state stale, reconnect attempts |
| media-only loss | control stays READY, media renegotiates |
| trust revoked | pairing/auth required, no silent fallback |
| capability digest changes | capabilities refreshed |
| unsupported media endpoint | choose next compatible endpoint |
| corrupt file upload | no published asset |
| storage full | explicit `STORAGE_FULL` |

## 6. Two mock layers

PRISMA should maintain two complementary test doubles:

### In-memory Mock Connector

Fast Dart unit/integration tests. No sockets, no HTTP, no timing dependency.

### Protocol Mock Server

A later standalone process exposing real HTTP/WebSocket/transfer endpoints. Used to validate the network connector, serialization, reconnect behavior and Android local-network behavior.

Both must use the same canonical test fixtures and expected state transitions.

## 7. Protected hardware boundary

The Mock Appliance is specifically intended to absorb experimentation that must **not** be performed against the current protected ESP32 baseline.

Only after a behavior passes deterministic mock tests should the equivalent physical adapter be implemented and physically validated.
