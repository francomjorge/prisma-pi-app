# Foundation CI Validation Evidence

This file records concrete validation evidence for the infrastructure branch. It is append-only in spirit: later runs may supersede earlier evidence, but prior evidence should not be rewritten as if it covered code that did not yet exist.

## 2026-10-12 — Green foundation gate

Validated head commit:

```text
156efa93d48805f1efcf8a4bfde3dba9e800898d
```

GitHub Actions workflow run:

```text
foundation-validation #138
run_id: 38215256850
```

All five jobs completed successfully:

```text
domain                        SUCCESS
security-contracts            SUCCESS
connector-session             SUCCESS
network-protocol-integration  SUCCESS
android-stack-spike           SUCCESS
```

Evidence included:

- `prisma_domain` analyze + tests;
- `prisma_security` analyze + fail-closed security-profile tests;
- `prisma_connector` analyze + session/reconnect/idempotency tests;
- real loopback Protocol 2.0 HTTP/WebSocket integration tests with fault injection;
- disposable Flutter/Android host generation;
- Flutter analysis and widget smoke test;
- Kotlin platform bridge compilation including Android NSD adapter;
- debug Android APK build.

This evidence is **static/CI validation**, not Android physical-device testing and not ESP32 hardware validation.

The production pairing profile remains PROPOSED even though the platform-neutral security contract passed CI.

---

## 2026-10-12 — Expanded green gate: legacy + storage + Keystore compile

Validated head commit:

```text
e6f2bdd6b816909d61cd0c3a72686526aeb7a580
```

GitHub Actions workflow run:

```text
foundation-validation #161
run_id: 38216669784
```

All six jobs completed successfully:

```text
domain                        SUCCESS
security-contracts            SUCCESS
storage-runtime               SUCCESS
connector-session             SUCCESS
network-protocol-integration  SUCCESS
android-stack-spike           SUCCESS
```

This gate additionally validates:

- read-only `LegacyEsp32Connector` state normalization against a local fixture matching the protected `/api/state` schema;
- explicit legacy capability limitations and `UNSUPPORTED_COMMAND` behavior;
- legacy 300 ms-style polling adapter feeding normal session generation reconciliation;
- managed storage layout and path traversal protection;
- transactional image/video import staging;
- SHA-256 integrity metadata;
- invalid-media rejection;
- metadata-commit rollback;
- interrupted import staging cleanup;
- orphan/missing durable-media recovery reporting;
- Android M0 source compilation including `NsdDiscoveryBridge.kt`;
- Android M0 source compilation including `KeystoreSecretBridge.kt`;
- Flutter analysis/tests;
- full debug Android APK build.

The Android Keystore result here proves **source/build integration only**. It does not prove secure-store runtime behavior on a physical phone; the diagnostic round-trip still needs to be run on-device.

The legacy adapter result proves adapter behavior against a deterministic HTTP fixture. It does not constitute physical validation against the ESP32-S3 appliance.
