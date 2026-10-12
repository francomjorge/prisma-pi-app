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

---

## 2026-10-12 — Expanded green gate: SQLite + media runtime + Media3/OES GPU path

Validated head commit:

```text
74e4c8d6ad9584ae997f849782ce60a957840fef
```

GitHub Actions workflow run:

```text
foundation-validation #216
run_id: 38269436921
```

All seven jobs completed successfully:

```text
domain                        SUCCESS
security-contracts            SUCCESS
storage-runtime               SUCCESS
media-runtime-contract        SUCCESS
connector-session             SUCCESS
network-protocol-integration  SUCCESS
android-stack-spike           SUCCESS
```

This gate additionally validates in CI:

- durable `SqliteMediaMetadataRepository` schema creation/migration, reopen persistence, uniqueness constraints and deterministic retrieval tests;
- platform-neutral local-media session contracts;
- contain/cover/fill/fit-width/fit-height/native-pixel/scale-down decode-size planning;
- bounded image/cache/decoder/render-surface resource budgets;
- `MediaResourceRegistry` ownership, byte accounting and idempotent release semantics;
- Android managed-media bridge source compilation;
- target-sized native still-image surface compilation;
- Media3/ExoPlayer native playback-surface compilation;
- Android `SurfaceTexture` + `Surface` + `GL_TEXTURE_EXTERNAL_OES` + GLSL pass-through GPU-path compilation;
- Flutter diagnostic routing for video through the GPU texture platform view;
- full disposable Android debug APK build with Media3 dependencies.

A previous run exposed a Dart language-compatibility defect in a new media test (`digit-separators` while the package minimum remains Dart 3.4). The test was corrected without raising the package minimum, and this run confirms analysis/tests pass on the supported constraint.

This gate does **not** prove that a physical Android device successfully decodes video into the OES texture, that the path is zero-copy on a particular codec/device, or that memory/thermal behavior is production-safe. Those remain physical-device acceptance gates.

The GPU shader in this baseline is intentionally pass-through. Real PRISMA FX processing is not claimed by this evidence.

---

## 2026-10-12 — Neutral processing runtime + Android diagnostic FX adapter

Validated head commit:

```text
7545dee1564bf2613a7136d94fc30c4176f94a18
```

GitHub Actions workflow run:

```text
foundation-validation #234
run_id: 38274554710
```

All eight jobs completed successfully:

```text
domain                        SUCCESS
security-contracts            SUCCESS
storage-runtime               SUCCESS
media-runtime-contract        SUCCESS
processing-runtime            SUCCESS
connector-session             SUCCESS
network-protocol-integration  SUCCESS
android-stack-spike           SUCCESS
```

This gate additionally validates in CI:

- the new pure-Dart `prisma_processing_runtime` package;
- `ProcessingGraph` → local `ProcessingPlan` compilation for MOBILE/BOTH execution targets;
- deterministic active-node ordering;
- strict rejection of unsupported node types by default;
- required-backend-capability enforcement;
- explicit compatibility bypass diagnostics when that policy is deliberately selected;
- active-node limit enforcement;
- schema-versioned platform serialization containing control data only;
- opaque input/output transport validation;
- Flutter diagnostic compilation of the domain graph into `ProcessingPlan` schema v1;
- Android native parsing of that plan without receiving raw image/video frame payloads through Dart;
- diagnostic `POSTER` and `GRAYSCALE` mapping in the SurfaceTexture/OES GLSL adapter;
- full disposable Android debug APK build with the neutral processing-plan boundary wired into the native GPU path.

This proves the **software boundary and build integration**, not physical GPU execution. It does not yet prove decoded frames traverse the POSTER shader correctly on a phone, that the path is zero-copy on a particular device, or that a multi-node chain can run without CPU readback.

The Android diagnostic adapter is intentionally capped at one active processing node. The next GPU implementation gate is ordered multi-pass execution with native ping-pong render targets while keeping framebuffer/texture identifiers out of the domain/runtime contract.
