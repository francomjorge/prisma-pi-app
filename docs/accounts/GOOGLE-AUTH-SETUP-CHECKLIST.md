# Google Authentication — Production Setup Checklist

**Status:** Preparation only  
**Do not finalize during M0 disposable spike**

This checklist exists so the final Android identity/signing configuration is not improvised later.

## 1. Before creating production OAuth credentials

Freeze or explicitly choose:

- final Android application/package ID;
- production signing strategy;
- Google Play App Signing usage;
- DEV/STAGING/PRODUCTION environment naming;
- backend production hostname/audience strategy;
- public product name and support/contact information.

Do not bind production OAuth configuration to the temporary M0 package identity.

## 2. Google project/auth configuration

Prepare a Google Cloud/Auth project and configure:

- app/product branding;
- OAuth consent configuration;
- Android client identity using final package + signing certificate fingerprints;
- server/web client ID used as backend audience for Google ID-token exchange;
- development/staging client IDs kept separate from production;
- test users/restrictions when applicable during pre-production verification.

Google's current Android guidance uses Credential Manager for Sign in with Google and requires Google Auth Platform client configuration.

## 3. Android app integration

Production adapter responsibilities:

```text
GoogleIdentityAdapter
├── requestCredential()
├── obtainIdToken()
├── handleCancel()
├── handleProviderError()
└── clearProviderStateWhenAppropriate()
```

The adapter returns a provider credential to the application auth service. It does not create licenses and does not directly mutate feature entitlement state.

## 4. Backend exchange

The app sends the Google ID token to the PRISMA backend over HTTPS.

Backend verifies:

- signature;
- audience (`aud`) matches an approved PRISMA client ID;
- issuer (`iss`);
- expiration (`exp`);
- provider subject (`sub`).

The backend maps `(GOOGLE, sub)` to a PRISMA `account_id` and returns a PRISMA session.

Never trust a client-supplied email or Google numeric/string user ID alone as proof of authentication.

## 5. Store signing transition

When Play App Signing is enabled, ensure the OAuth Android configuration includes the certificate identity actually used by distributed builds, not only local debug signing.

Maintain a written mapping:

```text
ENVIRONMENT -> PACKAGE ID -> SIGNING CERTIFICATE -> GOOGLE CLIENT ID -> BACKEND AUDIENCE
```

## 6. Brand verification

Before public production rollout, verify the current Google Auth Platform branding/verification requirements so the intended product name and consent experience are shown to users.

## 7. Secrets rule

Safe in app/repository when designed to be public identifiers:

- OAuth client IDs;
- backend public URLs;
- environment identifiers.

Never commit:

- backend private signing keys;
- service-account private keys;
- session signing secrets;
- entitlement signing private keys;
- purchase verification credentials that are intended to remain secret.

## 8. Required pre-production tests

- debug/dev Google login;
- staging signed build Google login;
- Play-distributed internal-test build Google login;
- wrong audience rejected by backend;
- expired token rejected;
- logout and re-login;
- existing account restored on another Android device;
- changed Google email does not create a duplicate PRISMA account;
- network loss after successful login uses cached PRISMA session/entitlement policy correctly;
- provider credential never appears in logs.

## 9. iOS note

Google account support can later exist on iOS too, but the iOS release must also satisfy current App Store login-service requirements. The account domain therefore cannot assume that Google is the only identity provider.

## 10. Official references to re-check at implementation time

- https://developer.android.com/identity/sign-in/credential-manager-siwg
- https://developers.google.com/identity/sign-in/android/backend-auth

Platform setup guidance changes over time; re-check these official sources when production credentials are created.
