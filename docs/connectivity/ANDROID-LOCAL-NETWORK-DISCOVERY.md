# PRISMA-PI App — Android Local Network Discovery

**Status:** Draft / platform constraint captured  
**Date:** 2026-10-12

## Purpose

Define the Android-specific discovery boundary for finding and reconnecting PRISMA appliances on a LAN without leaking Android APIs into `prisma_domain` or `prisma_connector`.

The cross-platform layer now exposes `PrismaDiscoveryProvider` and `PrismaDiscoveryCoordinator`. Android NSD/mDNS is one provider behind that contract.

## Service identity

Protocol 2.0 reserves DNS-SD/mDNS service type:

```text
_prisma-pi._tcp
```

Expected TXT/bootstrap fields should remain small and non-secret:

```text
device_id
protocol_major
protocol_minor
pairing_required
capability_digest
model (optional)
```

Discovery metadata is not authentication.

## Android API direction

Use Android `NsdManager` / platform mDNS rather than implementing a raw multicast DNS stack in Dart.

The Android adapter resolves a service and emits a normalized `DiscoveryRecord` containing:

```text
device_id
host
control_port
protocol
pairing_required
capability_digest
```

The rest of the app does not depend on `NsdServiceInfo`, callbacks, Android permissions, or Android SDK version checks.

## Local-network privacy changes

Android's local-network privacy model is changing. Current Android developer guidance states that apps targeting Android 17 / SDK 37 or newer that need broad direct local-network access must declare/request the local-network runtime permission. Android also provides an `NsdManager` system-mediated service picker path (`DiscoveryRequest.FLAG_SHOW_PICKER`) that can allow access to a user-selected service without broad LAN permission.

PRISMA must support:

- automatic discovery of PRISMA appliances;
- persistent reconnect;
- potentially multiple appliances;
- direct HTTP/WebSocket/media traffic;
- operation while the user is performing, without repeatedly invoking a picker.

Therefore the system picker is useful as a privacy-preserving optional/manual pairing path, but it may not be sufficient as the only production discovery mechanism for multi-device/persistent operation.

No final manifest/runtime-permission implementation is frozen until the production Android target SDK and tested behavior are known.

## Adapter boundary

```text
Android NsdManager
      ↓
AndroidNsdDiscoveryProvider
      ↓
PrismaDiscoveryProvider
      ↓
PrismaDiscoveryCoordinator
      ↓
DiscoveryRecord
      ↓
Protocol2LanConnector
```

A future iOS Bonjour provider should emit the same `DiscoveryRecord` contract.

## Deduplication

The coordinator deduplicates repeated observations by stable `device_id` and a connection fingerprint. A record is re-emitted when endpoint/protocol/pairing/capability-digest data changes.

This lets mDNS, a manually entered endpoint and future USB discovery coexist without feature code receiving duplicate device cards.

## Failure handling

Discovery failure is separate from an established session failure.

Once a session has a resolved `DiscoveryRecord`, temporary mDNS disappearance must not immediately tear down a healthy TCP/WebSocket session. Conversely, reconnect may trigger re-resolution when the known endpoint no longer responds or the device advertises a changed endpoint.

## Security rules

Discovery TXT records must never contain:

- Google/Apple account tokens;
- PRISMA cloud access/refresh tokens;
- appliance session tokens;
- pairing secrets;
- license snapshots;
- user email.

Discovery identifies a candidate endpoint only. Pairing/authentication establishes trust.

## Validation gates

Before accepting Android discovery as production-ready:

1. compile against the chosen production target SDK;
2. validate on at least one modern Android version with local-network protections enabled;
3. validate permission denied/revoked flows;
4. validate Wi-Fi reconnect and access-point changes;
5. validate duplicate device advertisements;
6. validate two or more PRISMA devices on the same LAN;
7. validate device IP change while `device_id` remains stable;
8. verify app never treats mDNS data as authenticated identity;
9. verify local appliance control remains independent from Google/PRISMA cloud availability.

## Authoritative Android references

- Android Developers — Local network permission: https://developer.android.com/privacy-and-security/local-network-permission
- Android Developers — Android 16 behavior changes / local network: https://developer.android.com/about/versions/16/behavior-changes-16
- Android API — `NsdManager` and `Context.NSD_SERVICE`: https://developer.android.com/reference/android/net/nsd/NsdManager
