# PRISMA-PI App Project Status

Status vocabulary:

```text
DESIGNED
IMPLEMENTED
BUILT
STATICALLY_VERIFIED
RUNTIME_VERIFIED
HARDWARE_TESTED
BASELINE
```

A later status includes evidence from previous stages only when that evidence actually exists. A design is not implementation; a successful build is not physical validation.

## Current subsystem status

| Subsystem | Status | Notes |
|---|---|---|
| Repository baseline | IMPLEMENTED | App repository initialized; active work is isolated in `infra-foundation`. |
| Mobile architecture | DESIGNED | Foundation contract documented; review/freeze pending. |
| Mobile stack ADR | DESIGNED | Flutter + native boundary remains PROPOSED until M0 real-device validation. |
| Platform-neutral domain package | STATICALLY_VERIFIED_BASELINE | State, protocol, devices, processing graph, account and entitlement contracts have a recorded green CI baseline; later branch changes still pass through the current gate. |
| Protocol 2.0 | PARTIAL_IMPLEMENTATION | Reference HTTP + WebSocket client/server path, media endpoints, events, timeouts, command idempotency and reconnect behavior implemented; production security and hardware adapter remain pending. |
| Connector abstraction | IMPLEMENTED | `prisma_connector` defines transport-neutral discovery/control/event/session contracts plus a transport-neutral failure model. |
| Protocol 2.0 LAN connector | IMPLEMENTED | HTTP control + WebSocket events, typed HTTP/transport failures and request/event-connect timeouts implemented. |
| Remote session manager | IMPLEMENTED | Bootstrap, authoritative snapshot mirror, command gate, generation recovery and bounded automatic reconnect implemented. |
| Reconnect/backoff | IMPLEMENTED | Bounded exponential policy plus explicit `reconnectNow()` and deterministic test policy. |
| Command idempotency reference | IMPLEMENTED | Reference mock caches exact `command_id` retransmissions and rejects divergent reuse with `COMMAND_ID_REUSE`. |
| In-memory Mock Appliance | IMPLEMENTED | Deterministic connector supports commands, generation gaps and event-channel failure injection. |
| Network Mock Appliance | IMPLEMENTED | HTTP/WebSocket server supports forced WS disconnect, one-shot HTTP faults, latency and timeout test scenarios. |
| Discovery coordinator | IMPLEMENTED | Multiple discovery providers merge into stable `DiscoveryRecord` observations with duplicate suppression and endpoint/capability-change emission. |
| Android NSD/mDNS adapter | SPIKE_COMPILES | Kotlin `NsdManager` diagnostic bridge emits `_prisma-pi._tcp` observations through Flutter EventChannel; real-device/local-network-permission validation not performed. |
| Legacy ESP32 connector | IMPLEMENTED_PENDING_CURRENT_CI | Read-only adapter maps protected `/api/state` and `/source/*` behavior into `PrismaState`, capabilities, polling events and JPEG MediaEndpoint without changing firmware. Physical appliance validation still pending. |
| Legacy appliance security | COMPATIBILITY_ONLY | Current ESP32-S3 open SoftAP/plain HTTP baseline is explicitly `LEGACY_UNAUTHENTICATED`, never silently preferred. |
| Managed storage architecture | DESIGNED | Durable layout, SQLite target, projects, recordings, cache, migrations and reference rules documented. |
| Managed storage runtime | IMPLEMENTED_PENDING_CURRENT_CI | `prisma_storage` implements managed layout, transactional staged import, SHA-256, image/video validation boundary, rollback and startup recovery scan. |
| SQLite metadata adapter | NOT_STARTED | Repository boundary exists; durable SQLite implementation and migrations still pending. |
| Android file/content URI adapter | NOT_STARTED | Import stream abstraction exists; platform picker/content resolver adapter pending. |
| Cloud account identity | DESIGNED + PARTIAL_IMPLEMENTATION | Provider-independent account/domain model implemented; Google production flow/backend not implemented. |
| Google Android sign-in | DESIGNED | Credential Manager / Sign in with Google selected as preferred Android path; production OAuth configuration intentionally not frozen during M0. |
| iOS identity provider | DESIGNED | Sign in with Apple reserved as equivalent provider for the iOS target. |
| PRISMA account backend | DESIGNED | API trust boundary and logical account/session/entitlement/purchase data model defined; hosting/vendor still open. |
| Licensing/entitlements | DESIGNED + PARTIAL_IMPLEMENTATION | Normalized entitlement model implemented; signed offline snapshot/backend verification still pending. |
| Offline license continuity | DESIGNED | Internet loss must not stop an active performance; exact freshness/grace policy pending. |
| Store purchase abstraction | DESIGNED | Store SDK behavior must normalize through backend-verified entitlements. |
| Privacy/account deletion | DESIGNED | Local media remains local by default; deletion/retention contract still to implement. |
| Appliance security/pairing contract | IMPLEMENTED | `prisma_security` defines trust states, profile policy, credential references, secure-store and pairing-client boundaries. |
| Android secure credential adapter | SPIKE_COMPILES_PENDING_CURRENT_CI | M0 Keystore bridge uses non-exportable AndroidKeyStore AES-GCM key with encrypted private-app-storage blob; physical runtime/restart tests pending. |
| Appliance production security profile | PROPOSED | ADR-003 proposes protocomm Security 2 for first pairing and pinned TLS/authenticated short-lived sessions for normal control; hardware measurement required before acceptance. |
| Account vs appliance trust separation | DESIGNED | Cloud identity and local appliance pairing are separate trust domains. |
| Local image decode | NOT_STARTED | Required before production UI. |
| Local looping video decode | NOT_STARTED | Required before production UI. |
| Media endpoint negotiation | PARTIAL_IMPLEMENTATION | Endpoint model, Protocol 2.0 decode and session acquisition implemented; platform media transport selection/runtime pending. |
| Processing graph | IMPLEMENTED_CONTRACT | Ordered node model exists in domain package; processor runtime not implemented. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | PARTIAL_IMPLEMENTATION | M0 spike includes keyboard/native bridge diagnostics; product action layer pending. |
| Android app shell | SPIKE_ONLY | Diagnostic M0 shell exists; production UI intentionally blocked. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build; account/auth configuration will then use final package/signing identities. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Validation evidence

A full foundation gate was green at commit:

```text
156efa93d48805f1efcf8a4bfde3dba9e800898d
foundation-validation run #138 / 38215256850
```

That evidence covers domain, security contracts, connector/session, network Protocol 2.0 and the Android M0 build as they existed at that commit. It is recorded in `docs/validation/FOUNDATION-CI-EVIDENCE.md`.

The branch has since added Android Keystore diagnostics, the Legacy ESP32 adapter and the managed-storage runtime. The current six-job gate must complete successfully before those newer increments are promoted to `STATICALLY_VERIFIED`.

CI concurrency cancels obsolete in-progress PR runs so only the newest revision matters.

## Next coherent work packages

1. make the current six-way CI gate green: domain, security, storage, connector/legacy, network Protocol 2.0 and Android M0;
2. run Android M0 on a physical device and validate `NsdManager`, local-network permission behavior, Keystore round-trip/restart, keyboard input and native boundary;
3. physically validate `LegacyEsp32Connector` against the protected ESP32-S3 firmware without modifying that firmware;
4. implement SQLite metadata repository + migrations and Android content-URI import adapter;
5. implement native image/video media metadata/decode spike;
6. build a disposable ESP32-S3 pairing/security spike on ESP-IDF 5.5.1 without modifying the protected firmware baseline;
7. measure protocomm Security 2 + HTTPS/WSS flash/RAM/latency costs and validate revoke/replay/fingerprint-failure behavior;
8. implement account backend API skeleton and signed offline-entitlement proof;
9. validate Google login with non-production OAuth only after final-enough package/signing identity exists;
10. only then begin production UI composition.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- cloud account work must not be used as a reason to rewrite local appliance trust;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
