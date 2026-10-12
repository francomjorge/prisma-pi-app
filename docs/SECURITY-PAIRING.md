# Security & Pairing Contract

**Status:** DESIGN IN PROGRESS

## Goals

The production app must establish explicit trust with each appliance. Security is part of the protocol and connector design, not a later UI feature.

## Required properties

- stable appliance identity;
- stable app/client identity where required;
- explicit first-pairing ceremony;
- authenticated sessions after pairing;
- replay-resistant session establishment;
- credential revocation/reset;
- Android Keystore and iOS Keychain for secrets;
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

## Pairing flow — logical

```text
Discover device
→ fetch identity + supported security profiles
→ user confirms target device
→ perform selected pairing method
→ exchange/derive client authorization material
→ store secret material in secure platform store
→ verify authenticated session
→ persist non-secret public device metadata
→ mark TRUSTED
```

The exact cryptographic mechanism is intentionally not frozen until actual ESP32-S3 and future appliance constraints are validated against official SDK support.

## Security profile selection

The client chooses the strongest mutually supported production profile. `LEGACY_UNAUTHENTICATED` must never be silently preferred.

## Secret storage boundary

Allowed in app metadata DB:

- device ID;
- display name;
- model;
- last-known endpoint;
- trust status;
- public key/fingerprint if non-secret;
- protocol/capability metadata.

Forbidden in normal DB/project/log storage:

- passwords;
- bearer tokens;
- private keys;
- session secrets;
- reusable pairing secrets.

## Logging rules

Logs may include request IDs, device IDs, protocol versions, state transitions and error codes. Logs must redact credentials, authorization headers, private keys, security challenge material and sensitive payloads.

## Revocation/reset

The product requires both:

- app-side forget/revoke operation;
- appliance-side trust reset/factory identity reset path.

A revoked client must fail closed and require fresh pairing.

## Validation gate

No production device connector is considered security-ready until pairing, reconnect, revocation, invalid credential, replay/session-expiry and secure-storage tests pass on the real target platform.
