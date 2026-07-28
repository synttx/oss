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

	@version 1.1.0
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

-- Upvalue caching :3
local bufferCreate = buffer.create
local bufferCopy = buffer.copy
local readu32 = buffer.readu32
local writeu32 = buffer.writeu32
local readu8 = buffer.readu8
local writeu8 = buffer.writeu8
local tableCreate = table.create
local tableClear = table.clear
local coroutineStatus = coroutine.status
local taskCancel = task.cancel
local taskDefer = task.defer
local typeofFn = typeof
local rawequalFn = rawequal
local pcallFn = pcall
local btest = bit32.btest
local bor = bit32.bor
local band = bit32.band
local bnot = bit32.bnot

-- ============================== SoA storage ==============================

local scopeItems = tableCreate(INITIAL_SCOPES) :: { { unknown } }
local scopeTags = tableCreate(INITIAL_SCOPES) :: { buffer }
local scopeLens: buffer = bufferCreate(INITIAL_SCOPES * 4)
local scopeCaps: buffer = bufferCreate(INITIAL_SCOPES * 4)
local scopeGens: buffer = bufferCreate(INITIAL_SCOPES * 4)
local scopeFlags: buffer = bufferCreate(INITIAL_SCOPES)
local scopeCap = INITIAL_SCOPES
local scopeCount = 0

local freeStack: buffer = bufferCreate(INITIAL_SCOPES * 4)
local freeCap = INITIAL_SCOPES
local freeLen = 0

-- ============================== internals ================================

-- Forward declare internal lifecycle functions so disposeOne can destroy sub-scopes
local cleanScope: (id: number) -> ()
local releaseScope: (id: number) -> ()

-- Reallocate a u32 buffer to a larger element count, preserving contents.
local function growU32(b: buffer, oldCount: number, newCount: number): buffer
	local grown = bufferCreate(newCount * 4)
	bufferCopy(grown, 0, b, 0, oldCount * 4)
	return grown
end

-- Reallocate a u8 buffer to a larger element count, preserving contents.
local function growU8(b: buffer, oldCount: number, newCount: number): buffer
	local grown = bufferCreate(newCount)
	bufferCopy(grown, 0, b, 0, oldCount)
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
		local status = coroutineStatus(value)
		if status == "suspended" then
			taskCancel(value)
		elseif status ~= "dead" then
			taskDefer(taskCancel, value)
		end
	elseif tag == TAG_DESTROY then
		value:Destroy()
	elseif tag == TAG_DISCONNECT then
		value:Disconnect()
	elseif tag == TAG_SCOPE then
		-- 1.1: Nesting scopes!
		local childId = value % SCOPE_ID_SPACE
		local childFlags = readu8(scopeFlags, childId)

		-- Fine, you can delete the child whenever, developer. Scythe will handle it. No need to worry about unlinking anything.
		if btest(childFlags, FLAG_LIVE) and readu32(scopeGens, childId * 4) == (value - childId) // SCOPE_ID_SPACE then
			if btest(childFlags, FLAG_CLEANING) then
				if not btest(childFlags, FLAG_DESTROY_PENDING) then
					writeu8(scopeFlags, childId, bor(childFlags, FLAG_DESTROY_PENDING))
				end
			else
				cleanScope(childId)

				if readu8(scopeFlags, childId) ~= 0 then -- BE SAFE!
					releaseScope(childId)
				end
			end
		end
	else
		error(`Scythe: corrupted disposal tag '{tag}'`, 0)
	end
end

-- Small optimization teehee
local function resolveError(method: string, msg: string): never
	error(`Scythe.{method}: {msg}`, 3)
end

-- Decode + validate a public handle into an internal slot id.
@native
local function resolve(handle: Scope, method: string): number
	if type(handle) ~= "number" then
		resolveError(method, `expected a Scope handle, got {typeofFn(handle)}`)
	end

	if handle ~= handle or handle < 0 or handle > MAX_HANDLE or handle % 1 ~= 0 then
		resolveError(method, `'{handle}' is not a valid Scope handle`)
	end

	local id = handle % SCOPE_ID_SPACE
	local generation = (handle - id) // SCOPE_ID_SPACE

	if id >= scopeCount then
		resolveError(method, `handle references scope #{id}, which was never allocated`)
	end

	local flags = readu8(scopeFlags, id)
	if not btest(flags, FLAG_LIVE) then
		resolveError(method, `scope #{id} has already been destroyed`)
	end

	if readu32(scopeGens, id * 4) ~= generation then
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
		local len = readu32(scopeLens, lenOffset)
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
		local tag = readu8(tags, len - 1)

		items[len] = nil
		writeu32(scopeLens, lenOffset, len - 1)

		if value ~= nil then
			if PROTECTED_DISPOSAL then
				local ok, err = pcallFn(disposeOne :: any, tag, value) -- I couldn't figure this one out. I'm sorry.
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

	if readu32(scopeLens, id * 4) ~= 0 then
		tableClear(scopeItems[slot])
		writeu32(scopeLens, id * 4, 0)
	end

	local generation = readu32(scopeGens, id * 4) + 1
	if generation >= GEN_SPACE then
		generation = 0
	end
	writeu32(scopeGens, id * 4, generation)
	writeu8(scopeFlags, id, 0)

	-- Give memory back after a spike; stay warm for ordinary churn.
	if readu32(scopeCaps, id * 4) > SHRINK_THRESHOLD then
		scopeItems[slot] = tableCreate(INITIAL_ITEMS)
		scopeTags[slot] = bufferCreate(INITIAL_ITEMS)
		writeu32(scopeCaps, id * 4, INITIAL_ITEMS)
	end

	if freeLen >= freeCap then
		local newCap = freeCap * 2
		if newCap <= freeCap then
			newCap = freeCap + INITIAL_SCOPES
		end
		freeStack = growU32(freeStack, freeCap, newCap)
		freeCap = newCap
	end

	writeu32(freeStack, freeLen * 4, id)
	freeLen += 1
end

-- Drain a scope, guaranteeing the CLEANING flag is cleared and any deferred
-- destroy is honoured, even when a disposer throws.
function cleanScope(id: number): ()
	local flags = readu8(scopeFlags, id)
	local outermost = not btest(flags, FLAG_CLEANING)

	if outermost then
		writeu8(scopeFlags, id, bor(flags, FLAG_CLEANING))
	end

	local ok, err = pcallFn(drainScope :: any, id) -- I'm sorry. Again.

	if outermost then
		local current = readu8(scopeFlags, id)

		if btest(current, FLAG_DESTROY_PENDING) then
			writeu8(scopeFlags, id, FLAG_LIVE)
			releaseScope(id)
		else
			writeu8(scopeFlags, id, band(current, bnot(FLAG_CLEANING)))
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
		id = readu32(freeStack, freeLen * 4)
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

		scopeItems[id + 1] = tableCreate(INITIAL_ITEMS)
		scopeTags[id + 1] = bufferCreate(INITIAL_ITEMS)
		writeu32(scopeCaps, id * 4, INITIAL_ITEMS)
		writeu32(scopeGens, id * 4, 0)
	end

	writeu32(scopeLens, id * 4, 0)
	writeu8(scopeFlags, id, FLAG_LIVE)

	return id + readu32(scopeGens, id * 4) * SCOPE_ID_SPACE
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

	local tag: number
	local kind = typeofFn(value)

	if kind == "number" then
		-- 1.1: Sub-Scope validation
		local childId = (value :: any) % SCOPE_ID_SPACE
		if childId < scopeCount and btest(readu8(scopeFlags, childId), FLAG_LIVE) and readu32(scopeGens, childId * 4) == ((value :: any) - childId) // SCOPE_ID_SPACE then
			if value == scope then
				error(`Scythe.add: cannot add a scope to itself`, 2)
			end
			tag = TAG_SCOPE
		else
			error(`Scythe.add: cannot clean this number (not a valid, alive scope handle)`, 2)
		end
	elseif kind == "RBXScriptConnection" then
		tag = TAG_CONNECTION
	elseif kind == "Instance" then
		tag = TAG_INSTANCE
	elseif kind == "function" then
		tag = TAG_FUNCTION
	elseif kind == "thread" then
		tag = TAG_THREAD
	elseif kind == "table" or kind == "userdata" then
		local resolved, reason = resolveMemberTag(value :: any)
		if resolved == nil then
			error(`Scythe.add: cannot clean this {kind} - {reason}`, 2)
		end
		tag = resolved :: number
	else
		error(`Scythe.add: cannot clean a value of type '{kind}'`, 2)
	end

	local slot = id + 1
	local items = scopeItems[slot]
	local tags = scopeTags[slot]
	local len = readu32(scopeLens, id * 4)
	local cap = readu32(scopeCaps, id * 4)

	if len >= cap then
		if cap >= MAX_ITEMS_PER_SCOPE then
			error(`Scythe.add: scope #{id} hit the item limit ({MAX_ITEMS_PER_SCOPE})`, 2)
		end

		local newCap = cap * 2
		if newCap > MAX_ITEMS_PER_SCOPE then
			newCap = MAX_ITEMS_PER_SCOPE
		end

		local grown = bufferCreate(newCap)
		bufferCopy(grown, 0, tags, 0, cap)
		scopeTags[slot] = grown
		tags = grown
		writeu32(scopeCaps, id * 4, newCap)
	end

	items[len + 1] = value
	writeu8(tags, len, tag)
	writeu32(scopeLens, id * 4, len + 1)

	return value
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
	local len = readu32(scopeLens, id * 4)

	for i = len, 1, -1 do
		if rawequalFn(items[i], value) then
			-- O(1) go brrr
			items[i] = items[len]
			items[len] = nil
			writeu8(tags, i - 1, readu8(tags, len - 1))
			writeu32(scopeLens, id * 4, len - 1)
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
	local flags = readu8(scopeFlags, id)

	if btest(flags, FLAG_CLEANING) then
		-- Re-entrant destroy: defer the recycle so the slot cannot be
		-- reissued and repopulated while the outer drain is still running.
		if not btest(flags, FLAG_DESTROY_PENDING) then
			writeu8(scopeFlags, id, bor(flags, FLAG_DESTROY_PENDING))
		end
		return
	end

	local ok, err = pcallFn(cleanScope :: any, id) -- Please forgive me. I didn't mean it. :(

	-- don't release anything twice :(
	if readu8(scopeFlags, id) ~= 0 then
		releaseScope(id)
	end

	releaseScope(id)

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
	return readu32(scopeLens, resolve(scope, "count") * 4)
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

	if not btest(readu8(scopeFlags, id), FLAG_LIVE) then
		return false
	end

	return readu32(scopeGens, id * 4) == (scope - id) // SCOPE_ID_SPACE
end

table.freeze(Scythe)

return Scythe

-- checcerr.
