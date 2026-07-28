--!nocheck
--!optimize 2

--[[
    Memory Allocation & GC Pressure Benchmark

    Measures Peak Active RAM (Cold/Warm footprint in KB and Bytes/scope) and Total GC Garbage generated across 1 million cycles.

    Lower numbers are better (lower RAM footprint in KB/Bytes, lower GC allocations).

    Contenders:
    - Scythe (by fridayqx)
    - Janitor (by howmanysmall)
    - Maid (by Quenty)
    - Trove (by sleitnick)

    Note: Run this script in the Roblox Studio Command Bar.
]]

local Scythe = require('../src/scythe.luau')
local Janitor = require('path to howmanysmall`s Janitor')
local Maid = require('path to Quenty`s Maid')
local Trove = require('path to sleitnick`s Trove')

local function dummyTask() end

local ACTIVE_ITERATIONS = 100_000
local GC_ITERATIONS = 1_000_000

local function printHeader(title)
	print("\n=================================================================")
	print(" " .. title)
	print("=================================================================")
end

local function runActiveTest(libName, setupFn, teardownFn)
	task.wait(1.5)

	local startMem = gcinfo()
	local active = table.create(ACTIVE_ITERATIONS)

	for i = 1, ACTIVE_ITERATIONS do
		active[i] = setupFn()
	end

	local peakMem = gcinfo()

	for i = 1, ACTIVE_ITERATIONS do
		teardownFn(active[i])
	end
	table.clear(active)

	local allocatedKB = math.max(0, peakMem - startMem)
	local bytesPerScope = (allocatedKB * 1024) / ACTIVE_ITERATIONS

	print(string.format("%-10s | Peak Active RAM: %8.2f KB | %6.2f Bytes per scope", libName, allocatedKB, bytesPerScope))
end

local function runGCTest(libName, loopFn)
	task.wait(1.5)

	local allocations = 0
	local lastMem = gcinfo()

	for i = 1, GC_ITERATIONS do
		loopFn()

		if i % 50 == 0 then
			local currentMem = gcinfo()
			if currentMem > lastMem then
				allocations += (currentMem - lastMem)
			end
			lastMem = currentMem
		end
	end

	local bytesPerCycle = (allocations * 1024) / GC_ITERATIONS
	print(string.format("%-10s | Total GC Garbage: %7.2f KB | %6.2f Bytes per cycle", libName, allocations, bytesPerCycle))
end

-- =======================================================================
-- EXECUTION
-- =======================================================================

print("\nStarting Ultimate Memory Benchmark...")
print(`Tracking {ACTIVE_ITERATIONS} active objects, and {GC_ITERATIONS} GC cycles.`)
print("Studio will freeze for a moment during calculations...\n")

-- --- PHASE 1: COLD START ---
printHeader("PHASE 1: COLD ACTIVE FOOTPRINT (Fresh Memory)")
runActiveTest("Maid",
	function() local m = Maid.new(); m:GiveTask(dummyTask); return m end,
	function(m) m:Destroy() end
)
runActiveTest("Trove",
	function() local t = Trove.new(); t:Add(dummyTask); return t end,
	function(t) t:Destroy() end
)
runActiveTest("Janitor",
	function() local j = Janitor.new(); j:Add(dummyTask); return j end,
	function(j) j:Destroy() end
)
runActiveTest("Scythe",
	function() local s = Scythe.scope(); Scythe.add(s, dummyTask); return s end,
	function(s) Scythe.destroy(s) end
)


-- --- PHASE 2: WARM START ---
printHeader("PHASE 2: WARM ACTIVE FOOTPRINT (Reused Memory)")
runActiveTest("Maid",
	function() local m = Maid.new(); m:GiveTask(dummyTask); return m end,
	function(m) m:Destroy() end
)
runActiveTest("Trove",
	function() local t = Trove.new(); t:Add(dummyTask); return t end,
	function(t) t:Destroy() end
)
runActiveTest("Janitor",
	function() local j = Janitor.new(); j:Add(dummyTask); return j end,
	function(j) j:Destroy() end
)
runActiveTest("Scythe",
	function() local s = Scythe.scope(); Scythe.add(s, dummyTask); return s end,
	function(s) Scythe.destroy(s) end
)

-- --- PHASE 3: GARBAGE COLLECTION ---
printHeader("PHASE 3: STEADY-STATE GARBAGE GENERATION (1 Million Cycles)")
runGCTest("Maid", function()
	local m = Maid.new()
	m:GiveTask(dummyTask)
	m:Destroy()
end)

runGCTest("Trove", function()
	local t = Trove.new()
	t:Add(dummyTask)
	t:Destroy()
end)


runGCTest("Janitor", function()
	local j = Janitor.new()
	j:Add(dummyTask)
	j:Destroy()
end)

runGCTest("Scythe", function()
	local s = Scythe.scope()
	Scythe.add(s, dummyTask)
	Scythe.destroy(s)
end)

print("\nBenchmark Complete! 🚀")
