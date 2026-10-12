import 'package:prisma_security/prisma_security.dart';
import 'package:test/test.dart';

void main() {
  group('SecurityProfilePolicy', () {
    test('prefers strongest mutually supported profile', () {
      const policy = SecurityProfilePolicy();
      expect(
        policy.choose(const [
          SecurityProfileIds.protocommSecurity2,
          SecurityProfileIds.tlsPinnedSessionV1,
        ]),
        SecurityProfileIds.tlsPinnedSessionV1,
      );
    });

    test('accepts protocomm security2 when pinned TLS session is unavailable', () {
      const policy = SecurityProfilePolicy();
      expect(
        policy.choose(const [SecurityProfileIds.protocommSecurity2]),
        SecurityProfileIds.protocommSecurity2,
      );
    });

    test('fails closed instead of silently selecting legacy insecure mode', () {
      const policy = SecurityProfilePolicy();
      expect(
        () => policy.choose(const [SecurityProfileIds.legacyUnauthenticated]),
        throwsStateError,
      );
    });

    test('legacy insecure mode requires explicit compatibility policy', () {
      const policy = SecurityProfilePolicy(allowLegacyUnauthenticated: true);
      expect(
        policy.choose(const [SecurityProfileIds.legacyUnauthenticated]),
        SecurityProfileIds.legacyUnauthenticated,
      );
    });
  });
}
