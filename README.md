# PRISMA-PI App

Primary mobile controller and local processing application for PRISMA-PI.

## Status

**Phase:** infrastructure foundation  
**Primary target:** Android first, iOS second  
**UI implementation:** intentionally not started yet

This repository is the construction repository for the PRISMA-PI mobile application. The application will become the primary controller for PRISMA-PI appliances while preserving a secondary web controller where useful.

The project is intentionally infrastructure-first. No production UI work begins until the storage, connector, security, synchronization, media transport and processing contracts are stable enough to support it without redesign.

## Product direction

PRISMA-PI App will:

- run locally on Android and later iOS;
- manage image and video sources as first-class media, with audio reserved as a first-class future input;
- perform capable local media processing on the phone;
- discover, pair with and control PRISMA-PI appliances;
- receive Live View content from appliances;
- support Wi-Fi/LAN first and additional transports through connector adapters;
- separate source preview, processed preview and program output;
- expose a unified FX Rack for visual FX, Motion FX and processing order;
- expose FX Lab as the advanced composition/processing workspace;
- support projects, recordings, managed media and future skins;
- support external keyboard shortcuts through the same command system used by touch UI;
- keep the web controller as an optional secondary surface rather than the primary runtime.

## Architectural invariants

1. One authoritative synthesizer state per active runtime/session.
2. All state mutations are commands.
3. UI navigation/presentation state is not synthesizer state.
4. Device support is capability-driven, not device-name-driven.
5. LOCAL, APPLIANCE and future HYBRID execution are explicit modes.
6. Source Preview, Processed Preview, Preview Stream and Program Output are distinct concepts.
7. Files are referenced by logical IDs, not exposed filesystem paths.
8. Security and pairing are part of the protocol design, not UI add-ons.
9. The validated appliance firmware is not modified merely to simplify mobile development.
10. The first visual skin is retro photographic / warm analog inspired, without reproducing a third-party brand.

## Engineering gates before UI

The following foundation must be designed and validated before production screen implementation:

1. app/core state + command contracts;
2. device discovery, identity and pairing;
3. connector abstraction;
4. Protocol 2.0 and real-time synchronization;
5. media endpoint negotiation and Live View;
6. managed storage/library and migration model;
7. processing graph and execution-target model;
8. skin/design-token and input-action abstraction;
9. Mock Appliance test harness.

## Related repositories

- `prisma-pi-lite-core` — existing hardware-independent PRISMA contracts and architecture baseline.
- `prisma-pi-lite-waveshare-esp32-s3-touch-lcd-1-54` — current ESP32-S3 appliance implementation and physically validated baseline.

The mobile app repository owns the application implementation and app-specific architecture. Shared product semantics should remain aligned with PRISMA Core rather than being silently redefined here.

## Documentation

Architecture and implementation planning live under `docs/`. The documentation is treated as part of the product source and must evolve together with the implementation.
