<div align="center">
<h1> I Vow you you'll switch from Promise/Future after reading this post. 🤝📜 </h1>
<h6>On par with the quickest libraries. Up to 32 times lighter than traditional Promises.
</h6></div>

<hr>

<div align="center">
 <h3><kbd>What is Vow?</kbd> </h3> 
</div>

Vow is a **zero-allocation, data-oriented** Promise/Future library for Luau. It performs the exact same role as `evaera`'s Promise or `RedBlox`'s Future—allowing you to chain asynchronous operations, wait on resolutions, and handle rejections—but takes a fundamentally different approach to how it stores and resolves them.

Instead of creating an object per scope (a table with a metatable, a dictionary, closure wrappers, etc.), **Vow** represents each asynchronous operation as a **plain integer handle** pointing into module-level Structure-of-Arrays (SoA) storage. No objects. No metatables. No per-instance allocation cost.

The result is a library that's up to **6x faster** than traditional Promises, produces **zero garbage collector pressure** in steady state, and is fully compatible with `--!strict` typed Luau.

**Source**: [GitHub](https://github.com/synttx/oss/tree/main/vow) - Licensed under MPL-2.0.

<hr>

<div align="center">
 <h3><kbd>Why Not Just Use Promise?</kbd> </h3>
<small>Or Future...</small> 
</div>

`evaera`'s Promise, `RedBlox`'s Future, and `YetAnotherClown`'s Future all follow the same pattern: each promise is an **object** (a table with a metatable). Every time you `.andThen()` chain or aggregate with `.all()`, you're allocating new tables and wrapping closures. Over hundreds of thousands of operations, this creates a massive graveyard of garbage for the Luau GC to sweep up.

Vow flips this on its head:

| | Traditional Promise / Future | Vow |
|---|---|---|
| **Scope** | Object (table + metatable) | Integer handle (plain `number`) |
| **Data Storage** | Dictionaries & Node Trees | Contiguous arrays + `buffer` |
| **Type resolution** | Constant OOP lookups | Parallel array lookups |
| **Steady-state GC** | High (e.g., `1.74 GB` over 200k cycles) | **0 KB** (Recycled Handles) |
| **Strict typing** | Varies / Internal casting | Full `--!strict` Compatibility |

The key insight: **Promises don't need to be objects.** Vow pre-allocates SoA arrays and scopes are just integer IDs. Once a Vow is destroyed, its handle is recycled. There is zero heap churn. You get all the power of asynchronous chaining without any of the OOP baggage!

<hr>

<div align="center">
 <h3><kbd>Benchmarks</kbd> </h3> 
</div>

> [Check out the benchmarks section on GitHub for a detailed benchmark overview, memory footprint graphs, and more.](https://github.com/synttx/oss/tree/main/vow/benchmarks)

**Overall, Vow leaves a much, much tinier memory footprint and GC pressure while boasting execution speeds that completely demolish traditional OOP Promises. (Up to 32 times lighter!)**

**Because Vow recycles its integer handles, there is always *0 KB* of heap garbage generated in the steady state!**

### This translates to massively reduced RAM consumption and virtually zero GC micro-stutters. Your game stays smooth, even under intense asynchronous workloads. Yeah, it's just cool like that. 👀

<hr>

<div align="center">
 <h3><kbd>Usage</kbd> </h3> 
</div>

```lua
local Vow = require(path.to.Vow)

-- Create a new Vow
local id = Vow.new(function(id)
	task.defer(function()
		Vow.resolve(id, "ready")
	end)
end)

-- Chain with andThen
local nextId = Vow.andThen(id, function(value)
	print(value) -- prints: ready
	return "finished"
end)

-- Await the result
local ok, value = Vow.await(nextId)
print(value) -- prints: finished

-- IMPORTANT: You must manually destroy Vows to free up slots in the pool
Vow.destroy(id)
Vow.destroy(nextId)
```

That's the core workflow. It's built to feel instantly familiar to anyone who has used Promises, but optimized to the absolute limit.

### Strict Typing

Vow is written under `--!strict` with full type annotations. The module exports a `Vow` type, so your code stays exceptionally clean:

```lua
local Vow = require(path.to.Vow)

local id: Vow.Vow = Vow.new(function(id)
	Vow.resolve(id, "Success!")
end)
```

No casts, no `any`, no type errors.

<hr>

<div align="center">
 <h3><kbd>API Reference</kbd> </h3> 
</div>

### `Vow.new(executor) → Vow`
Acquire a new Vow and execute the provided function.

### `Vow.resolve(id, value) → ()`
Resolves the Vow with a single value. Can adopt another live Vow.

### `Vow.reject(id, value) → ()`
Rejects the Vow with the given value.

### `Vow.cancel(id) → ()`
Cancels the Vow and flows downwards to its children.

### `Vow.destroy(id) → ()`
Disposes the Vow, detaches it, and recycles the handle.

### `Vow.andThen(id, handler) → Vow`
Chains a callback to run when the Vow resolves.

### `Vow.await(id) → (boolean, any)`
Yields the current thread until the Vow settles.

### `Vow.all(vows) → Vow`
Returns an aggregate Vow that resolves when all input Vows resolve.

### `Vow.race(vows) → Vow`
Returns an aggregate Vow that settles as soon as any input Vow settles.

<hr>

<div align="center">
 <h3><kbd>Important Notes</kbd> </h3> 
</div>

> 🚨 **Manual Memory Management.** Because Vows are opaque integer handles, Luau's garbage collector cannot automatically discover when a settled Vow is no longer needed. **Developers MUST call `Vow.destroy(id)`** when completely finished with a Vow to release it back into the pool. Using a handle after destruction is undefined behavior. Treat `destroy()` as final!

<small>That's all, for now.</small>

<hr>

<div align="center">
 <h3><kbd>Get It</kbd> </h3> 
</div>

- **Source**: [GitHub](https://github.com/synttx/oss/tree/main/vow)
- **License**: MPL-2.0 (open source, use it freely)
- **Installation**:
Vow is available on Wally! You can get it by modifying your `wally.toml`, like so:

```toml
[dependencies]
Vow = "synttx/vow@1.0.0"
```

Alternatively, you can download the latest release or clone the source directly into your project.

If you have questions, suggestions, or find a bug - drop a reply below or open an issue on GitHub. Contributions are welcome.

Thanks for reading!
