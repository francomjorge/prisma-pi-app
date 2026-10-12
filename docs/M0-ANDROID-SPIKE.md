# M0 — Android Stack Spike

**Status:** IMPLEMENTED / CI validation pending  
**Scope:** infrastructure proof only; not product UI

## Objective

Validate the proposed Android-first mobile stack before the production application is generated. This spike must prove the parts of the stack that could invalidate the architecture early.

## Current implementation

The repository now contains:

- a disposable Flutter diagnostic harness under `spikes/android_flutter/`;
- a Kotlin `FlutterActivity` with a minimal `MethodChannel` named `prisma.pi/media`;
- hardware keyboard event capture through Flutter's `KeyboardListener`;
- a platform-neutral Dart domain package under `packages/prisma_domain/`;
- CI that generates a fresh Android host, injects the spike sources, runs analysis/tests and builds a debug APK.

The disposable host uses the temporary Android package identity `com.prismapi.prisma_mobile_spike`. It is **not** the future Google Play application ID.

## What this proves when CI passes

- current stable Flutter tooling can bootstrap an Android host;
- Dart/Flutter code compiles independently of the final product UI;
- the native Android/Kotlin boundary compiles with the application;
- the app can represent hardware-keyboard input through the same input layer that will later map to PRISMA actions;
- the repository can run repeatable Dart tests and build an APK in CI.

## Still required before M0 is complete

The following require subsequent targeted validation, preferably on a physical Android device:

1. actual `MethodChannel` round trip at runtime;
2. sustained native media frame delivery without pathological copies;
3. image import through Android document/media APIs;
4. looping hardware-decoded video playback;
5. mDNS/DNS-SD discovery and local-network permission behavior;
6. external display / fullscreen feasibility;
7. hardware keyboard events from a real USB/Bluetooth keyboard;
8. lifecycle tests: background/foreground, screen rotation and connection recovery.

M0 must not be marked HARDWARE_TESTED until those checks have run on target hardware.

## Decision gate

ADR-001 (Flutter presentation/application layer plus native Android/iOS media backends) remains **PROPOSED** until this spike and the physical media/network tests pass.
