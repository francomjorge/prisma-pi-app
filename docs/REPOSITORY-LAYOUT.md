# Intended Repository Layout

**Status:** proposed layout before implementation

The repository should separate product/domain logic from platform adapters and presentation so Android-first work does not make iOS a rewrite.

```text
prisma-pi-app/
├── README.md
├── docs/
│   ├── architecture/
│   ├── protocol/
│   ├── storage/
│   └── decisions/
├── app/
│   ├── lib/
│   │   ├── application/
│   │   ├── presentation/
│   │   ├── navigation/
│   │   └── bootstrap/
│   ├── android/
│   └── ios/
├── packages/
│   ├── prisma_domain/
│   ├── prisma_protocol/
│   ├── prisma_connectors/
│   ├── prisma_storage/
│   ├── prisma_processing_graph/
│   ├── prisma_skin/
│   └── prisma_test_support/
├── native/
│   ├── android_media/
│   └── ios_media/
├── tools/
│   ├── mock_appliance/
│   └── fixtures/
└── tests/
    ├── contract/
    ├── integration/
    └── media/
```

## Ownership rules

### `prisma_domain`

Owns platform-neutral state, commands, events, capabilities, device/session descriptors, project models and validation rules.

It imports no Android/iOS/network/filesystem implementation packages.

### `prisma_protocol`

Owns Protocol 2.0 envelopes, serializers, error model, version negotiation and synchronization state machine.

### `prisma_connectors`

Owns connector interfaces and connection lifecycle. Concrete adapters may live in subpackages/modules:

```text
LanConnector
LegacyEsp32Connector
UsbConnector (future)
MockConnector
```

### `prisma_storage`

Owns repository interfaces and transactional storage semantics. Platform filesystem/SQLite details remain adapters.

### `prisma_processing_graph`

Owns graph/nodes/ordering/execution-target contracts. It does not own a specific GPU API.

### `prisma_skin`

Owns design-token schema, skin package validation and semantic token lookup. Skins do not contain executable feature code.

### `native/android_media`

Owns Android-specific media acceleration/backends only. Candidate technologies must be validated by spikes before freezing the implementation stack.

### `native/ios_media`

Equivalent iOS media backend when the iOS phase starts.

### `mock_appliance`

Reference device implementation for protocol/connector integration tests. It must be able to simulate disconnects, generation gaps, capability differences, file failures and media endpoint changes.

## Dependency direction

```text
Presentation
     ↓
Application
     ↓
Domain contracts
  ↙      ↘
Ports   Protocol models
  ↑
Adapters / platform implementations
```

Platform SDK objects must not cross into domain contracts.

## Test placement

- pure domain tests stay close to package code;
- protocol contract tests exercise serialized fixtures;
- connector integration tests use Mock Appliance;
- media tests use deterministic fixtures;
- physical appliance tests are tracked separately from automated simulation results.
