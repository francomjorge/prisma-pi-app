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
| Platform-neutral domain package | STATICALLY_VERIFIED | State, protocol, devices, processing graph, account and entitlement contracts pass the recorded foundation gate. |
| Protocol 2.0 | PARTIAL_IMPLEMENTATION | Reference HTTP + WebSocket client/server path, media endpoints, events, timeouts, command idempotency and reconnect behavior implemented; production security and hardware adapter remain pending. |
| Connector abstraction | STATICALLY_VERIFIED | `prisma_connector` defines transport-neutral discovery/control/event/session contracts plus transport-neutral failure behavior. |
| Protocol 2.0 LAN connector | RUNTIME_VERIFIED | HTTP control + WebSocket events, failures and timeouts execute against the loopback network Mock Appliance. Hardware/Wi-Fi validation pending. |
| Remote session manager | RUNTIME_VERIFIED | Bootstrap, authoritative snapshot mirror, command gate, generation recovery and automatic reconnect execute in deterministic integration tests. |
| Reconnect/backoff | RUNTIME_VERIFIED | Bounded exponential policy and `reconnectNow()` tested through in-memory and real WebSocket disconnect paths. |
| Command idempotency reference | RUNTIME_VERIFIED | Exact `command_id` retransmission is non-mutating; divergent reuse fails with `COMMAND_ID_REUSE`. |
| In-memory Mock Appliance | RUNTIME_VERIFIED | Deterministic connector executes command, generation-gap and event-channel fault scenarios. |
| Network Mock Appliance | RUNTIME_VERIFIED | Real loopback HTTP/WebSocket server executes disconnect, transient HTTP failure, latency and timeout scenarios. |
| Discovery coordinator | STATICALLY_VERIFIED | Provider merge/dedup and endpoint/capability-change behavior pass tests. |
| Android NSD/mDNS adapter | BUILT | Kotlin `NsdManager` diagnostic bridge compiles into the debug Android APK; physical-device/local-network-permission behavior remains unverified. |
| Legacy ESP32 connector | STATICALLY_VERIFIED | Adapter tests match protected `/api/state` schema, capability limitations, polling reconciliation and JPEG MediaEndpoint. Physical appliance validation pending. |
| Legacy appliance security | COMPATIBILITY_ONLY | Current ESP32-S3 open SoftAP/plain HTTP baseline is explicitly `LEGACY_UNAUTHENTICATED`, never silently preferred. |
| Managed storage architecture | DESIGNED | Durable layout, SQLite target, projects, recordings, cache, migrations and reference rules documented. |
| Managed storage runtime | RUNTIME_VERIFIED | Managed layout, staged image/video import, SHA-256, validation, rollback and startup recovery execute against temporary filesystems in CI. |
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
| Appliance security/pairing contract | STATICALLY_VERIFIED | `prisma_security` trust/profile/credential/secure-store interfaces and fail-closed profile policy pass CI. |
| Android secure credential adapter | BUILT | M0 Keystore bridge compiles into the Android APK using AndroidKeyStore AES-GCM + encrypted private-app-storage blob. Runtime/restart/revoke tests on a phone remain pending. |
| Appliance production security profile | PROPOSED | ADR-003 proposes protocomm Security 2 for first pairing and pinned TLS/authenticated short-lived sessions for normal control; hardware measurement required before acceptance. |
| Account vs appliance trust separation | DESIGNED | Cloud identity and local appliance pairing are separate trust domains. |
| Local image decode | NOT_STARTED | Required before production UI. |
| Local looping video decode | NOT_STARTED | Required before production UI. |
| Media endpoint negotiation | PARTIAL_IMPLEMENTATION | Endpoint model, Protocol 2.0 decode and session acquisition implemented; platform media transport selection/runtime pending. |
| Processing graph | IMPLEMENTED_CONTRACT | Ordered node model exists in domain package; processor runtime not implemented. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | PARTIAL_IMPLEMENTATION | M0 spike includes keyboard/native bridge diagnostics; product action layer pending. |
| Android app shell | BUILT_SPIKE | Diagnostic M0 Flutter/Kotlin shell builds as debug APK; product UI remains blocked. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build; account/auth configuration will then use final package/signing identities. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Validation evidence

Latest expanded green gate:

```text
e6f2bdd6b816909d61cd0c3a72686526aeb7a580
foundation-validation run #161 / 38216669784
```

All six jobs passed:

```text
domain
security-contracts
storage-runtime
connector-session
network-protocol-integration
android-stack-spike
```

The complete scope and limitations of this evidence are recorded in `docs/validation/FOUNDATION-CI-EVIDENCE.md`.

This is not physical Android or ESP32 evidence. In particular, Android NSD/Keystore behavior and the Legacy ESP32 connector still require target-hardware validation.

CI concurrency cancels obsolete in-progress PR runs so only the newest revision matters.

## Next coherent work packages

1. run Android M0 on a physical device and validate `NsdManager`, local-network permission behavior, Keystore round-trip/restart, keyboard input and native boundary;
2. physically validate `LegacyEsp32Connector` against the protected ESP32-S3 firmware without modifying that firmware;
3. implement SQLite metadata repository + migrations and Android content-URI import adapter;
4. implement native image/video media metadata/decode spike;
5. build a disposable ESP32-S3 pairing/security spike on ESP-IDF 5.5.1 without modifying the protected firmware baseline;
6. measure protocomm Security 2 + HTTPS/WSS flash/RAM/latency costs and validate revoke/replay/fingerprint-failure behavior;
7. implement account backend API skeleton and signed offline-entitlement proof;
8. validate Google login with non-production OAuth only after final-enough package/signing identity exists;
9. only then begin production UI composition.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- cloud account work must not be used as a reason to rewrite local appliance trust;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
