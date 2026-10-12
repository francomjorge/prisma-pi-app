# PRISMA Account Backend — Logical Data Model

**Status:** Draft / DESIGNED  
**Date:** 2026-10-12

## 1. Scope

This document freezes the logical persistence boundary for identity, sessions and licensing before a concrete backend/database vendor is chosen.

It intentionally excludes user media and projects. Login does not imply cloud storage.

## 2. Core entities

```text
Account
├── account_id UUID
├── status ACTIVE | SUSPENDED | DELETION_PENDING | DELETED
├── display_name?
├── primary_email?
├── primary_email_verified
├── created_at
├── updated_at
└── deletion_requested_at?

ExternalIdentity
├── identity_id UUID
├── account_id
├── provider GOOGLE | APPLE | EMAIL_LINK | FUTURE
├── provider_subject
├── provider_email?
├── provider_email_verified?
├── linked_at
├── last_verified_at
└── disabled_at?

Session
├── session_id UUID
├── account_id
├── client_instance_id
├── refresh_credential_hash / key reference
├── created_at
├── last_used_at
├── expires_at
├── revoked_at?
├── revoke_reason?
└── environment

Entitlement
├── entitlement_id UUID
├── account_id
├── feature_id
├── status ACTIVE | GRACE | EXPIRED | REVOKED
├── source PLAY | APP_STORE | PROMO | ADMIN | LEGACY | BUNDLE
├── source_reference?
├── valid_from
├── valid_until?
├── revision
├── metadata_json
└── updated_at

PurchaseRecord
├── purchase_id UUID
├── account_id
├── provider GOOGLE_PLAY | APP_STORE
├── provider_transaction_id
├── product_id
├── purchase_state
├── purchased_at
├── last_verified_at
├── raw_evidence_secure_reference?
└── normalized_result_json

AccountEvent
├── event_id UUID
├── account_id?
├── type
├── occurred_at
├── actor_class USER | SYSTEM | SUPPORT | STORE_WEBHOOK
├── request_correlation_id?
└── redacted_metadata_json
```

## 3. Identity invariants

1. `account_id` is the permanent PRISMA product identity.
2. Email is contact/display metadata and is never the account primary key.
3. Provider subject (`sub`/equivalent) is unique per provider namespace.
4. A provider token is verification evidence, never durable account identity.
5. An account must not lose its last recoverable identity without an explicit account-deletion path.
6. Linking a second provider does not create a second entitlement owner.
7. Provider email changes must not migrate or duplicate an account automatically.

Recommended uniqueness constraint:

```text
UNIQUE(provider, provider_subject)
```

## 4. Session invariants

- access credentials should be short-lived;
- refresh credentials are rotatable;
- only hashes/key references are persisted where practical;
- refresh reuse after rotation should be detectable if the chosen mechanism supports it;
- logout-current revokes one session;
- revoke-all invalidates every active session for the account;
- environment is part of the trust domain: DEV credentials never work in PROD.

No raw Google/Apple ID token should be retained beyond the minimum verification/diagnostic window required by implementation policy.

## 5. Entitlement model

Licensing resolves to feature entitlements rather than store products.

Example normalized feature IDs:

```text
prisma.core
prisma.fxlab
prisma.recording
prisma.advanced_fx
prisma.multi_device
prisma.program_stream
prisma.future.<feature>
```

Store SKU → feature mapping is backend configuration.

Example:

```text
com.prisma.pro.monthly
      ↓
[prisma.core,
 prisma.fxlab,
 prisma.recording,
 prisma.advanced_fx,
 prisma.multi_device]
```

Changing a store catalog therefore does not require changing feature code.

## 6. Entitlement revision

Every entitlement-changing transaction advances an account-level monotonic entitlement revision.

Conceptual entity:

```text
AccountEntitlementRevision
├── account_id
├── revision uint64
└── updated_at
```

The signed offline snapshot carries this revision. When online, a newer backend revision supersedes a cached snapshot.

## 7. Offline snapshot logical payload

```text
OfflineEntitlementSnapshot
├── schema_version
├── account_id
├── entitlement_revision
├── issued_at
├── refresh_after
├── offline_valid_until
├── entitlements[]
├── environment
├── key_id
└── signature
```

The client stores the snapshot, not server signing secrets.

Required behavior:

- signature verified locally;
- wrong environment rejected;
- account mismatch rejected;
- unknown future fields tolerated where schema rules allow;
- malformed signature fails closed;
- temporary Internet loss does not end an already active performance abruptly;
- hard-expired/revoked behavior follows the defined product grace policy.

## 8. Purchase idempotency

A store transaction must be processed idempotently.

Recommended uniqueness:

```text
UNIQUE(provider, provider_transaction_id)
```

Repeated client verification calls or duplicate store webhooks may refresh verification state but must not duplicate grants.

The backend, not the client, decides whether purchase evidence is valid.

## 9. Account deletion

Deletion is a workflow, not a single database row delete.

Conceptual states:

```text
ACTIVE
  ↓ request deletion
DELETION_PENDING
  ↓ revoke sessions / unlink or tombstone identities / apply retention rules
DELETED
```

Deletion processing must classify data into:

- delete immediately;
- retain temporarily for security/fraud/accounting obligations;
- anonymize;
- legal/financial retention if applicable.

Those retention policies are production/legal decisions and must be documented before store launch.

## 10. Appliance metadata

Future optional entity:

```text
AccountDeviceMetadata
├── account_id
├── device_id
├── user_label?
├── first_seen_at
└── last_seen_at
```

This relation is convenience metadata only. It never contains appliance pairing keys and never substitutes local appliance trust.

## 11. Indexing requirements

At minimum, efficient lookup is required for:

```text
external_identity(provider, provider_subject)
session(account_id, revoked_at)
entitlement(account_id, feature_id, status)
purchase(provider, provider_transaction_id)
account_event(account_id, occurred_at)
```

Exact index syntax belongs to the selected database adapter.

## 12. Secret classification

```text
PUBLIC/LOW SENSITIVITY
  account display name, feature IDs, non-secret IDs

PERSONAL
  email, provider profile metadata

SECRET
  refresh tokens, store verification credentials, backend signing keys

LOCAL-DEVICE SECRET
  appliance pairing credentials (not stored in account backend)
```

Logs must never include SECRET or LOCAL-DEVICE SECRET material.

## 13. Backup and recovery

Before production, backend design must define:

- encrypted backups;
- point-in-time recovery where supported;
- migration rollback/forward-fix policy;
- signing-key rotation without invalidating all legitimate offline snapshots unexpectedly;
- entitlement reconstruction from purchase records/account events;
- disaster recovery objectives.

## 14. Vendor independence

The model can be implemented on PostgreSQL or another transactional database, and the service may run on multiple cloud platforms. Vendor SDK object types must not become mobile-domain contracts.
