# Legacy Web Controller Reference

**Purpose:** preserve proven behavior and experiments from the existing PRISMA-PI Lite web controller so the mobile app can reuse concepts without inheriting browser limitations.

## 1. Stable web concepts already demonstrated

The existing controller established the following product behaviors:

- PRISMA-PI Lite landing/home identity;
- PiCore / quick control with source, power, intensity and RANDOM/BYPASS semantics;
- Live View of appliance source content;
- fullscreen preview;
- preview rotation;
- read-only synchronization of appliance effect values;
- keyboard navigation/shortcuts experiments;
- global state synchronization with the physical appliance;
- visual FX processing prototypes in the browser;
- Motion FX prototypes;
- FX Lab with an ordered processing chain;
- source/layer concepts;
- output aspect/resolution experiments;
- recording experiments;
- generators/ASCII/chroma experiments;
- detach/fullscreen/zoom experiments.

These are behavioral references, not a requirement to copy the exact page structure.

## 2. Protected current ESP32 baseline

The current `main` branch of the Waveshare ESP32-S3 appliance repository has been inspected directly. Its compatibility surface is intentionally much smaller than the historical experimental branches.

Current stable network behavior:

```text
SoftAP SSID: PRISMA-PI-<MAC suffix>
SoftAP IP:   192.168.4.1
Wi-Fi auth:  OPEN
Transport:   plaintext HTTP

GET /
GET /style.css
GET /api/state
GET /source/<filename>
```

The current stable baseline exposes **no remote command endpoint** and **no native event/WebSocket channel**. The web controller reads authoritative state and source content; control mutations continue to originate from the appliance-side control path.

This baseline is protected compatibility behavior. It is not the production security model.

## 3. Exact legacy state schema

Current `/api/state` returns:

```json
{
  "on": true,
  "mode": 0,
  "intensity": 61,
  "generation": 1,
  "filename": "F1_MOON.JPG",
  "effects": [false, false, false, false, false, true],
  "values": [50, 50, 50, 50, 50, 50]
}
```

Verified semantics from the current firmware:

```text
mode 0 → RANDOM
mode 1 → BYPASS

six effect slots → PIXEL, GLITCH, POSTER, HUE, MIRROR, MIX
MIX             → always enabled by the stable web-state endpoint
filename        → current appliance source filename
generation      → increments when the serialized web-visible state changes
```

`GET /source/<filename>` validates a simple safe filename, reads `/storage/<filename>`, and currently responds as `image/jpeg`.

## 4. Mobile compatibility adapter

`packages/prisma_connector/lib/src/legacy_esp32_connector.dart` now isolates this behavior behind the normal `PrismaConnector` contract.

The adapter:

- probes `/api/state` during connect;
- maps the legacy JSON into `PrismaState`;
- maps the six legacy effect slots to the six known Core FX IDs;
- exposes the current JPEG source as a normalized `MediaEndpoint`;
- advertises the actual limitations through `DeviceCapabilities`;
- synthesizes state events by polling `/api/state` (300 ms reference default);
- uses legacy `generation` changes to drive normal session resynchronization;
- reports generation reset/poll transport failure as a degraded session condition;
- rejects remote commands explicitly with `UNSUPPORTED_COMMAND`;
- labels the security profile `LEGACY_UNAUTHENTICATED`.

This means product/application code does not need to know that the old device uses polling, a fixed HTTP source path or a different JSON schema.

### Deliberate limitation

The adapter is **read-only** because that is what the protected stable firmware actually supports remotely today. We do not invent a write API, patch the protected baseline, or falsely advertise capabilities simply to make the app contract look symmetrical.

If remote control is later added to a new appliance firmware, that belongs to Protocol 2.0 or a separately hardware-validated legacy extension.

## 5. Legacy functional surfaces

### Home
Brand/identity landing surface.

### PiCore / Quick Control
Observed controls include:

- current/now-playing source;
- ON/OFF;
- intensity;
- RANDOM/BYPASS mode.

### Live View / Image
Displays appliance-provided source image/content with fullscreen and later rotation support.

### Effects
Legacy effect controls/readouts included:

```text
PIXEL
GLITCH
POSTER
HUE
MIRROR
MIX
```

The mobile architecture does not freeze these as six permanent algorithm names. It preserves the command/state semantics and migrates effect execution into the processing graph.

### Motion
Experiments included:

```text
PULSE
DRIFT
ROTATE
WAVE
SHAKE
FEEDBACK
```

The mobile app merges Visual FX and Motion FX into one ordered `FX Rack` / processing graph rather than maintaining artificial isolated pages.

### FX Lab
The web experiments progressed beyond simple controls into an actual browser graphics pipeline with processing order, canvas preview and advanced tools.

The mobile FX Lab should preserve the useful interaction concepts while implementing the runtime using native/mobile media infrastructure rather than browser canvas as the architectural foundation.

## 6. Important reference branches

Relevant historical branches in the ESP32-S3 repository include:

```text
m4.2-vintage-web-synth
m4.3-web4-readonly
m4.9-global-web-sync
v1.0-web-keyboard-nav
v1.1-web-desktop-nav
v0-fxengine-infra
v0-fxengine-pixel-v1
v0-fxengine-glitch-v1-fullscreen
v0-fxengine-allfx-v1
v0-fxengine-allfx-ui-polish
v0-motionfx-v1-all
v0-fxlab-page5
v0-fxlab-rotate
v0-fxlab-unified-pipeline-v1
web-fxlab-console-layout-v2
web-fxlab-mobile-rotation-v3
web-fxlab-generator-v4
web-fxlab-output-ascii-v5
web-fxlab-recording-v6
web-fxlab-recording-v7-part1
web-fxlab-detach-aspect-v8
web-fxlab-reset-detach-zoom-v9
web-fxlab-generators-chroma-efficiency-v10
web-fxlab-performance-cache-v11
web-fxlab-sources-v1
web-fxlab-feature-tuning-v12b
web-fxlab-generators-ux-v12
web-fxlab-generators-ux-v12-redo
web-fxlab-generators-refine-v12c
```

Before recreating a feature, inspect the most relevant historical branch and record what was actually proven vs merely prototyped.

## 7. Migration rule

For every legacy web feature, classify it as:

```text
PRODUCT SEMANTIC      keep in Core/app contract
INTERACTION PATTERN   redesign natively but preserve intent
BROWSER IMPLEMENTATION discard/replace
APPLIANCE COMPAT      isolate behind connector/adapter
EXPERIMENT            require revalidation before product inclusion
```

## 8. Explicitly not carried forward

- browser canvas as the universal processing engine;
- polling every few hundred milliseconds as the normal Protocol 2.0 state transport;
- direct filesystem-path semantics in product state;
- page count/HTML DOM as product architecture;
- effects and Motion as unrelated subsystems;
- hard-coded visual styling that prevents skins;
- unauthenticated local HTTP as the production security model.

## 9. Verification policy

A visual or interaction concept seen in the web controller is not automatically considered a validated mobile feature. The mobile implementation must pass its own functional/performance tests on target hardware.

The `LegacyEsp32Connector` can be statically/integration tested against a local HTTP fixture, but it is not `HARDWARE_TESTED` until run against the physical protected ESP32-S3 baseline.
