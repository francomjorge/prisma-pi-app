# ADR-003 — Appliance Pairing and Local Session Security

**Status:** PROPOSED / implementation contract started  
**Date:** 2026-10-12

## Context

PRISMA mobile must control appliances over local Wi-Fi without coupling local control to Google/Apple/PRISMA cloud identity.

The current ESP32-S3 firmware baseline is intentionally legacy-compatible and physically validated. Its current network surface uses:

- ESP-IDF `v5.5.1` in CI;
- ESP32-S3 target;
- device SoftAP;
- `WIFI_AUTH_OPEN`;
- plaintext HTTP server;
- legacy `/api/state` and `/source/...` endpoints.

That baseline is a compatibility target, not the production security model, and must not be silently modified while the mobile contract is still being designed.

## Decision direction

Separate first pairing from normal authenticated control sessions.

```text
DISCOVERY
   ↓
PAIRING CEREMONY
   ↓
DEVICE TRUST ESTABLISHED
   ↓
SECURE CREDENTIAL STORED
   ↓
AUTHENTICATED LOCAL SESSION
   ↓
HTTP/WebSocket/media control
```

Cloud account authentication is not part of this chain.

## Proposed production profile

The preferred ESP32-S3 direction is a two-stage design:

### Stage A — first pairing

Evaluate ESP-IDF `protocomm_security2` as the reference first-pairing mechanism.

Espressif's protocomm Security 2 provides:

```text
SRP6a authentication/key exchange
+ AES-GCM protected application messages
```

This is available in the ESP-IDF family used by the appliance and is specifically designed for secure session establishment over SoftAP/HTTP or BLE-style provisioning transports.

The pairing ceremony should require a device-specific human-verifiable secret rather than a global password. Product candidates:

- short pairing code displayed on the appliance screen;
- QR containing non-secret device identity plus one-time/bootstrap material;
- unique per-device setup credential generated during manufacturing/first boot.

The final UX is not frozen by this ADR.

### Stage B — normal sessions

After successful first pairing, the app and appliance establish reusable local trust material. Normal control should then use short-lived authenticated sessions, not re-run a human pairing ceremony every time.

Reference direction:

```text
pinned per-device TLS identity
+
client authorization credential/challenge
+
short-lived appliance session token
```

A practical production candidate is HTTPS/WSS using a per-device certificate/public-key fingerprint pinned during pairing, plus application-level client authorization. Mutual TLS is not required by this ADR and should only be selected if measurements and implementation complexity justify it.

## Why not use Google login for appliance trust

Google/Apple proves cloud account identity. It does not prove physical possession of a nearby PRISMA appliance and must not become a dependency for local performance control.

Therefore:

```text
Google / Apple / PRISMA account → licenses, account, cloud

Appliance pairing              → local device trust, control, media
```

The two domains may later be associated by non-secret metadata, but they do not share credentials.

## Security profile identifiers

The mobile contract currently reserves:

```text
TLS_PINNED_SESSION_V1
PROTOCOMM_SECURITY2
LEGACY_UNAUTHENTICATED
```

Production profile selection fails closed if no acceptable secure profile is shared.

`LEGACY_UNAUTHENTICATED` is only allowed through an explicit compatibility policy for the protected legacy ESP32 baseline. It must never be silently selected.

## Secret storage

### Mobile

Long-lived appliance credentials must be stored behind a platform secure-store adapter:

- Android: Keystore-backed storage;
- iOS: Keychain-backed storage.

SQLite may store only opaque credential IDs and non-secret public metadata.

### ESP32-S3

Plain NVS is not sufficient for production long-lived secrets. ESP-IDF supports NVS encryption on ESP32-S3, including HMAC/eFuse-backed key protection. This must be evaluated before production credentials are persisted on-device.

Secure Boot / Flash Encryption are separate device-integrity hardening layers and should be evaluated for production manufacturing. Enabling them is not required to prototype the pairing protocol, but a production threat model must explicitly decide them.

## Transport confidentiality

ESP-IDF provides an HTTPS server layered on the regular HTTP server. This makes migration of Protocol 2.0 endpoints from HTTP to HTTPS technically feasible without replacing the entire request model.

Performance must be measured on the actual appliance because TLS session establishment has non-trivial cost on embedded hardware. Long-lived/reused control connections and WebSockets should be preferred over repeatedly creating TLS sessions.

## Wi-Fi network security

Application security must not rely solely on SoftAP WPA credentials.

For production, the appliance should not remain an anonymous open access point by default. A unique protected SoftAP configuration is desirable, but even a WPA-protected AP does not replace application-layer device authentication and session security.

## Revocation and reset

Required operations:

```text
APP FORGET DEVICE
→ delete mobile secure credential
→ invalidate local session

APPLIANCE REVOKE CLIENT
→ remove authorized client credential
→ current/future sessions fail

APPLIANCE TRUST RESET
→ clear paired clients
→ preserve or deliberately regenerate device identity according to reset type
```

Factory reset semantics must distinguish clearing user pairing from destroying/replacing manufacturing identity.

## Replay/session rules

Normal session establishment must include freshness (nonce/challenge or equivalent) and must not accept replay of a captured authorization exchange.

Bearer/session tokens must be:

- short-lived;
- device-local;
- scoped to appliance control;
- never logged;
- invalidated on revoke/reset where feasible.

## Current implementation boundary

`packages/prisma_security` now defines only platform-neutral trust/profile/credential interfaces. It contains no cryptographic implementation and therefore is not a claim that the production profile is complete.

The current Mock Appliance token remains test-only.

## Validation required before ACCEPTED

1. build a disposable ESP32-S3 security spike on ESP-IDF 5.5.1;
2. measure firmware/RAM impact of protocomm Security 2;
3. measure HTTPS/WSS handshake and steady-state command latency;
4. prove first pairing with incorrect/correct credential paths;
5. prove pinned device identity detects endpoint impersonation;
6. prove app credential survives app restart but is absent from normal DB/logs;
7. prove revoke and appliance trust reset;
8. prove captured session establishment cannot be replayed;
9. validate NVS secret protection strategy;
10. physically validate on the target appliance before changing status to ACCEPTED.

## Authoritative references

- ESP-IDF Protocol Communication / protocomm: https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-reference/provisioning/protocomm.html
- ESP-IDF Wi-Fi Provisioning Security 2: https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/api-reference/provisioning/wifi_provisioning.html
- ESP-IDF HTTPS Server: https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/protocols/esp_https_server.html
- ESP32-S3 NVS security/encryption: https://docs.espressif.com/projects/esp-idf/en/release-v5.5/esp32s3/api-reference/storage/nvs_flash.html
- ESP32-S3 security enablement workflows: https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/security/security-features-enablement-workflows.html
