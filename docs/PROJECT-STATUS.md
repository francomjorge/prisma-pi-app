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
| SQLite metadata adapter | RUNTIME_VERIFIED | `SqliteMediaMetadataRepository` schema migration v1, persistence/reopen, uniqueness constraints and ordered retrieval execute in CI. Android device packaging/restart behavior still requires physical validation. |
| Android content URI adapter | BUILT | M0 `ContentResolver` bridge inspects user-selected URIs and copies granted content into controlled app paths without depending on external absolute paths. Physical SAF picker/grant validation pending. |
| Android native media metadata probe | BUILT | M0 bridge compiles image/video metadata probing with `BitmapFactory` / `MediaMetadataRetriever`; real-device codec/format coverage pending. |
| Media presentation/aspect contract | RUNTIME_VERIFIED | Platform-neutral contain/cover/fill/fit-width/fit-height/native-pixel/scale-down semantics plus bounded decode-size planning pass deterministic tests. |
| Media resource-budget contract | RUNTIME_VERIFIED | Byte/decoder/render-surface budgets, pressure levels, release policy and explicit `MediaResourceRegistry` ownership/lease behavior pass tests. Device-specific limits remain unmeasured. |
| Native GPU diagnostic accounting | BUILT_SPIKE | Android diagnostic counters now include active OES/2D GPU textures and ping-pong framebuffers and are exposed by the M0 resource probe. Correct device-side allocation/release still requires hardware validation. |
| UI/media library strategy | DESIGNED | ADR-004 keeps Flutter UI, optional image/UI helpers and Android Media3/platform decoders behind PRISMA-owned boundaries; no third-party library is allowed to own core architecture. |
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
| Local image decode | BUILT_SPIKE | Target-sized native still-image decode/render path compiles with modern `ImageDecoder` plus `BitmapFactory` fallback. Physical format/performance validation pending. |
| Local looping video decode | BUILT_SPIKE | Media3 repeat/seek-capable local-video path and explicit player disposal compile into the Android APK. Sustained physical playback validation pending. |
| Android GPU texture video path | BUILT_SPIKE | Media3 → `Surface` → `SurfaceTexture` → `GL_TEXTURE_EXTERNAL_OES` → native input pass → reusable 2D ping-pong targets compiles into the Android APK. Actual frame delivery, copy behavior, memory and thermal characteristics require hardware validation. |
| Media endpoint negotiation | PARTIAL_IMPLEMENTATION | Endpoint model, Protocol 2.0 decode and session acquisition implemented; platform media transport selection/runtime pending. |
| Processing graph contract | STATICALLY_VERIFIED | Ordered authoritative `ProcessingGraph`, execution-target filtering, reorder semantics and bypass behavior pass domain/runtime tests. |
| Processing runtime adapter | STATICALLY_VERIFIED | `prisma_processing_runtime` compiles MOBILE/BOTH graph nodes into deterministic schema-v1 plans, enforces capabilities/node limits and defines opaque backend session contracts without platform SDK types. |
| Ordered GPU processing stage | BUILT_SPIKE | Android M0 consumes the neutral plan, converts the OES decoder texture once, alternates ordered passes through two private 2D texture/FBO targets, and currently maps `POSTER` and `GRAYSCALE`. APK build is verified; physical multi-pass execution is not. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | PARTIAL_IMPLEMENTATION | M0 spike includes keyboard/native bridge diagnostics; product action layer pending. |
| Android app shell | BUILT_SPIKE | Diagnostic M0 Flutter/Kotlin shell builds as debug APK; product UI remains blocked. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build; account/auth configuration will then use final package/signing identities. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Validation evidence

Latest fully green code + integration gate:

```text
d9378c513c7065b0d581aba939ffff38d937b75c
foundation-validation run #241 / 38276485418
```

All eight jobs passed on that exact head:

```text
domain
security-contracts
storage-runtime
media-runtime-contract
processing-runtime
connector-session
network-protocol-integration
android-stack-spike
```

This gate covers the previous foundation plus the ordered native GPU processing increment: `ProcessingPlan` reorder/bypass tests, a two-node diagnostic plan, private ping-pong 2D textures/framebuffers, OES input conversion, ordered POSTER → GRAYSCALE passes, explicit GPU texture/FBO accounting, resource counters exposed through the M0 diagnostic probe, and a complete debug APK build.

This is still build/static evidence for the Android GPU path, not physical execution evidence. CI does not execute a phone GPU driver or prove zero-copy behavior, visual output correctness, decoder/SurfaceTexture lifecycle under Android backgrounding, memory stability or thermal behavior.

Android NSD/Keystore/ContentResolver/media behavior, actual OES frame delivery through the two-node chain, GPU allocation/release behavior and the Legacy ESP32 connector still require target-hardware validation.

CI concurrency cancels obsolete in-progress PR runs so only the newest revision matters for branch health, while recorded evidence remains tied to the exact validated commit.

## Next coherent work packages

1. make the M0 debug APK a retained CI artifact so the exact validated diagnostic build can be installed on a physical Android device without rebuilding it elsewhere;
2. run the physical Android M0 acceptance sequence: Media3 → OES frame delivery, POSTER → GRAYSCALE output, resource counters, NSD, Keystore restart behavior, keyboard input, ContentResolver imports and SQLite persistence;
3. add a controlled physical reorder/bypass diagnostic and prove the visible GPU pass order matches `ProcessingPlan` order without CPU readback;
4. stress repeated image/video source switching and processing-session recreation while recording Java/native/GPU memory, decoder/surface/texture/FBO counts and dropped frames;
5. run a sustained 30+ minute processed-video loop plus background/foreground and rotation cycles; record thermal and memory behavior;
6. only after that device baseline, implement production-shaped `updatePlan(...)` behavior instead of rebuilding processing state blindly;
7. physically validate `LegacyEsp32Connector` against the protected ESP32-S3 firmware without modifying that firmware;
8. align production parameter semantics for PIXEL/GLITCH/POSTER/HUE/MIRROR with PRISMA Core before expanding the native effect family;
9. build a disposable ESP32-S3 pairing/security spike on ESP-IDF 5.5.1 without modifying the protected firmware baseline;
10. implement account backend API skeleton and signed offline-entitlement proof;
11. validate Google login with non-production OAuth only after final-enough package/signing identity exists;
12. only then begin production UI composition.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- cloud account work must not be used as a reason to rewrite local appliance trust;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
