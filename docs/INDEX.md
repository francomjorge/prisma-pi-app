# PRISMA-PI App Documentation Index

This repository is the working construction repository for the PRISMA-PI mobile application.

## Current phase

**INFRASTRUCTURE FOUNDATION** — product UI implementation is intentionally blocked until the infrastructure gates are satisfied.

## Canonical app documents

- `architecture/MOBILE-FOUNDATION-2.0.md` — mobile runtime topology, execution modes, connectors, processing graph and infrastructure gates.
- `protocol/PROTOCOL-2.0.md` — mobile ↔ appliance discovery, control, events, capabilities, media negotiation and compatibility.
- `protocol/NETWORK-MOCK-APPLIANCE.md` — real HTTP + WebSocket Protocol 2.0 reference path, network Mock Appliance, session sequence and integration-test scope.
- `connectivity/CONNECTOR-SESSION-RUNTIME.md` — transport-neutral connector API, appliance-session state machine, generation synchronization, reconnect and legacy-adapter boundaries.
- `testing/MOCK-APPLIANCE.md` — deterministic Mock Appliance strategy, current in-memory implementation, fault-injection plan and integration-test matrix.
- `storage/MOBILE-STORAGE-2.0.md` — managed library, media import, SQLite metadata, projects, recordings, cache and migration rules.
- `accounts/AUTH-AND-LICENSING.md` — PRISMA account identity, Google/Apple/email provider abstraction, backend sessions, entitlements, purchases and offline licensing.
- `accounts/BACKEND-API-BOUNDARY.md` — minimal provider-independent backend trust/API boundary for identity, sessions, entitlements and purchase verification.
- `accounts/BACKEND-DATA-MODEL.md` — logical account/identity/session/entitlement/purchase persistence model, uniqueness rules and offline snapshot boundary.
- `accounts/GOOGLE-AUTH-SETUP-CHECKLIST.md` — production Google Auth/Android signing configuration checklist; intentionally deferred until final package/signing identity is chosen.
- `SECURITY-PAIRING.md` — appliance trust, pairing, credential handling and production transport-security constraints. Account login is a separate trust domain.
- `MEDIA-LIVE-VIEW.md` — source/processed/program media semantics and endpoint selection.
- `UI-SKIN-CONTRACT.md` — UI boundaries, design tokens, skins and input abstraction; no concrete production screens yet.
- `LEGACY-WEB-REFERENCE.md` — functionality already proven or prototyped in the existing web controller and branches.
- `ROADMAP-INFRA-FIRST.md` — implementation order and validation gates.
- `PROJECT-STATUS.md` — current status by subsystem using DESIGNED → IMPLEMENTED → BUILT → STATICALLY_VERIFIED → RUNTIME_VERIFIED → HARDWARE_TESTED → BASELINE.
- `REPOSITORY-LAYOUT.md` — intended application repository organization.

## Architecture decisions

- `decisions/ADR-001-MOBILE-STACK.md` — proposed Flutter application shell + native media/platform boundary; not accepted until the Android spike is validated.
- `decisions/ADR-002-ACCOUNT-IDENTITY-AND-LICENSING.md` — provider-independent PRISMA account, Google-first Android login, backend-issued sessions, normalized entitlements and offline licensing.

## Implemented non-UI packages

### `packages/prisma_domain`

Initial platform-neutral product contracts for:

- synthesizer state;
- protocol envelopes/events;
- devices/capabilities/media endpoints;
- processing graph;
- account identity;
- authentication state;
- license entitlements.

### `packages/prisma_connector`

Initial remote-runtime infrastructure for:

- connector transport abstraction;
- discovery records;
- connection health;
- remote appliance session lifecycle;
- full-state synchronization and generation-gap recovery;
- deterministic in-memory Mock Appliance;
- Protocol 2.0 LAN/Wi-Fi HTTP + WebSocket connector;
- integration tests for commands/conflicts/resynchronization.

### `packages/prisma_mock_appliance`

Development/test appliance process for:

- Protocol 2.0 HTTP endpoints;
- authenticated appliance session bootstrap;
- WebSocket event channel;
- network command/state/capability/media tests;
- generation-gap fault injection;
- future disconnect/latency/schema fault injection.

These are infrastructure contracts and runtime components, not final UI code.

## Related sources of truth

PRISMA product semantics currently originate in `prisma-pi-lite-core`. The mobile app may specialize application behavior but must not silently redefine shared Core state or command semantics.

The current ESP32-S3 repository is a physical appliance implementation and a compatibility target. Its validated firmware baseline is protected while Protocol 2.0 is developed.

## Working rule

Documentation is versioned product source. Any implementation that changes a contract must update the corresponding document in the same change set.
