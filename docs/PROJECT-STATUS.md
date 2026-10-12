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
| Repository baseline | IMPLEMENTED | App repository initialized and documentation branch created. |
| Mobile architecture | DESIGNED | Foundation contract documented; review/freeze pending. |
| Protocol 2.0 | DESIGNED | Envelope, channels, events, reconnect, capabilities and legacy boundary documented. |
| Managed storage | DESIGNED | Transactional import, SQLite metadata, projects, recordings and migration documented. |
| Security/pairing | DESIGNED | Required properties defined; production cryptographic profile not selected yet. |
| Connector abstraction | DESIGNED | Interface and transport families defined; no app code yet. |
| LAN discovery | DESIGNED | mDNS/DNS-SD preferred; implementation not started. |
| Mock Appliance | NOT_STARTED | Next major infrastructure deliverable. |
| Local image decode | NOT_STARTED | Required before UI. |
| Local looping video decode | NOT_STARTED | Required before UI. |
| Media endpoint negotiation | DESIGNED | Runtime implementation pending. |
| Processing graph | DESIGNED | Ordered node model defined; runtime not implemented. |
| Legacy ESP32 connector | DESIGNED | Compatibility behavior documented; implementation pending. |
| Skin/token system | DESIGNED | Contract defined; schema implementation pending. |
| Input/keyboard action layer | DESIGNED | Product-action mapping defined; implementation pending. |
| Android app shell | BLOCKED | Intentionally blocked by infrastructure gates. |
| Production UI | BLOCKED | Must not begin before foundation exit criteria. |
| Google Play distribution | PENDING | Needed at first signed internal-testing build, not before. |
| iOS implementation | FUTURE | Starts after Android foundation stabilizes. |

## Next work package

The next coherent increment should be:

1. freeze app repository layout;
2. select the cross-platform application framework and native media boundary formally;
3. implement platform-independent model package;
4. implement Mock Appliance + Protocol 2.0 client integration tests;
5. then begin storage/runtime adapters.

## Protected external baselines

- current physically validated ESP32-S3 firmware remains protected;
- legacy web branches remain historical references and test vectors;
- no compatibility work should rewrite stable appliance behavior unless a requirement directly demands it and regression validation exists.
