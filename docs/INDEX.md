# PRISMA-PI App Documentation Index

This repository is the working construction repository for the PRISMA-PI mobile application.

## Current phase

**INFRASTRUCTURE FOUNDATION** — product UI implementation is intentionally blocked until the infrastructure gates are satisfied.

## Canonical app documents

- `architecture/MOBILE-FOUNDATION-2.0.md` — mobile runtime topology, execution modes, connectors, processing graph and infrastructure gates.
- `protocol/PROTOCOL-2.0.md` — mobile ↔ appliance discovery, control, events, capabilities, media negotiation and compatibility.
- `storage/MOBILE-STORAGE-2.0.md` — managed library, media import, SQLite metadata, projects, recordings, cache and migration rules.
- `SECURITY-PAIRING.md` — trust, pairing, credential handling and production security constraints.
- `MEDIA-LIVE-VIEW.md` — source/processed/program media semantics and endpoint selection.
- `UI-SKIN-CONTRACT.md` — UI boundaries, design tokens, skins and input abstraction; no concrete production screens yet.
- `LEGACY-WEB-REFERENCE.md` — functionality already proven or prototyped in the existing web controller and branches.
- `ROADMAP-INFRA-FIRST.md` — implementation order and validation gates.
- `PROJECT-STATUS.md` — current status by subsystem using DESIGNED → IMPLEMENTED → BUILT → STATICALLY_VERIFIED → HARDWARE_TESTED → BASELINE.
- `REPOSITORY-LAYOUT.md` — intended application repository organization before code lands.

## Related sources of truth

PRISMA product semantics currently originate in `prisma-pi-lite-core`. The mobile app may specialize application behavior but must not silently redefine shared Core state or command semantics.

The current ESP32-S3 repository is a physical appliance implementation and a compatibility target. Its validated firmware baseline is protected while Protocol 2.0 is developed.

## Working rule

Documentation is versioned product source. Any implementation that changes a contract must update the corresponding document in the same change set.
