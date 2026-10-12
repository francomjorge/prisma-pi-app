# PRISMA-PI App — Account, Authentication & Licensing

**Status:** Draft / DESIGNED  
**Date:** 2026-10-12  
**Scope:** Mobile account identity, login, sessions, entitlements and licensing. This is separate from appliance pairing/security.

## 1. Product requirement

PRISMA-PI App will have an account layer because later product functions will depend on a stable user identity: licenses, subscriptions, purchases, restore-purchases, future cloud synchronization, support and account recovery.

Android starts with **Sign in with Google** as the primary login path. The architecture must remain provider-neutral so iOS can add **Sign in with Apple** and a future email-link/one-time-code provider can be added without changing account IDs, licenses or product logic.

## 2. Critical separation: account identity != appliance trust

There are two independent trust domains:

```text
PRISMA CLOUD ACCOUNT
  identity / sessions / licenses / purchases

PRISMA APPLIANCE TRUST
  local pairing / device authorization / local transport security
```

A signed-in cloud account does not automatically authorize control of arbitrary appliances. A paired appliance does not contain Google/Apple credentials. A temporary cloud outage must not invalidate an established local appliance pairing.

Account↔device association may later exist as metadata for convenience/support, but it is not the local transport trust mechanism.

## 3. Account identity model

PRISMA owns the product identity. External identity providers prove who the user is; they do not become the product database key.

```text
PrismaAccount
├── account_id                 immutable PRISMA UUID
├── display_name?
├── primary_email?
├── email_verified
├── identities[]
├── created_at
├── status
└── profile_generation

ExternalIdentity
├── provider                   GOOGLE | APPLE | EMAIL_LINK | FUTURE
├── provider_subject           immutable provider subject
├── email?
├── email_verified
├── linked_at
└── last_authenticated_at
```

Rules:

- `account_id` is the canonical PRISMA identity.
- Never use email as the primary key; email can change.
- For Google, the stable provider identifier is the token subject (`sub`), not the displayed email.
- Multiple provider identities may later link to one PRISMA account.
- Provider tokens/credentials are never serialized into projects or appliance configuration.

## 4. Android login flow

Preferred production flow:

```text
User
 ↓
Android Credential Manager / Sign in with Google
 ↓
Google ID token / credential
 ↓ HTTPS
PRISMA Account Backend
 ↓
verify Google token signature + audience + issuer + expiry
 ↓
resolve/create PrismaAccount using provider + subject
 ↓
issue PRISMA session
 ↓
return account profile + entitlement snapshot
 ↓
App secure credential store
```

The mobile client must not treat a locally decoded Google token as sufficient proof for licensing. Provider credentials are exchanged with the PRISMA backend, and the backend performs verification before creating a PRISMA session.

## 5. Backend verification invariant

For Google identity tokens, the backend validates at minimum:

- token signature;
- `aud` against the expected PRISMA OAuth client audience;
- `iss`;
- `exp`;
- provider subject `sub` as the stable external identity key.

A plain Google user ID or email supplied by the app is never trusted as authentication proof.

## 6. PRISMA session model

Provider login and PRISMA application session are distinct.

```text
Provider Credential
        ↓ exchange
PRISMA Session
├── session_id
├── account_id
├── access credential
├── refresh credential / equivalent
├── issued_at
├── expires_at
├── environment
└── security_generation
```

Session material must be stored only through secure platform storage (Android Keystore-backed storage / iOS Keychain-backed storage via the platform adapter).

Logs must never contain provider tokens, PRISMA session secrets, refresh credentials or purchase verification secrets.

## 7. Authentication state machine

```text
SIGNED_OUT
   ↓ login
AUTHENTICATING
   ↓ success
AUTHENTICATED
   ↓ entitlement refresh
READY_ONLINE

AUTHENTICATED ── network unavailable ──> READY_OFFLINE
AUTHENTICATED ── session invalid ───────> REAUTH_REQUIRED
ANY ── logout/account removed ─────────> SIGNED_OUT
```

Presentation code observes these states. It does not own them.

## 8. Licensing is not authentication

Authentication answers:

> Who is this user?

Licensing answers:

> Which PRISMA capabilities is this account currently entitled to use?

They must remain separate services and models.

```text
LicenseEntitlement
├── entitlement_id
├── account_id
├── product_id
├── tier
├── status
├── source
├── features[]
├── valid_from?
├── valid_until?
├── offline_grace_until?
├── revision
└── server_signature / verification metadata
```

Initial entitlement sources are normalized as:

```text
GOOGLE_PLAY
APPLE_APP_STORE
PROMO
ADMIN
LEGACY
BUNDLE
```

Store-specific receipts/tokens do not leak into feature code.

## 9. Offline-first licensing requirement

PRISMA is intended for live/creative use. Internet loss during a performance must not abruptly disable processing or appliance control.

The app therefore needs a locally cached, backend-issued entitlement snapshot that can be verified offline.

Conceptual states:

```text
LICENSED_ONLINE
LICENSED_OFFLINE_FRESH
LICENSED_OFFLINE_GRACE
ENTITLEMENT_REFRESH_REQUIRED
ENTITLEMENT_EXPIRED
ENTITLEMENT_REVOKED
```

Rules:

- exact offline duration is configuration/policy, not hard-coded into domain models;
- a transient network loss does not terminate an already-running performance session;
- reconnect triggers entitlement refresh;
- permanent offline bypass is not supported;
- clock-skew behavior must be explicit and tested;
- entitlement expiry/revocation behavior must distinguish startup from an active live session.

## 10. Purchase verification boundary

Future Google Play / App Store purchase adapters are only acquisition mechanisms.

```text
Store SDK
  ↓ purchase token / signed transaction
PRISMA Backend
  ↓ provider verification
Entitlement Service
  ↓
Normalized LicenseEntitlement
```

The client does not grant itself a durable paid entitlement merely because a store callback reports success.

## 11. Minimal backend services

The first backend boundary should remain small:

```text
IdentityExchangeService
SessionService
AccountService
EntitlementService
PurchaseVerificationService
AccountDeletionService
Diagnostics/Audit Service (minimal, redacted)
```

Suggested logical endpoints, transport details still open:

```text
POST /auth/google/exchange
POST /auth/apple/exchange           future iOS
POST /auth/email/start              optional future
POST /auth/email/complete           optional future
POST /session/refresh
POST /session/logout
GET  /account
DELETE /account
GET  /entitlements
POST /purchases/google/verify       future
POST /purchases/apple/verify        future
```

## 12. Local data/privacy boundary

Login does **not** imply cloud upload of the user's media, projects or recordings.

Default:

- account/profile/licensing metadata may use backend services;
- media library remains local;
- projects remain local;
- appliance credentials remain local secure data;
- future cloud sync must be an explicit product feature with its own consent/data contract.

## 13. iOS requirement

The account abstraction must support multiple providers from day one. When the iOS app uses Google or another third-party social login to establish the primary app account, App Store review rules can require an equivalent privacy-preserving login option. The implementation plan therefore reserves **Sign in with Apple** for the iOS target rather than hard-coding Google as the only possible provider.

## 14. Email account option

A separate email-based login remains supported architecturally through `EMAIL_LINK` or one-time-code authentication.

If added, the preferred initial direction is passwordless email verification rather than creating a password database without a concrete need.

This decision is still open for V1; Google remains the Android default.

## 15. Environment separation

Identity and licensing must have explicit environments:

```text
DEV
STAGING
PRODUCTION
```

Each environment has independent:

- backend base URL;
- OAuth client configuration/audience;
- session signing configuration;
- entitlement signing configuration;
- database/account namespace;
- purchase verification configuration.

No production secret belongs in this repository.

The disposable M0 Android spike must not freeze the final Android application ID, signing identity or production OAuth configuration.

## 16. Failure policy

Authentication/licensing failures must be explicit and typed:

```text
NETWORK_UNAVAILABLE
PROVIDER_CANCELLED
PROVIDER_FAILED
INVALID_PROVIDER_CREDENTIAL
ACCOUNT_DISABLED
SESSION_EXPIRED
SESSION_REVOKED
ENTITLEMENT_UNAVAILABLE
ENTITLEMENT_EXPIRED
ENTITLEMENT_REVOKED
PURCHASE_VERIFICATION_FAILED
CLOCK_SKEW_DETECTED
BACKEND_UNAVAILABLE
```

A cloud/account failure must never be silently converted into an appliance pairing failure.

## 17. Required tests before production UI

- Google credential exchange success/failure;
- wrong audience rejection;
- expired provider token rejection;
- stable provider subject mapping to one `account_id`;
- email change without account duplication;
- secure logout/revocation;
- offline restart with valid entitlement snapshot;
- offline grace transition;
- entitlement expiration;
- entitlement revocation after reconnect;
- clock skew handling;
- backend unavailable during active performance;
- provider linking conflict;
- account deletion behavior;
- proof that appliance pairing works independently from cloud reachability.

## 18. Current official platform references

- Android: Credential Manager / Sign in with Google — https://developer.android.com/identity/sign-in/credential-manager-siwg
- Google backend authentication / ID token verification — https://developers.google.com/identity/sign-in/android/backend-auth
- Apple App Store Review Guidelines, Login Services — https://developer.apple.com/app-store/review/guidelines/
- Sign in with Apple — https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/

These external platform details can evolve. Product/domain contracts in this document intentionally avoid depending on one SDK type.
