# ADR-001 — Mobile Application Stack

**Status:** PROPOSED — must pass technical spike before ACCEPTED  
**Decision target:** Android first, iOS second

## Context

PRISMA-PI App needs a shared product/UI codebase across Android and iOS, custom skinnable controls, drag/drop, hardware-keyboard input, local file/library management and access to high-performance platform media APIs.

The existing web controller is useful as a behavioral prototype but browser/WebView constraints are one of the reasons for creating the mobile app.

## Proposed decision

Use **Flutter** for the application/presentation layer and shared cross-platform feature code, with explicit native media backends for processing paths that require platform acceleration.

Conceptual split:

```text
Flutter
├── presentation/navigation
├── skin system
├── application/session logic
├── library/project UX
├── device/control UX
└── shared domain/protocol packages

Native Android backend
├── platform media decoding/encoding
├── hardware acceleration
├── low-level output integration
└── platform-specific performance services

Native iOS backend (later)
├── AVFoundation/media services
├── Metal/accelerated processing as required
└── platform-specific output services
```

## Why not a WebView/PWA as product runtime

- would preserve browser media/filesystem limitations we are trying to remove;
- would retain browser canvas/DOM coupling;
- would make native media acceleration and platform integration indirect;
- would weaken the clean connector/storage/security boundaries being established.

The web controller remains a separate secondary/compatibility surface.

## Why not put all processing in Dart

The app should not assume Dart is the optimal runtime for every media operation. The processing graph contract stays platform-neutral while performance-critical backends can use native APIs.

## Required spike before acceptance

Before freezing Flutter as ACCEPTED, prove on a representative Android phone:

1. application bootstrap/build pipeline;
2. platform channel/FFI boundary to a native test backend;
3. image import and persistent managed storage;
4. looping video decode/preview;
5. sustained frame delivery with no pathological copy overhead;
6. fullscreen/external-display feasibility investigation;
7. hardware keyboard events;
8. local-network/mDNS permissions and discovery feasibility.

If the spike exposes unacceptable media/runtime overhead, this ADR must be revisited before product UI implementation.
