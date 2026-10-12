# UI, Input & Skin Contract

**Status:** Functional boundaries defined; visual implementation intentionally deferred

## 1. Purpose

Define UI architecture without freezing the final screens. The first production UI begins only after infrastructure gates are satisfied.

## 2. Functional areas

```text
Performance / PiCore
Live View
FX Rack
FX Lab
Library
Devices & Routing
System
```

### Performance / PiCore
Fast performance controls: active source, power, global intensity, RANDOM/BYPASS and essential status.

### Live View
Monitoring of local or appliance source/processed media, fullscreen/rotation presentation controls and endpoint/status feedback.

### FX Rack
Unified ordered chain for Visual FX + Motion FX + modules. Replaces the legacy conceptual split between Effects and Motion as separate isolated pages.

### FX Lab
Advanced workspace for layers, source composition, generators, chain editing, output controls, recording and experimental processing.

### Library
Managed local images, videos, recordings, projects and explicit remote asset transfer.

### Devices & Routing
Discovery, pairing, active session, capabilities, input/output routing and connector state.

### System
Version, diagnostics, storage status, reset/settings and security/device trust management.

## 3. UI does not own domain state

Presentation components render state and issue commands. They do not keep authoritative copies of power, source, effect values, processing order or device state.

## 4. Input abstraction

All physical/virtual input maps to named product actions.

```text
Touch / Mouse / Hardware Keyboard
              ↓
          Input Mapper
              ↓
          Product Action
              ↓
           Command Bus
```

Example actions:

```text
NAV_NEXT
NAV_PREVIOUS
TOGGLE_POWER
RANDOMIZE
SET_INTENSITY
SELECT_SOURCE
TOGGLE_FULLSCREEN
ROTATE_PREVIEW_PRESENTATION
FX_ENABLE
FX_SET_VALUE
FX_MOVE_UP
FX_MOVE_DOWN
RECORD_TOGGLE
```

Keyboard shortcuts are therefore configuration over actions, not bespoke screen code.

## 5. Skin system

A skin is data and assets, never executable feature code.

Minimum token schema:

```text
colors
semantic_colors
typography
font_scale
spacing
radii
borders
shadows
textures
control_dimensions
animation_duration
animation_easing
state_styles
```

Components reference semantic tokens (`surface.primary`, `accent.active`, `text.muted`) rather than literal presentation values.

## 6. First skin direction

Working name: `Vintage Analog`.

Direction:

- warm photographic/electronic equipment feel;
- tactile controls;
- restrained analog texture;
- high readability and clear active/inactive states;
- no direct reproduction of Kodak or another third-party trade dress, logos or proprietary identity.

## 7. Skin package boundary

```text
skin.json
assets/
  textures/
  images/
```

Manifest includes skin schema version, app compatibility and token overrides.

## 8. Accessibility and scale

Skins may alter appearance but must preserve:

- minimum touch targets;
- semantic contrast requirements;
- readable dynamic type bounds;
- focus states for keyboard/accessibility navigation;
- state distinction beyond color alone where needed.

## 9. Drag & drop

Drag & drop is a first-class interaction for:

- media import where platform permits;
- reordering FX/processing nodes;
- layer ordering in FX Lab;
- moving assets into project contexts.

Every drag action must have a non-drag alternative to remain usable on different devices/input methods.

## 10. No WebView port

The existing HTML/CSS/JavaScript controller is a behavioral/reference implementation. The mobile app does not embed it as the product runtime. Web technologies may remain in the separate web controller.

## 11. UI gate

Production UI implementation starts only when state/commands, storage, connectors, Protocol 2.0, security, media endpoint handling, processing graph, Mock Appliance and token schema are validated enough to avoid architectural rework.
