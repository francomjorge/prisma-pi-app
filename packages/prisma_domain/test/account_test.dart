import 'package:prisma_domain/prisma_domain.dart';
import 'package:test/test.dart';

void main() {
  group('account identity', () {
    test('provider subject is separate from PRISMA account id', () {
      const identity = ExternalIdentity(
        provider: IdentityProvider.google,
        subject: 'google-sub-123',
        email: 'artist@example.com',
        emailVerified: true,
      );
      const account = PrismaAccount(
        accountId: 'prisma-account-uuid',
        identities: [identity],
        primaryEmail: 'artist@example.com',
        emailVerified: true,
      );

      expect(account.accountId, isNot(identity.subject));
      expect(account.identityFor(IdentityProvider.google)?.stableKey,
          'google:google-sub-123');
    });

    test('email changes do not alter provider stable identity', () {
      const before = ExternalIdentity(
        provider: IdentityProvider.google,
        subject: 'google-sub-123',
        email: 'old@example.com',
      );
      const after = ExternalIdentity(
        provider: IdentityProvider.google,
        subject: 'google-sub-123',
        email: 'new@example.com',
      );

      expect(before.stableKey, after.stableKey);
    });
  });

  group('entitlements', () {
    const base = LicenseEntitlement(
      entitlementId: 'ent-1',
      accountId: 'acct-1',
      productId: 'prisma_pro',
      tier: 'pro',
      status: EntitlementStatus.active,
      source: EntitlementSource.googlePlay,
      features: {'fx_lab', 'recording'},
      revision: 1,
    );

    test('active entitlement grants declared feature', () {
      expect(base.allows('fx_lab'), isTrue);
      expect(base.allows('unknown'), isFalse);
    });

    test('revoked entitlement grants nothing', () {
      const revoked = LicenseEntitlement(
        entitlementId: 'ent-1',
        accountId: 'acct-1',
        productId: 'prisma_pro',
        tier: 'pro',
        status: EntitlementStatus.revoked,
        source: EntitlementSource.googlePlay,
        features: {'fx_lab', 'recording'},
        revision: 2,
      );
      expect(revoked.allows('fx_lab'), isFalse);
    });

    test('offline grace remains explicitly usable', () {
      const grace = LicenseEntitlement(
        entitlementId: 'ent-1',
        accountId: 'acct-1',
        productId: 'prisma_pro',
        tier: 'pro',
        status: EntitlementStatus.offlineGrace,
        source: EntitlementSource.googlePlay,
        features: {'fx_lab'},
        revision: 2,
      );
      expect(grace.allows('fx_lab'), isTrue);
    });
  });
}
