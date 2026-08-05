--!strict
--!optimize 2

--[=[
	@name Scythe

	@desc A data-oriented cleanup library for Luau.

	Unlike Janitor/Maid/Trove, Scythe has no objects, no metatables and no
	per-instance allocation cost. A scope is just an integer handle into
	module-level Structure-of-Arrays storage:

		scopeItems : { {unknown} } -- payloads, one array per scope
		scopeTags  : { buffer }    -- u8 disposal tag per item
		scopeLens  : buffer        -- u32 live item count per scope
		scopeCaps  : buffer        -- u32 tag-buffer capacity per scope
		scopeGens  : buffer        -- u32 generation, invalidates old handles
		scopeFlags : buffer        -- u8 lifecycle flags
		freeStack  : buffer        -- u32 recycled id stack

	The disposal method is resolved ONCE at `add` time and stored as a u8
	tag, so the `clean` hot loop is a branch on an integer read straight
	out of a buffer - no `typeof`, no method sniffing.

	Cleanup order is LIFO (reverse insertion), matching resource
	acquisition semantics.

	@usage
		local Scythe = require(path.to.Scythe)

		local scope = Scythe.scope()
		Scythe.add(scope, workspace.Part)                -- :Destroy()
		Scythe.add(scope, humanoid.Died:Connect(onDied)) -- :Disconnect()
		Scythe.add(scope, task.spawn(loop))              -- task.cancel()
		Scythe.add(scope, function() print("bye") end)   -- called

		Scythe.addBulk(scope, part2, conn2, thread2)     -- Track multiple items in one atomic call

		local subScope = Scythe.scope()
		Scythe.add(scope, subScope)                      -- Sub-scope linked!

		Scythe.clean(scope)   -- dispose everything, scope stays usable
		Scythe.destroy(scope) -- dispose everything, recycle the handle

	@notes
		* Handles are generation-tagged. Reusing a handle after `destroy`
		  raises an error - it can never silently alias a newer scope.
		* Every item is disposed even if some disposers throw; the errors
		  are aggregated and re-raised once the scope is empty.
		* Disposers may `add`/`remove`/`clean`/`destroy` their own scope.
		  They must NOT yield: a yield inside a disposer suspends the drain
		  and exposes partially-cleaned state to other coroutines.

	@version 1.2
	@author checcerr | fridayqx
	@license MPL-2.0
]=]

--[=[
	An opaque integer handle to a cleanup scope.

	Obtained from `Scythe.scope()`, released with `Scythe.destroy()`.
	It is a plain number - cheap to store, pass, and compare - but you
	should never do arithmetic on it or fabricate one yourself: it packs
	both a slot index and a generation counter.
]=]
export type Scope = number

-- ============================== tunables ================================

-- When true, every disposer runs protected: one throwing callback can no
-- longer strand the remaining resources. Errors are counted and re-raised
-- once, after the scope is fully drained. Set false for 1.0.0 fail-fast.
local PROTECTED_DISPOSAL = false

local INITIAL_SCOPES = 64      -- starting scope capacity (module-wide)
local INITIAL_ITEMS = 8        -- starting item capacity per scope
local SHRINK_THRESHOLD = 1024  -- release per-scope storage grown past this
local DRAIN_LIMIT = 1_048_576  -- max disposals in a single clean (hang guard)

local SCOPE_ID_SPACE = 16_777_216   -- 2^24 addressable scopes
local MAX_SCOPES = SCOPE_ID_SPACE
local GEN_SPACE = 268_435_456       -- 2^28 generations; handle max ~2^52
local MAX_HANDLE = (GEN_SPACE - 1) * SCOPE_ID_SPACE + (SCOPE_ID_SPACE - 1)
local MAX_ITEMS_PER_SCOPE = 16_777_216

-- Disposal tags (u8). Resolved once at add-time, branched on at clean-time.
local TAG_CONNECTION = 1   -- RBXScriptConnection    -> :Disconnect()
local TAG_INSTANCE = 2     -- Instance               -> :Destroy()
local TAG_FUNCTION = 3     -- function               -> value()
local TAG_THREAD = 4       -- thread                 -> task.cancel()
local TAG_DESTROY = 5      -- table/userdata Destroy -> :Destroy()
local TAG_DISCONNECT = 6   -- table/userdata Disconn -> :Disconnect()
local TAG_SCOPE = 7        -- Sub-scopes             -> Scythe.destroy()

-- Lifecycle flags (u8, packed into scopeFlags).
local FLAG_LIVE = 1
local FLAG_CLEANING = 2
local FLAG_DESTROY_PENDING = 4

-- ============================== SoA storage ==============================

local scopeItems = table.create(INITIAL_SCOPES) :: { { unknown } }
local scopeTags = table.create(INITIAL_SCOPES) :: { buffer }
local scopeLens: buffer = buffer.create(INITIAL_SCOPES * 4)
local scopeCaps: buffer = buffer.create(INITIAL_SCOPES * 4)
local scopeGens: buffer = buffer.create(INITIAL_SCOPES * 4)
local scopeFlags: buffer = buffer.create(INITIAL_SCOPES)
local scopeCap = INITIAL_SCOPES
local scopeCount = 0

local freeStack: buffer = buffer.create(INITIAL_SCOPES * 4)
local freeCap = INITIAL_SCOPES
local freeLen = 0

-- ============================== internals ================================

-- Forward declare internal lifecycle functions so disposeOne can destroy sub-scopes
local cleanScope: (id: number) -> ()
local releaseScope: (id: number) -> ()

-- Reallocate a u32 buffer to a larger element count, preserving contents.
local function growU32(b: buffer, oldCount: number, newCount: number): buffer
	local grown = buffer.create(newCount * 4)
	buffer.copy(grown, 0, b, 0, oldCount * 4)
	return grown
end

-- Reallocate a u8 buffer to a larger element count, preserving contents.
local function growU8(b: buffer, oldCount: number, newCount: number): buffer
	local grown = buffer.create(newCount)
	buffer.copy(grown, 0, b, 0, oldCount)
	return grown
end

-- Resolve Destroy/Disconnect on a table or userdata.
-- Returns a tag, or nil plus the reason it failed.
local function resolveMemberTag(value: any): (number?, string?)
	if type(value.Destroy) == "function" then
		return TAG_DESTROY, nil
	elseif type(value.Disconnect) == "function" then
		return TAG_DISCONNECT, nil
	end

	return nil, "no callable Destroy/Disconnect member"
end

-- Dispose a single value by its precomputed tag.
-- Shared by `clean`, `destroy` and `remove`'s dispose path.
@native
local function disposeOne(tag: number, value: any): ()
	if tag == TAG_CONNECTION then
		value:Disconnect()
	elseif tag == TAG_INSTANCE then
		value:Destroy()
	elseif tag == TAG_FUNCTION then
		value()
	elseif tag == TAG_THREAD then
		local status = coroutine.status(value)
		if status == "suspended" then
			task.cancel(value)
		elseif status ~= "dead" then
			task.defer(task.cancel, value)
		end
	elseif tag == TAG_DESTROY then
		value:Destroy()
	elseif tag == TAG_DISCONNECT then
		value:Disconnect()
	elseif tag == TAG_SCOPE then
		-- 1.1: Nesting scopes!
		local childId = value % SCOPE_ID_SPACE
		local childFlags = buffer.readu8(scopeFlags, childId)

		-- Fine, you can delete the child whenever, developer. Scythe will handle it. No need to worry about unlinking anything.
		if bit32.btest(childFlags, FLAG_LIVE) and buffer.readu32(scopeGens, childId * 4) == (value - childId) // SCOPE_ID_SPACE then
			if bit32.btest(childFlags, FLAG_CLEANING) then
				if not bit32.btest(childFlags, FLAG_DESTROY_PENDING) then
					buffer.writeu8(scopeFlags, childId, bit32.bor(childFlags, FLAG_DESTROY_PENDING))
				end
			else
				cleanScope(childId)

				if buffer.readu8(scopeFlags, childId) ~= 0 then -- BE SAFE!
					releaseScope(childId)
				end
			end
		end
	else
		error(`Scythe: corrupted disposal tag '{tag}'`, 0)
	end
end

-- Resolve the disposal tag for a value, exactly once, at add-time.
-- Errors at level 3 so the blame lands on the caller of the public function.
@native
local function resolveTag(value: unknown, scope: Scope, method: string): number
	local kind = typeof(value)

	if kind == "number" then
		local handle = value :: number

		-- 1.1: Sub-Scope validation. Integer-guard BEFORE the modulo, otherwise
		-- a fractional number reaches buffer.readu8 and throws a garbage error.
		if handle == handle and handle >= 0 and handle <= MAX_HANDLE and handle % 1 == 0 then
			local childId = handle % SCOPE_ID_SPACE

			if
				childId < scopeCount
				and bit32.btest(buffer.readu8(scopeFlags, childId), FLAG_LIVE)
				and buffer.readu32(scopeGens, childId * 4) == (handle - childId) // SCOPE_ID_SPACE
			then
				if handle == scope then
					error(`Scythe.{method}: cannot add a scope to itself`, 3)
				end
				return TAG_SCOPE
			end
		end

		error(`Scythe.{method}: cannot clean this number (not a valid, alive scope handle)`, 3)
	elseif kind == "RBXScriptConnection" then
		return TAG_CONNECTION
	elseif kind == "Instance" then
		return TAG_INSTANCE
	elseif kind == "function" then
		return TAG_FUNCTION
	elseif kind == "thread" then
		return TAG_THREAD
	elseif kind == "table" or kind == "userdata" then
		local resolved, reason = resolveMemberTag(value :: any)
		if resolved == nil then
			error(`Scythe.{method}: cannot clean this {kind} - {reason}`, 3)
		end
		return resolved :: number
	end

	error(`Scythe.{method}: cannot clean a value of type '{kind}'`, 3)
end

-- Small optimization teehee
local function resolveError(method: string, msg: string): never
	error(`Scythe.{method}: {msg}`, 4)
end

-- Decode + validate a public handle into an internal slot id.
@native
local function resolve(handle: Scope, method: string): number
	if type(handle) ~= "number" then
		resolveError(method, `expected a Scope handle, got {typeof(handle)}`)
	end

	if handle ~= handle or handle < 0 or handle > MAX_HANDLE or handle % 1 ~= 0 then
		resolveError(method, `'{handle}' is not a valid Scope handle`)
	end

	local id = handle % SCOPE_ID_SPACE
	local generation = (handle - id) // SCOPE_ID_SPACE

	if id >= scopeCount then
		resolveError(method, `handle references scope #{id}, which was never allocated`)
	end

	local flags = buffer.readu8(scopeFlags, id)
	if not bit32.btest(flags, FLAG_LIVE) then
		resolveError(method, `scope #{id} has already been destroyed`)
	end

	if buffer.readu32(scopeGens, id * 4) ~= generation then
		resolveError(method, `stale handle - scope #{id} was destroyed and recycled`)
	end

	return id
end

-- Pop-then-dispose drain. State is committed to the SoA arrays BEFORE the
-- disposer runs, so re-entrant add/remove/clean/destroy from inside a
-- callback observe (and mutate) a fully consistent scope.
@native
local function drainScope(id: number): ()
	local slot = id + 1
	local lenOffset = id * 4
	local firstError: any = nil
	local errorCount = 0
	local guard = 0

	while true do
		local len = buffer.readu32(scopeLens, lenOffset)
		if len == 0 then
			break
		end

		guard += 1
		if guard > DRAIN_LIMIT then
			error(
				`Scythe.clean: drain limit ({DRAIN_LIMIT}) exceeded on scope #{id} - `
					.. `a disposer is adding items faster than they can be disposed`,
				0
			)
		end

		local items = scopeItems[slot]
		local tags = scopeTags[slot]
		local value = items[len]
		local tag = buffer.readu8(tags, len - 1)

		items[len] = nil
		buffer.writeu32(scopeLens, lenOffset, len - 1)

		if value ~= nil then
			if PROTECTED_DISPOSAL then
				local ok, err = pcall(disposeOne :: any, tag, value) -- I couldn't figure this one out. I'm sorry.
				if not ok then
					errorCount += 1
					if firstError == nil then
						firstError = err
					end
				end
			else
				disposeOne(tag, value)
			end
		end
	end

	if firstError ~= nil then
		if errorCount == 1 then
			error(`Scythe.clean: a disposer errored: {firstError}`, 0)
		end
		error(`Scythe.clean: {errorCount} disposers errored, first: {firstError}`, 0)
	end
end

-- Recycle a slot: bump the generation (invalidating every outstanding
-- handle), release oversized storage, push the id back on the free stack.
function releaseScope(id: number): ()
	local slot = id + 1

	if buffer.readu32(scopeLens, id * 4) ~= 0 then
		table.clear(scopeItems[slot])
		buffer.writeu32(scopeLens, id * 4, 0)
	end

	local generation = buffer.readu32(scopeGens, id * 4) + 1
	if generation >= GEN_SPACE then
		generation = 0
	end
	buffer.writeu32(scopeGens, id * 4, generation)
	buffer.writeu8(scopeFlags, id, 0)

	-- Give memory back after a spike; stay warm for ordinary churn.
	if buffer.readu32(scopeCaps, id * 4) > SHRINK_THRESHOLD then
		scopeItems[slot] = table.create(INITIAL_ITEMS)
		scopeTags[slot] = buffer.create(INITIAL_ITEMS)
		buffer.writeu32(scopeCaps, id * 4, INITIAL_ITEMS)
	end

	if freeLen >= freeCap then
		local newCap = freeCap * 2
		if newCap <= freeCap then
			newCap = freeCap + INITIAL_SCOPES
		end
		freeStack = growU32(freeStack, freeCap, newCap)
		freeCap = newCap
	end

	buffer.writeu32(freeStack, freeLen * 4, id)
	freeLen += 1
end

-- Drain a scope, guaranteeing the CLEANING flag is cleared and any deferred
-- destroy is honoured, even when a disposer throws.
function cleanScope(id: number): ()
	local flags = buffer.readu8(scopeFlags, id)
	local outermost = not bit32.btest(flags, FLAG_CLEANING)

	if outermost then
		buffer.writeu8(scopeFlags, id, bit32.bor(flags, FLAG_CLEANING))
	end

	local ok, err = pcall(drainScope :: any, id) -- I'm sorry. Again.

	if outermost then
		local current = buffer.readu8(scopeFlags, id)

		if bit32.btest(current, FLAG_DESTROY_PENDING) then
			buffer.writeu8(scopeFlags, id, FLAG_LIVE)
			releaseScope(id)
		else
			buffer.writeu8(scopeFlags, id, bit32.band(current, bit32.bnot(FLAG_CLEANING)))
		end
	end

	if not ok then
		error(err, 0)
	end
end

local Scythe = {}

-- ================================= API ==================================

--[=[
	Acquires a cleanup scope and returns its handle.

	Slots are pooled: destroyed scopes are recycled with their item arrays
	kept warm (capacity preserved, unless it ballooned past the shrink
	threshold), so `scope()` in steady state allocates nothing at all.

	```lua
	local scope = Scythe.scope()
	```

	@return Scope -- an opaque, generation-tagged integer handle
]=]
function Scythe.scope(): Scope
	local id: number

	-- Fast path! :D
	if freeLen > 0 then
		freeLen -= 1
		id = buffer.readu32(freeStack, freeLen * 4)
	else
		-- Slow path :(
		if scopeCount >= scopeCap then
			local newCap = scopeCap * 2
			if newCap > MAX_SCOPES then
				newCap = MAX_SCOPES
			end
			if newCap <= scopeCap then
				error(`Scythe.scope: scope limit ({MAX_SCOPES}) reached`, 2)
			end

			scopeLens = growU32(scopeLens, scopeCap, newCap)
			scopeCaps = growU32(scopeCaps, scopeCap, newCap)
			scopeGens = growU32(scopeGens, scopeCap, newCap)
			scopeFlags = growU8(scopeFlags, scopeCap, newCap)
			scopeCap = newCap
		end

		id = scopeCount
		scopeCount += 1

		scopeItems[id + 1] = table.create(INITIAL_ITEMS)
		scopeTags[id + 1] = buffer.create(INITIAL_ITEMS)
		buffer.writeu32(scopeCaps, id * 4, INITIAL_ITEMS)
		buffer.writeu32(scopeGens, id * 4, 0)
	end

	buffer.writeu32(scopeLens, id * 4, 0)
	buffer.writeu8(scopeFlags, id, FLAG_LIVE)

	return id + buffer.readu32(scopeGens, id * 4) * SCOPE_ID_SPACE
end

--[=[
	Adds a value to a scope and returns it unchanged, so calls can be
	inlined into expressions:

	```lua
	local part = Scythe.add(scope, Instance.new("Part"))
	local conn = Scythe.add(scope, signal:Connect(handler))
	local co   = Scythe.add(scope, task.spawn(loop))
	Scythe.add(scope, function() print("cleanup!") end)
	```

	The disposal method is resolved here, exactly once:

	| Value                                | On clean        |
	|--------------------------------------|-----------------|
	| `RBXScriptConnection`                | `:Disconnect()` |
	| `Instance`                           | `:Destroy()`    |
	| `function`                           | called          |
	| `thread`                             | `task.cancel()` |
	| table/userdata with callable Destroy | `:Destroy()`    |
	| table/userdata with callable Disconn | `:Disconnect()` |
	| `Scythe Scope`                       | Scythe.destroy()|

	Errors if the value fits none of the rows above - a silently
	un-cleanable value is a leak, and Scythe refuses to leak. Adding the
	same value twice disposes it twice; that is your call to make.

	Safe to call from inside a disposer: the item lands on top of the
	stack and is disposed by the in-flight drain.

	@param scope Scope -- handle from `Scythe.scope()`
	@param value T -- the resource to track
	@return T -- `value`, passed through
]=]
@native
function Scythe.add<T>(scope: Scope, value: T): T
	local id = resolve(scope, "add")

	local tag = resolveTag(value, scope, "add")

	local slot = id + 1
	local items = scopeItems[slot]
	local tags = scopeTags[slot]
	local len = buffer.readu32(scopeLens, id * 4)
	local cap = buffer.readu32(scopeCaps, id * 4)

	if len >= cap then
		if cap >= MAX_ITEMS_PER_SCOPE then
			error(`Scythe.add: scope #{id} hit the item limit ({MAX_ITEMS_PER_SCOPE})`, 2)
		end

		local newCap = cap * 2
		if newCap > MAX_ITEMS_PER_SCOPE then
			newCap = MAX_ITEMS_PER_SCOPE
		end

		local grown = buffer.create(newCap)
		buffer.copy(grown, 0, tags, 0, cap)
		scopeTags[slot] = grown
		tags = grown
		buffer.writeu32(scopeCaps, id * 4, newCap)
	end

	items[len + 1] = value
	buffer.writeu8(tags, len, tag)
	buffer.writeu32(scopeLens, id * 4, len + 1)

	return value
end

--[=[
	Adds many values to a scope in one call. Returns NOTHING - no pack, no
	table, no allocation:

	```lua
	Scythe.addBulk(scope, part, conn, thread, function() print("bye") end)
	```

	Identical semantics to `add` per value (same tag table, same LIFO
	disposal - later arguments are disposed first), with two differences:

	* The tag buffer is grown ONCE for the whole batch instead of doubling
	  per item.
	* It is atomic. Tags are resolved into the unused region above the live
	  length first, so if ANY value has no cleanup path the scope is left
	  untouched and nothing is half-tracked.

	`nil` is not a cleanable value, so holes in the argument list throw.
	Safe to call from inside a disposer; the batch lands on top of the stack
	and is drained by the in-flight clean.

	@param scope Scope -- handle from `Scythe.scope()`
	@param ... unknown -- resources to track
]=]
@native
function Scythe.addBulk(scope: Scope, ...: unknown): ()
	local id = resolve(scope, "addBulk")

	local n = select("#", ...)
	if n == 0 then
		return
	end

	local slot = id + 1
	local len = buffer.readu32(scopeLens, id * 4)
	local cap = buffer.readu32(scopeCaps, id * 4)
	local needed = len + n

	if needed > MAX_ITEMS_PER_SCOPE then
		error(`Scythe.addBulk: scope #{id} hit the item limit ({MAX_ITEMS_PER_SCOPE})`, 2)
	end

	local tags = scopeTags[slot]

	if needed > cap then
		local newCap = cap
		repeat
			newCap *= 2
		until newCap >= needed

		if newCap > MAX_ITEMS_PER_SCOPE then
			newCap = MAX_ITEMS_PER_SCOPE
		end

		local grown = buffer.create(newCap)
		buffer.copy(grown, 0, tags, 0, cap)
		scopeTags[slot] = grown
		tags = grown
		buffer.writeu32(scopeCaps, id * 4, newCap)
	end

	-- Pass 1: resolve every tag into scratch space above the live length.
	-- A throw here leaves scopeLens untouched, so the batch never happened.
	for i = 1, n do
		buffer.writeu8(tags, len + i - 1, resolveTag(select(i, ...), scope, "addBulk"))
	end

	-- Pass 2: commit. No failure paths left.
	local items = scopeItems[slot]
	for i = 1, n do
		items[len + i] = select(i, ...)
	end
	buffer.writeu32(scopeLens, id * 4, needed)
end

--[=[
	Removes ONE tracked value from a scope WITHOUT disposing it, using
	swap-removal (O(1) - order of remaining items may change, which is
	fine because disposal order only matters relative to live items you
	still control).

	Use this when ownership of a resource is transferred elsewhere:

	```lua
	local conn = Scythe.add(scope, signal:Connect(fn))
	-- ... later, someone else takes over the connection:
	Scythe.remove(scope, conn)
	```

	Identity is compared with `rawequal`, so a custom `__eq` can never
	trick Scythe into releasing the wrong resource.

	@param scope Scope -- handle from `Scythe.scope()`
	@param value unknown -- the exact value previously passed to `add`
	@return boolean -- true if found and removed, false otherwise
]=]
function Scythe.remove(scope: Scope, value: unknown): boolean
	local id = resolve(scope, "remove")
	if value == nil then
		return false
	end

	local slot = id + 1
	local items = scopeItems[slot]
	local tags = scopeTags[slot]
	local len = buffer.readu32(scopeLens, id * 4)

	for i = len, 1, -1 do
		if rawequal(items[i], value) then
			-- O(1) go brrr
			items[i] = items[len]
			items[len] = nil
			buffer.writeu8(tags, i - 1, buffer.readu8(tags, len - 1))
			buffer.writeu32(scopeLens, id * 4, len - 1)
			return true
		end
	end

	return false
end

--[=[
	Disposes every tracked value in LIFO order (reverse of insertion) and
	empties the scope. The scope handle REMAINS VALID and can be reused
	immediately - its internal capacity is kept warm, so a clean/add
	cycle in steady state performs zero allocations.

	```lua
	Scythe.clean(scope) -- everything disposed, scope still usable
	```

	Each item is popped from the scope BEFORE its disposer runs, and every
	disposer runs even if earlier ones threw. If any threw, a single
	aggregated error is raised after the scope is fully empty - nothing is
	ever stranded. Disposers may add to, remove from, clean, or destroy
	their own scope; they must not yield.

	@param scope Scope -- handle from `Scythe.scope()`
]=]
function Scythe.clean(scope: Scope): ()
	cleanScope(resolve(scope, "clean"))
end

--[=[
	Disposes every tracked value (exactly like `clean`), then recycles
	the slot back into the pool for a future `Scythe.scope()` call.

	```lua
	Scythe.destroy(scope)
	scope = nil :: any -- drop your reference; the handle is dead
	```

	The handle is generation-tagged, so reusing it after `destroy` - or
	destroying twice - raises a clear error rather than corrupting an
	unrelated scope. Calling this from inside a disposer is safe: the
	recycle is deferred until the in-flight drain finishes.

	@param scope Scope -- handle from `Scythe.scope()`
]=]
function Scythe.destroy(scope: Scope): ()
	local id = resolve(scope, "destroy")
	local flags = buffer.readu8(scopeFlags, id)

	if bit32.btest(flags, FLAG_CLEANING) then
		-- Re-entrant destroy: defer the recycle so the slot cannot be
		-- reissued and repopulated while the outer drain is still running.
		if not bit32.btest(flags, FLAG_DESTROY_PENDING) then
			buffer.writeu8(scopeFlags, id, bit32.bor(flags, FLAG_DESTROY_PENDING))
		end
		return
	end

	local ok, err = pcall(cleanScope :: any, id) -- Please forgive me. I didn't mean it. :(

	-- don't release anything twice :(
	if buffer.readu8(scopeFlags, id) ~= 0 then
		releaseScope(id)
	end

	-- releaseScope(id) die

	if not ok then
		error(err, 0)
	end
end

--[=[
	Returns the number of values currently tracked by a scope.
	One u32 buffer read - effectively free. Useful for asserts, tests,
	and leak hunting.

	```lua
	assert(Scythe.count(scope) == 0, "scope leaked items!")
	```

	@param scope Scope -- handle from `Scythe.scope()`
	@return number -- live item count
]=]
@native
function Scythe.count(scope: Scope): number
	return buffer.readu32(scopeLens, resolve(scope, "count") * 4)
end

--[=[
	Non-throwing liveness check. Returns false for destroyed, stale,
	malformed, or never-allocated handles.

	```lua
	if Scythe.isAlive(scope) then
		Scythe.add(scope, conn)
	end
	```

	@param scope Scope -- any value
	@return boolean -- true if the handle addresses a live scope
]=]
@native
function Scythe.isAlive(scope: Scope): boolean
	if type(scope) ~= "number" then
		return false
	end

	if scope ~= scope or scope < 0 or scope > MAX_HANDLE or scope % 1 ~= 0 then
		return false
	end

	local id = scope % SCOPE_ID_SPACE
	if id >= scopeCount then
		return false
	end

	if not bit32.btest(buffer.readu8(scopeFlags, id), FLAG_LIVE) then
		return false
	end

	return buffer.readu32(scopeGens, id * 4) == (scope - id) // SCOPE_ID_SPACE
end

table.freeze(Scythe)

return Scythe

-- checcerr.
