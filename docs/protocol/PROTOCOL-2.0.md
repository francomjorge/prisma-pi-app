# PRISMA-PI Protocol 2.0

**Status:** Draft / DESIGNED  
**Scope:** Mobile controller ↔ PRISMA appliance interoperability

## 1. Goals

Protocol 2.0 is transport-neutral and covers discovery, capability negotiation, pairing/authentication, state synchronization, commands, file operations, preview/media negotiation, health and diagnostics.

It replaces short-interval polling as the preferred synchronization model while preserving a compatibility adapter for current appliances.

## 2. Channel separation

```text
DISCOVERY CHANNEL   device presence and bootstrap metadata
CONTROL CHANNEL     request/response commands and queries
EVENT CHANNEL       persistent live state/status events
MEDIA CHANNEL       preview/program media negotiated by capability
```

File transfer may use a dedicated transfer endpoint for efficiency but remains part of the File Service contract.

## 3. Versioning

Every session starts with protocol negotiation.

```json
{"protocol":{"family":"PRISMA","major":2,"minor":0}}
```

Rules:

- incompatible `major` versions require an explicit compatibility adapter;
- newer `minor` versions may add optional fields/capabilities;
- unknown optional fields are ignored;
- unsupported required capabilities fail explicitly.

## 4. Device descriptor

```json
{
  "device_id":"stable-id",
  "display_name":"PRISMA Device",
  "model":"implementation-defined",
  "firmware_version":"x.y",
  "protocol":{"major":2,"minor":0},
  "pairing_required":true,
  "security_profiles":["PROFILE_ID"],
  "capability_digest":"opaque-digest"
}
```

`device_id` remains stable across normal reboots and updates.

## 5. Discovery

Preferred LAN discovery uses mDNS/DNS-SD where supported.

Logical service family:

```text
_prisma-pi._tcp
```

Discovery data may expose host, control port, device ID, protocol version, pairing requirement and capability digest. Discovery grants no authorization.

Manual host/IP entry remains a diagnostic fallback.

## 6. Session bootstrap

```text
Client                         Device
  |---- discover -------------->|
  |<--- descriptor -------------|
  |---- connect --------------->|
  |<--- protocol/security ------|
  |---- pair/authenticate ----->|
  |<--- session accepted -------|
  |---- capabilities ---------->|
  |<--- capability profile -----|
  |---- full state ------------>|
  |<--- PrismaState ------------|
  |---- event subscribe ------->|
  |<=== live events ============|
```

Reconnect reuses valid trust material. Revoked trust returns a pairing-required/authentication failure.

## 7. Security profile abstraction

```text
SecurityProfile
├── id
├── transport_security
├── pairing_method
├── client_authentication
├── session_authentication
└── replay_protection
```

Production profiles require authenticated sessions and protected credentials in transit.

`LEGACY_UNAUTHENTICATED` is allowed only as an explicitly marked development/compatibility profile and must never be silently preferred over a secure profile.

## 8. Control request envelope

```json
{
  "request_id":"uuid",
  "type":"COMMAND_OR_QUERY",
  "device_id":"target-device-id",
  "client_id":"controller-client-id",
  "timestamp_ms":0,
  "expected_generation":123,
  "payload":{}
}
```

`expected_generation` is optional and supports optimistic concurrency.

## 9. Control response envelope

Success:

```json
{
  "request_id":"uuid",
  "ok":true,
  "generation":124,
  "result":{},
  "error":null
}
```

Failure:

```json
{
  "request_id":"uuid",
  "ok":false,
  "generation":124,
  "result":null,
  "error":{
    "code":"GENERATION_CONFLICT",
    "message":"diagnostic",
    "retryable":true,
    "details":{}
  }
}
```

## 10. Initial queries

```text
GET_DEVICE_INFO
GET_CAPABILITIES
GET_STATE
GET_SETTINGS
GET_STATUS
GET_MEDIA_ENDPOINTS
GET_FILE_CAPABILITIES
GET_DIAGNOSTICS_SUMMARY
```

## 11. Initial command families

```text
SET_POWER
SET_MODE
SET_INTENSITY
SELECT_SOURCE
NEXT_SOURCE
SET_CORE_EFFECT
SET_CORE_EFFECT_ENABLED
RANDOMIZE
MODULE_ENABLE
MODULE_BYPASS
MODULE_SET_PARAMETER
SET_PROCESSING_GRAPH
SET_OUTPUT_ROUTE
SET_LOOP
SET_SETTING
RESET_SETTINGS
```

Transport serialization is derived from authoritative command schemas rather than inventing transport-specific mutations.

## 12. Event channel

Preferred IP implementation: persistent full-duplex/event transport such as WebSocket.

```json
{
  "event_id":"opaque-id",
  "type":"STATE_CHANGED",
  "device_id":"device-id",
  "generation":125,
  "timestamp_ms":0,
  "payload":{}
}
```

Initial event families:

```text
STATE_CHANGED
SOURCE_CHANGED
EFFECT_STATE_CHANGED
PROCESSING_GRAPH_CHANGED
MODULE_STATE_CHANGED
OUTPUT_STATE_CHANGED
SETTINGS_CHANGED
CAPABILITIES_CHANGED
STATUS_CHANGED
MEDIA_ENDPOINT_CHANGED
FILE_LIBRARY_CHANGED
FAULT_RAISED
FAULT_CLEARED
SESSION_EXPIRING
```

## 13. Synchronization

Client algorithm:

```text
1. Connect/authenticate.
2. Read full state + generation G.
3. Subscribe to events.
4. Apply ordered compatible events.
5. If a generation gap is detected, fetch a fresh full state.
6. Never fabricate missing authoritative intermediate state.
```

Optimistic UI must always reconcile with authoritative response/event state.

## 14. Reconnect behavior

On disconnect:

- retain local presentation/navigation state;
- mark remote state stale;
- stop issuing commands requiring a live session;
- attempt bounded reconnect;
- re-authenticate;
- fetch a fresh state snapshot;
- resume event subscription;
- renegotiate media endpoints;
- reconcile generation.

Media failure does not automatically invalidate the control session.

## 15. Capability model

Capabilities are structured and may contain limits, not only booleans.

Examples:

```text
control.commands
control.events
control.expected_generation
network.discovery.mdns
network.transport.websocket
security.pairing
security.session_auth
files.list
files.upload
files.download
files.delete
preview.source
preview.processed
preview.transports[]
program.stream
media.image
media.video
media.video_audio
processing.graph
processing.execution_targets[]
```

## 16. Media endpoint negotiation

Media bytes do not travel inside normal state events.

```json
{
  "purpose":"PROCESSED_PREVIEW",
  "transport":"mjpeg",
  "codec_or_format":"jpeg",
  "width":640,
  "height":480,
  "fps":12,
  "audio":false,
  "latency_class":"interactive-preview",
  "session_descriptor":{}
}
```

The app selects an advertised endpoint according to purpose, latency, quality and platform support.

## 17. File service

```text
LIST_ASSETS
GET_ASSET_METADATA
UPLOAD_ASSET
DOWNLOAD_ASSET
DELETE_ASSET
RENAME_ASSET_METADATA
```

Rules:

- asset identity is logical, not a filesystem path;
- uploads are integrity-validated before publication;
- partial uploads are never selectable assets;
- device storage/file limits are capabilities.

## 18. Common error codes

```text
UNSUPPORTED_PROTOCOL
UNSUPPORTED_CAPABILITY
PAIRING_REQUIRED
AUTHENTICATION_FAILED
AUTHORIZATION_FAILED
SESSION_EXPIRED
INVALID_REQUEST
INVALID_COMMAND
INVALID_PARAMETER
GENERATION_CONFLICT
DEVICE_BUSY
RESOURCE_EXHAUSTED
STORAGE_FULL
ASSET_NOT_FOUND
MEDIA_ENDPOINT_UNAVAILABLE
TRANSFER_FAILED
INTERNAL_ERROR
```

Errors distinguish unsupported, unavailable, unauthorized and transient conditions.

## 19. Legacy compatibility

Current ESP32-S3 behavior such as `/api/state` polling and `/source/<filename>` is implemented only behind `LegacyEsp32Connector`.

That adapter maps legacy snapshots into the app's modern internal model while declaring unavailable capabilities explicitly.

Legacy paths and polling assumptions must never leak into feature or UI code.

## 20. Validation gate

Protocol 2.0 is not IMPLEMENTED until a reference app client and Mock Appliance pass:

- protocol negotiation;
- capability negotiation;
- full-state synchronization;
- command/response correlation;
- generation conflict behavior;
- disconnect/reconnect;
- event-gap recovery;
- media endpoint negotiation;
- file integrity failure handling;
- production pairing/authentication tests.
