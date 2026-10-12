enum IdentityProvider { google, apple, emailLink, future }

enum AccountStatus { active, disabled, deletionPending }

enum AuthState {
  signedOut,
  authenticating,
  authenticated,
  readyOnline,
  readyOffline,
  reauthRequired,
}

enum EntitlementStatus {
  active,
  offlineFresh,
  offlineGrace,
  refreshRequired,
  expired,
  revoked,
}

enum EntitlementSource {
  googlePlay,
  appleAppStore,
  promo,
  admin,
  legacy,
  bundle,
}

class ExternalIdentity {
  const ExternalIdentity({
    required this.provider,
    required this.subject,
    this.email,
    this.emailVerified = false,
  });

  final IdentityProvider provider;
  final String subject;
  final String? email;
  final bool emailVerified;

  String get stableKey => '${provider.name}:$subject';
}

class PrismaAccount {
  const PrismaAccount({
    required this.accountId,
    required this.identities,
    this.displayName,
    this.primaryEmail,
    this.emailVerified = false,
    this.status = AccountStatus.active,
    this.profileGeneration = 0,
  });

  final String accountId;
  final List<ExternalIdentity> identities;
  final String? displayName;
  final String? primaryEmail;
  final bool emailVerified;
  final AccountStatus status;
  final int profileGeneration;

  ExternalIdentity? identityFor(IdentityProvider provider) {
    for (final identity in identities) {
      if (identity.provider == provider) return identity;
    }
    return null;
  }
}

class LicenseEntitlement {
  const LicenseEntitlement({
    required this.entitlementId,
    required this.accountId,
    required this.productId,
    required this.tier,
    required this.status,
    required this.source,
    required this.features,
    required this.revision,
    this.validFrom,
    this.validUntil,
    this.offlineGraceUntil,
  });

  final String entitlementId;
  final String accountId;
  final String productId;
  final String tier;
  final EntitlementStatus status;
  final EntitlementSource source;
  final Set<String> features;
  final int revision;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? offlineGraceUntil;

  bool allows(String feature) {
    if (status == EntitlementStatus.expired ||
        status == EntitlementStatus.revoked ||
        status == EntitlementStatus.refreshRequired) {
      return false;
    }
    return features.contains(feature);
  }
}

class AccountSessionSnapshot {
  const AccountSessionSnapshot({
    required this.authState,
    this.account,
    this.entitlements = const [],
  });

  final AuthState authState;
  final PrismaAccount? account;
  final List<LicenseEntitlement> entitlements;

  bool hasFeature(String feature) =>
      entitlements.any((entitlement) => entitlement.allows(feature));
}
