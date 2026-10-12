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
| Mobile stack ADR | DESIGNED | Flutter + native boundary remains PROPOSED until M0 validation. |
| Platform-neutral domain package | IMPLEMENTED | State, protocol, devices, processing graph, account and entitlement contracts exist with initial tests. |
| Protocol 2.0 | DESIGNED | Envelope, channels, events, reconnect, capabilities and legacy boundary documented. |
| Connector abstraction | IMPLEMENTED | `prisma_connector` defines transport-neutral discovery/control/event/session contracts. |
| Remote session manager | IMPLEMENTED | Bootstrap, authoritative snapshot mirror, command gate and generation resynchronization implemented. |
| Mock Appliance | IMPLEMENTED | Deterministic in-memory connector exists with command/event/generation-gap fault behavior and tests. Real socket Mock Server still pending. |
| Managed storage | DESIGNED | Transactional import, SQLite metadata, projects, recordings and migration documented. |
| Cloud account identity | DESIGNED + PARTIAL_IMPLEMENTATION | Provider-independent account/domain model implemented; Google production flow/backend not implemented. |
| Google Android sign-in | DESIGNED | Credential Manager / Sign in with Google selected as preferred Android path; production OAuth configuration intentionally not frozen during M0. |
| iOS identity provider | DESIGNED | Sign in with Apple reserved as equivalent provider for the iOS target. |
| PRISMA account backend | DESIGNED | API trust boundary and logical account/session/entitlement/purchase data model defined; hosting/vendor still open. |
| Licensing/entitlements | DESIGNED + PARTIAL_IMPLEMENTATION | Normalized entitlement model implemented; signed offline snapshot/backend verification still pending. |
| Offline license continuity | DESIGNED | Internet loss must not stop an active performance; exact freshness/grace policy pending. |
| Store purchase abstraction | DESIGNED | Store SDK behavior must normalize through backend-verified entitlements. |
| Privacy/account deletion | DESIGNED | Local media remains local by default; deletion/retention contract still to implement. |
| Appliance security/pairing | DESIGNED | Required properties defined; production cryptographic profile not selected yet. |
| Account vs appliance trust separation | DESIGNED | Cloud identity and local appliance pairing are separate trust domains. |
| LAN discovery | DESIGNED | mDNS/DNS-SD preferred; implementation not started. |
| Local image decode | NOT_STARTED | Required before production UI. |
| Local looping video decode | NOT_STARTED | Required before production UI. |
| Media endpoint negotiation | PARTIAL_IMPLEMENTATION | Endpoint model and session acquisition implemented; platform media transport selection/runtime pending. |
| Processing graph | IMPLEMENTED_CONTRACT | Ordered node model exists in domain package; processor runtime not implemented. |
| Legacy ESP32 connector | DESIGNED | Compatibility behavior documented; implementation pending. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | PARTIAL_IMPLEMENTATION | M0 spike includes keyboard/native bridge diagnostics; product action layer pending. |
| Android app shell | SPIKE_ONLY | Diagnostic M0 shell exists; production UI intentionally blocked. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build; account/auth configuration will then use final package/signing identities. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Next coherent work packages

1. run/repair M0 + domain + connector CI and validate the native/media boundary on a real Android device;
2. expand the Mock Appliance into a real HTTP/WebSocket Protocol 2.0 test server with disconnect/failure injection;
3. add explicit reconnect scheduling and typed Protocol 2.0 response/error models to `prisma_connector`;
4. implement account backend contract/API skeleton and signed-entitlement proof before any paid purchase flow;
5. implement managed storage/runtime adapters;
6. implement LAN discovery + secure appliance pairing;
7. implement Legacy ESP32 connector and physically validate it against the protected firmware baseline;
8. validate Google login with non-production OAuth configuration after the application identity is stable enough;
9. implement and test signed offline entitlement snapshots;
10. only then begin production UI composition.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- cloud account work must not be used as a reason to rewrite local appliance trust;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
