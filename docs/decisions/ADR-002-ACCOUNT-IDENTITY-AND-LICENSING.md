# ADR-002 — Account Identity and Licensing Boundary

**Status:** PROPOSED  
**Date:** 2026-10-12

## Context

PRISMA-PI App requires a stable user account for future licensing, subscriptions, purchases, restore-purchases and optional cloud services. Android should start with Google account login for low-friction onboarding. The product must later ship on iOS and remain robust during offline live-performance use.

## Decision

1. PRISMA owns a provider-independent `account_id`.
2. Google is the default Android identity provider.
3. Google credentials are verified by a PRISMA backend; the client never self-authorizes a license from an unverified provider token.
4. Provider `(provider, subject)` is the stable external identity key. Email is profile/contact metadata, not the primary key.
5. The backend issues PRISMA application sessions after provider verification.
6. Licensing is modeled as normalized account entitlements, separate from authentication.
7. Store purchases are verified server-side before durable entitlements are granted.
8. Offline creative/performance use is supported through a backend-issued cached entitlement snapshot with explicit freshness/grace semantics.
9. Cloud account identity is strictly separate from local appliance pairing/trust.
10. The provider adapter remains replaceable. iOS reserves Sign in with Apple; optional passwordless email login remains a future provider.
11. Local media/projects are not uploaded merely because the user signs in.

## Why not use the Google email as the account key?

Email addresses can change. The provider subject is the stable Google identity identifier, while PRISMA's own `account_id` allows multiple future identity providers to link to the same product account without rewriting license ownership.

## Why not let Google/Firebase identity directly represent licenses?

Identity provider state answers who authenticated. PRISMA entitlement state answers what the product account can use. Keeping the boundaries separate allows Play/App Store purchases, promo licenses, bundles, support grants and future billing systems to converge on one product model.

## Why preserve offline entitlements?

PRISMA is a live visual/performance product. Network reachability is not a safe runtime dependency. An authenticated/licensed user must not lose an active local performance because Internet access disappears.

## iOS consequence

The account domain cannot be Google-only. Apple App Store login rules may require an equivalent privacy-preserving login option when a third-party social login is used for the app's primary account. Sign in with Apple is therefore reserved in the provider model before iOS implementation begins.

## Consequences

### Positive

- stable product identity independent of login vendor;
- licensing is portable across providers/stores;
- offline show reliability;
- appliance security stays local and independent;
- future email/Apple providers do not require domain redesign;
- backend trust boundary is explicit.

### Cost

- requires a minimal PRISMA backend before production login/licensing;
- requires session, entitlement and purchase-verification infrastructure;
- requires account deletion/privacy lifecycle;
- requires provider configuration in Google/Apple consoles.

## Deferred decisions

- concrete backend hosting/vendor;
- exact session token mechanism and TTLs;
- exact offline entitlement grace duration;
- whether passwordless email ships in V1;
- billing/subscription product catalog;
- cloud project/media sync;
- final production Android package/application ID.

## Acceptance conditions

ADR can move to ACCEPTED only when:

- Google Android sign-in spike succeeds with the final account-flow abstraction;
- backend token verification is demonstrated;
- account/entitlement domain tests pass;
- offline entitlement behavior is defined and tested;
- iOS provider strategy is confirmed against current App Store rules;
- no appliance trust code depends on cloud login tokens.
