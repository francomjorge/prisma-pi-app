# Security & Pairing Contract

**Status:** DESIGN IN PROGRESS / CONTRACT IMPLEMENTED

## Goals

The production app must establish explicit trust with each appliance. Security is part of the protocol and connector design, not a later UI feature.

## Current target facts

The protected ESP32-S3 baseline currently builds with ESP-IDF 5.5.1 and exposes a legacy open SoftAP + plaintext HTTP controller. That behavior remains a compatibility target and is classified as `LEGACY_UNAUTHENTICATED`; it is not the production profile.

ESP-IDF provides relevant primitives for the future production path:

- protocomm Security 2: SRP6a + AES-GCM secure session establishment;
- SoftAP/HTTP transport support for protocomm;
- HTTPS server support over the existing HTTP server model;
- ESP32-S3 NVS encryption options, including HMAC/eFuse-backed key protection.

These primitives make a secure production profile feasible without inventing cryptography, but the exact composition remains PROPOSED until measured on hardware.

See `decisions/ADR-003-APPLIANCE-PAIRING-SECURITY.md`.

## Required properties

- stable appliance identity;
- stable app/client identity where required;
- explicit first-pairing ceremony;
- authenticated sessions after pairing;
- replay-resistant session establishment;
- credential revocation/reset;
- Android Keystore and iOS Keychain for mobile secrets;
- protected device-side secret persistence for production;
- no plaintext secret persistence in SQLite, project files or logs;
- no permanent globally shared appliance password;
- diagnostics that distinguish discovery, pairing, authentication and authorization failures;
- legacy insecure operation explicitly marked as compatibility/development mode.

## Trust states

```text
UNSEEN
DISCOVERED
PAIRING_REQUIRED
PAIRING
TRUSTED
AUTHENTICATED
REVOKED
ERROR
```

These states now exist in platform-neutral code in `packages/prisma_security`.

## Pairing flow — logical

```text
Discover device
→ fetch identity + supported security profiles
→ select strongest mutually acceptable profile
→ user confirms target device
→ perform selected pairing method
→ exchange/derive client authorization material
→ store secret material in secure platform store
→ verify authenticated session
→ persist non-secret public device metadata
→ mark TRUSTED/AUTHENTICATED
```

The pairing ceremony should use a device-specific human-verifiable secret or equivalent proof of physical possession. Candidate UX includes a short code or QR shown on the appliance display. No final UX is frozen yet.

## Security profile selection

Reserved profile IDs:

```text
TLS_PINNED_SESSION_V1
PROTOCOMM_SECURITY2
LEGACY_UNAUTHENTICATED
```

The client chooses the strongest mutually supported production profile.

Default policy fails closed if only `LEGACY_UNAUTHENTICATED` is advertised. Legacy mode must be explicitly enabled by compatibility policy and visibly identified as insecure/development behavior.

## Two-stage production direction

### First pairing

Evaluate ESP-IDF `protocomm_security2` as the reference initial pairing mechanism.

### Normal control session

After pairing, prefer a reusable local trust relationship with short-lived authenticated sessions. Reference direction:

```text
pinned per-device TLS identity
+
client authorization credential/challenge
+
short-lived appliance session token
```

This avoids requiring human pairing on every reconnect while still separating long-lived trust from transient session tokens.

## Secret storage boundary

Allowed in app metadata DB:

- device ID;
- display name;
- model;
- last-known endpoint;
- trust status;
- credential ID/reference;
- public key/fingerprint if non-secret;
- protocol/capability metadata.

Forbidden in normal DB/project/log storage:

- passwords;
- bearer tokens;
- private keys;
- raw secure-store secret blobs;
- session secrets;
- reusable pairing secrets.

`ApplianceSecureStore` is a platform-neutral interface. Android/iOS implementations must use secure platform storage rather than SQLite.

## Device-side storage

Plain NVS is not accepted as the final production location for long-lived appliance client secrets.

The production ESP32-S3 security spike must evaluate NVS encryption and hardware-protected key options before credentials are persisted. Secure Boot and Flash Encryption remain separate production-hardening decisions.

## Logging rules

Logs may include request IDs, device IDs, protocol versions, state transitions and error codes. Logs must redact credentials, authorization headers, private keys, security challenge material, pairing codes, session tokens and sensitive payloads.

## Revocation/reset

The product requires:

- app-side forget/revoke operation;
- appliance-side single-client revoke where supported;
- appliance-side trust reset;
- explicit factory identity reset semantics.

A revoked client must fail closed and require fresh pairing.

## Cloud independence

Google/Apple/PRISMA cloud identity is a separate trust domain.

An already paired local appliance must remain controllable during cloud outage as long as local trust and offline-license policy permit operation.

No Google OAuth token, PRISMA cloud refresh token or account credential is ever sent to the ESP32 as an appliance pairing secret.

## Current code boundary

`packages/prisma_security` currently implements:

- trust-state model;
- security-profile IDs;
- fail-closed profile selection;
- pairing request/result contracts;
- opaque credential references;
- authenticated local-session contract;
- secure-store adapter interface;
- pairing-client adapter interface;
- tests proving legacy insecure mode is not silently selected.

It intentionally contains no production cryptographic implementation yet.

## Validation gate

No production device connector is considered security-ready until the following pass on real targets:

1. correct and incorrect pairing credentials;
2. reconnect after app/device restart;
3. revoked credential;
4. appliance trust reset;
5. invalid/expired session;
6. replay attempt;
7. impersonated endpoint/device fingerprint mismatch;
8. secure mobile credential persistence;
9. protected ESP32 credential persistence;
10. latency/RAM/flash measurements;
11. physical hardware test.
