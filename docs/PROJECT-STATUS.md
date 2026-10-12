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
| Android GPU texture video path | BUILT_SPIKE | Media3 → `Surface` → `SurfaceTexture` → `GL_TEXTURE_EXTERNAL_OES` → GLSL pass-through compiles in CI; actual frame delivery, copy behavior, memory and thermal characteristics require hardware validation. |
| Media endpoint negotiation | PARTIAL_IMPLEMENTATION | Endpoint model, Protocol 2.0 decode and session acquisition implemented; platform media transport selection/runtime pending. |
| Processing graph | IMPLEMENTED_CONTRACT | Ordered node model exists in domain package; processor runtime not implemented. |
| GPU processing stage | PROOF_BOUNDARY_ONLY | OES/GLSL insertion point now compiles but the shader is pass-through; no production FX node execution is claimed yet. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | PARTIAL_IMPLEMENTATION | M0 spike includes keyboard/native bridge diagnostics; product action layer pending. |
| Android app shell | BUILT_SPIKE | Diagnostic M0 Flutter/Kotlin shell builds as debug APK; product UI remains blocked. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build; account/auth configuration will then use final package/signing identities. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Validation evidence

Latest fully recorded green foundation gate:

```text
74e4c8d6ad9584ae997f849782ce60a957840fef
foundation-validation run #216 / 38269436921
```

All seven jobs passed on that exact head:

```text
domain
security-contracts
storage-runtime
media-runtime-contract
connector-session
network-protocol-integration
android-stack-spike
```

This gate covers durable SQLite tests, local-media contracts, aspect/resolution policy, resource ownership, Android managed-media source compilation, Media3 playback-surface compilation and the SurfaceTexture/OES GPU-path debug APK build.

This is not physical Android or ESP32 evidence. Android NSD/Keystore/ContentResolver/media behavior, SurfaceTexture frame delivery and the Legacy ESP32 connector still require target-hardware validation.

CI concurrency cancels obsolete in-progress PR runs so only the newest revision matters.

## Next coherent work packages

1. add one deliberately simple diagnostic GPU shader effect (grayscale/posterize) to prove decoder → OES texture → PRISMA shader → render target without CPU readback;
2. define the PRISMA-owned GPU processing-node adapter so Core/application code never depends directly on OpenGL ES, Vulkan or Media3;
3. run Android M0 on a physical device and validate `NsdManager`, local-network permission behavior, Keystore round-trip/restart, keyboard input, ContentResolver imports, SQLite restart persistence and native media probing;
4. validate target-sized image rendering and the Media3/OES path under portrait/landscape/extreme aspect ratios;
5. stress repeated video/image source switching and release/reopen cycles while recording Java/native memory, decoder count, render-surface count and dropped frames;
6. run a sustained 30+ minute loop plus background/foreground and rotation cycles; record thermal and memory behavior;
7. physically validate `LegacyEsp32Connector` against the protected ESP32-S3 firmware without modifying that firmware;
8. build a disposable ESP32-S3 pairing/security spike on ESP-IDF 5.5.1 without modifying the protected firmware baseline;
9. implement account backend API skeleton and signed offline-entitlement proof;
10. validate Google login with non-production OAuth only after final-enough package/signing identity exists;
11. only then begin production UI composition.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- cloud account work must not be used as a reason to rewrite local appliance trust;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
