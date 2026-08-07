# synttx/oss 🌌

Welcome to the **synttx/oss** monorepo! This is my storefront for high-performance, data-oriented, and garbage-collector-friendly open-source tools built for Roblox Luau.

I focus on building utilities that challenge traditional Object-Oriented Programming (OOP) paradigms in Luau, replacing heavy metatables and object allocations with Structure-of-Arrays (SoA) buffers and integer handles to completely eliminate GC frame stutters.

---

## 📦 Packages

### [Scythe 🔪🩸](./packages/scythe)

A data-oriented cleanup library for Roblox Luau.

- **Zero Garbage**: Generates 0 bytes of heap garbage in steady-state cleanup loops.
- **Ultra-Lightweight**: Uses simple integer handles instead of objects, costing only 16 bytes per scope.
- **Bug-Proof**: Generation-tagged handles prevent double-destroys and memory leaks.

### [Vow 🤝📜](./packages/vow)

A data-oriented, procedural Promise/Future library for Roblox Luau.

- **Blazing Fast**: Uses pre-allocated SoA buffers for extreme performance and cache locality.
- **Zero GC Pressure**: Creates and resolves Vows without triggering heap allocations.
- **Procedural Design**: No methods or objects, just generation-tagged opaque handles.

---

## 🚀 Installation

Each package can be installed independently via [Wally](https://wally.run/). Check the README inside each package for specific installation instructions and API documentation.

---

## 📜 License

All packages in this repository are licensed under the [Mozilla Public License 2.0 (MPL-2.0)](LICENSE) unless stated otherwise.
