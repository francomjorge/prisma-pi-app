# PRISMA-PI App Documentation Index

This repository is the working construction repository for the PRISMA-PI mobile application.

## Current phase

**INFRASTRUCTURE FOUNDATION** — product UI implementation is intentionally blocked until the infrastructure gates are satisfied.

## Canonical app documents

- `architecture/MOBILE-FOUNDATION-2.0.md` — mobile runtime topology, execution modes, connectors, processing graph and infrastructure gates.
- `protocol/PROTOCOL-2.0.md` — mobile ↔ appliance discovery, control, events, capabilities, media negotiation and compatibility.
- `storage/MOBILE-STORAGE-2.0.md` — managed library, media import, SQLite metadata, projects, recordings, cache and migration rules.
- `accounts/AUTH-AND-LICENSING.md` — PRISMA account identity, Google/Apple/email provider abstraction, backend sessions, entitlements, purchases and offline licensing.
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

`packages/prisma_domain` contains the initial platform-neutral product contracts for:

- synthesizer state;
- protocol envelopes/events;
- devices/capabilities/media endpoints;
- processing graph;
- account identity;
- authentication state;
- license entitlements.

These are infrastructure contracts, not final UI code.

## Related sources of truth

PRISMA product semantics currently originate in `prisma-pi-lite-core`. The mobile app may specialize application behavior but must not silently redefine shared Core state or command semantics.

The current ESP32-S3 repository is a physical appliance implementation and a compatibility target. Its validated firmware baseline is protected while Protocol 2.0 is developed.

## Working rule

Documentation is versioned product source. Any implementation that changes a contract must update the corresponding document in the same change set.
