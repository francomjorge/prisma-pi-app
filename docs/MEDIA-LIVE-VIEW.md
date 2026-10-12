# Media & Live View Contract

**Status:** DESIGNED

## 1. Distinct media concepts

The app must never conflate these concepts:

```text
SOURCE_PREVIEW      unprocessed source observation
PROCESSED_PREVIEW   observation after active processing
PREVIEW_STREAM      monitoring transport carrying one of the previews
PROGRAM_OUTPUT      actual routed program output
```

A preview can be lower resolution/FPS than program output without changing synthesis semantics.

## 2. Live View responsibility

Live View is a monitoring surface that consumes a negotiated media endpoint. It does not own source selection, effect state or output routing.

## 3. Endpoint descriptor

```text
MediaEndpoint
├── endpoint_id
├── purpose
├── transport
├── codec_or_format
├── width
├── height
├── fps
├── audio
├── latency_class
├── quality_class
└── session_descriptor
```

## 4. Selection policy

The app selects from device-advertised endpoints according to:

1. requested purpose;
2. platform decoder support;
3. interactive latency;
4. requested quality;
5. bandwidth/network state;
6. power/resource policy;
7. fallback compatibility.

No screen should hard-code MJPEG, JPEG, RTSP or any other transport.

## 5. Current compatibility path

The present ESP32-S3 implementation exposes source/state behavior used by the web controller, including legacy source retrieval. That behavior is wrapped by `LegacyEsp32Connector` and adapted into the same `MediaEndpoint` abstraction used by future appliances.

## 6. Local mode

In LOCAL mode, the app does not need a remote preview stream. The local Media Runtime owns decode → processing → preview rendering directly.

## 7. Appliance mode

In APPLIANCE mode, the appliance owns processing. The app negotiates SOURCE_PREVIEW and/or PROCESSED_PREVIEW endpoints according to capabilities.

## 8. Hybrid mode

HYBRID remains reserved. Media endpoint and asset-transfer contracts must not prevent a phone source from later being transferred or routed to an appliance.

## 9. Rotation/fullscreen

Rotation and fullscreen are presentation state unless the user explicitly applies a transform node to the processing graph. Display rotation must not silently mutate program media.

## 10. Failure isolation

Media-channel failure does not automatically terminate a healthy control session. The app should:

- show preview as unavailable/stale;
- retain authoritative control state;
- renegotiate the endpoint;
- preserve commands when the control channel remains valid.

## 11. Initial validation

Before product UI:

- local image preview;
- local looping video preview;
- legacy appliance source preview adapter;
- endpoint negotiation against Mock Appliance;
- media loss/reconnect;
- source vs processed preview identity;
- rotate/fullscreen as presentation-only behavior;
- independent control-channel survival when preview fails.
