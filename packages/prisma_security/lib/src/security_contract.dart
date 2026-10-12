import 'dart:typed_data';

import 'package:prisma_domain/prisma_domain.dart';

enum ApplianceTrustState {
  unseen,
  discovered,
  pairingRequired,
  pairing,
  trusted,
  authenticated,
  revoked,
  error,
}

abstract final class SecurityProfileIds {
  static const legacyUnauthenticated = 'LEGACY_UNAUTHENTICATED';
  static const protocommSecurity2 = 'PROTOCOMM_SECURITY2';
  static const tlsPinnedSessionV1 = 'TLS_PINNED_SESSION_V1';
}

class SecurityProfilePolicy {
  const SecurityProfilePolicy({
    this.allowLegacyUnauthenticated = false,
    this.preference = const [
      SecurityProfileIds.tlsPinnedSessionV1,
      SecurityProfileIds.protocommSecurity2,
    ],
  });

  final bool allowLegacyUnauthenticated;
  final List<String> preference;

  String choose(Iterable<String> advertised) {
    final available = advertised.toSet();
    for (final profile in preference) {
      if (available.contains(profile)) return profile;
    }
    if (allowLegacyUnauthenticated &&
        available.contains(SecurityProfileIds.legacyUnauthenticated)) {
      return SecurityProfileIds.legacyUnauthenticated;
    }
    throw StateError('No acceptable appliance security profile');
  }
}

class PairingRequest {
  const PairingRequest({
    required this.device,
    required this.securityProfile,
    this.userCode,
    this.expectedDeviceFingerprint,
  });

  final DeviceDescriptor device;
  final String securityProfile;
  final String? userCode;
  final String? expectedDeviceFingerprint;
}

class ApplianceCredentialRef {
  const ApplianceCredentialRef({
    required this.deviceId,
    required this.credentialId,
    required this.securityProfile,
    required this.createdAtMs,
    this.deviceFingerprint,
  });

  final String deviceId;
  final String credentialId;
  final String securityProfile;
  final int createdAtMs;
  final String? deviceFingerprint;
}

class PairingResult {
  const PairingResult({
    required this.credential,
    required this.trustState,
  });

  final ApplianceCredentialRef credential;
  final ApplianceTrustState trustState;
}

class ApplianceAuthSession {
  const ApplianceAuthSession({
    required this.deviceId,
    required this.sessionId,
    required this.securityProfile,
    required this.expiresAtMs,
  });

  final String deviceId;
  final String sessionId;
  final String securityProfile;
  final int expiresAtMs;
}

/// Platform-backed secret storage. Implementations belong in Android/iOS
/// adapters and must map to Keystore/Keychain-class secure storage.
abstract interface class ApplianceSecureStore {
  Future<void> writeSecret(String credentialId, Uint8List secret);
  Future<Uint8List?> readSecret(String credentialId);
  Future<void> deleteSecret(String credentialId);
}

/// Cryptographic pairing/authentication is delegated behind this interface.
/// The app layer sees trust transitions and opaque credential references only.
abstract interface class AppliancePairingClient {
  Future<PairingResult> pair(PairingRequest request);

  Future<ApplianceAuthSession> authenticate({
    required DeviceDescriptor device,
    required ApplianceCredentialRef credential,
  });

  Future<void> revoke({
    required DeviceDescriptor device,
    required ApplianceCredentialRef credential,
  });
}
