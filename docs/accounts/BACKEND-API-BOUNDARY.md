# PRISMA Account Backend — API Boundary Draft

**Status:** Draft / DESIGNED  
**Date:** 2026-10-12

## 1. Purpose

Define the smallest backend required for mobile identity and licensing without coupling the app to a specific cloud vendor.

The backend is not the media engine, appliance controller or project store. Its initial job is identity/session/licensing trust.

## 2. Trust boundary

The backend is authoritative for:

- external identity verification;
- PRISMA account creation/linking;
- PRISMA sessions;
- account status;
- normalized entitlements;
- purchase verification decisions;
- entitlement revisions/revocation;
- account deletion workflow.

The backend is not authoritative for:

- live appliance pairing/session keys;
- local media bytes;
- local project files;
- current synthesizer state;
- appliance command state.

## 3. Logical services

```text
IdentityExchangeService
├── exchangeGoogleCredential(...)
├── exchangeAppleCredential(...)
└── emailPasswordless... (optional)

SessionService
├── refresh(...)
├── revokeCurrent(...)
└── revokeAll(...)

AccountService
├── getProfile(...)
├── linkIdentity(...)
├── unlinkIdentity(...)
└── requestDeletion(...)

EntitlementService
├── getSnapshot(...)
├── refresh(...)
└── getRevision(...)

PurchaseVerificationService
├── verifyGooglePlay(...)
└── verifyAppleStore(...)
```

## 4. API envelope

Exact transport remains open; HTTPS JSON is the initial reference.

Success:

```json
{
  "request_id": "uuid",
  "ok": true,
  "result": {},
  "error": null,
  "server_time_ms": 0
}
```

Failure:

```json
{
  "request_id": "uuid",
  "ok": false,
  "result": null,
  "error": {
    "code": "AUTH_INVALID_CREDENTIAL",
    "message": "safe diagnostic",
    "retryable": false
  },
  "server_time_ms": 0
}
```

## 5. Identity exchange

```text
POST /v1/auth/google/exchange
```

Request contains the provider credential plus app/environment metadata required for validation. The backend verifies the provider token and never trusts client-provided account/email identifiers as proof.

Response concept:

```json
{
  "account": {
    "account_id": "uuid",
    "display_name": "...",
    "primary_email": "...",
    "email_verified": true
  },
  "session": {
    "access_token": "opaque-or-signed",
    "expires_at_ms": 0,
    "refresh_token": "opaque"
  },
  "entitlements": {
    "revision": 12,
    "snapshot": "signed-or-server-verifiable-payload"
  }
}
```

Secrets are returned only over authenticated TLS transport and must not be logged.

## 6. Session endpoints

```text
POST /v1/session/refresh
POST /v1/session/logout
POST /v1/session/revoke-all
```

Refresh credentials are rotatable/revocable. Exact token mechanism is deferred until backend implementation selection.

## 7. Account endpoints

```text
GET    /v1/account
DELETE /v1/account
POST   /v1/account/identities/link
DELETE /v1/account/identities/{provider}
```

Unlink must reject operations that would leave the account without any recoverable identity method.

## 8. Entitlement endpoint

```text
GET /v1/entitlements
```

Returns normalized product entitlements and offline-verification metadata. Client feature gates consume normalized features, never raw store receipts.

The snapshot must include at minimum:

```text
account_id
revision
issued_at
refresh_after
hard_expiry / offline policy fields
entitlements[]
verification/signature metadata
```

The exact cryptographic format is deferred until backend/security implementation, but local verification must not require network access.

## 9. Purchase verification hooks

Future:

```text
POST /v1/purchases/google/verify
POST /v1/purchases/apple/verify
```

Client forwards the store-issued purchase evidence. Backend validates it with the relevant store service and updates normalized entitlements idempotently.

Repeated verification of the same transaction must not duplicate grants.

## 10. Minimal persistence entities

```text
accounts
external_identities
sessions
entitlements
purchase_records
account_events
schema_migrations
```

Optional later:

```text
account_device_metadata
support_cases
cloud_projects
cloud_assets
```

These optional entities are not required for initial auth/licensing.

## 11. Account/device separation

No backend endpoint returns local appliance pairing secrets.

A future `account_device_metadata` relation may track that an account has named/registered a device, but actual local pairing credentials stay in the app/appliance secure trust domain.

## 12. Rate limiting and abuse controls

Required before production:

- rate-limit provider exchange failures;
- rate-limit passwordless email if added;
- protect refresh/revocation endpoints;
- idempotency keys for purchase verification;
- safe audit events for security-sensitive account transitions;
- no secret/token values in audit data.

## 13. Environment configuration

Backend instances/namespaces must be isolated for DEV/STAGING/PRODUCTION. Provider audiences and signing keys are environment-specific.

A DEV credential must not authenticate to production.

## 14. Open implementation choices

- backend language/framework;
- hosting provider;
- database engine;
- PRISMA session token format;
- entitlement snapshot signature format;
- email provider if passwordless login is added;
- purchase event/webhook processing strategy.

These choices should be made after contracts are stable, not embedded into the mobile domain model.
