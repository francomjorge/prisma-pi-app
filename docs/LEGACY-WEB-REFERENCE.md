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

## 2. Legacy state transport

The current stable web controller uses patterns including:

```text
GET /api/state
GET /source/<filename>
```

Short-interval polling was used to synchronize web surfaces. This is legacy compatibility behavior for the app and must be isolated in `LegacyEsp32Connector`.

## 3. Legacy functional surfaces

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

## 4. Important reference branches

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

## 5. Migration rule

For every legacy web feature, classify it as:

```text
PRODUCT SEMANTIC      keep in Core/app contract
INTERACTION PATTERN   redesign natively but preserve intent
BROWSER IMPLEMENTATION discard/replace
APPLIANCE COMPAT      isolate behind connector/adapter
EXPERIMENT            require revalidation before product inclusion
```

## 6. Explicitly not carried forward

- browser canvas as the universal processing engine;
- polling every few hundred milliseconds as the normal state transport;
- direct filesystem-path semantics in product state;
- page count/HTML DOM as product architecture;
- effects and Motion as unrelated subsystems;
- hard-coded visual styling that prevents skins;
- unauthenticated local HTTP as the production security model.

## 7. Verification policy

A visual or interaction concept seen in the web controller is not automatically considered a validated mobile feature. The mobile implementation must pass its own functional/performance tests on target hardware.
