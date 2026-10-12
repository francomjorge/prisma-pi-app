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
