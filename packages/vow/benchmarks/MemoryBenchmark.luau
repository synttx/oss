--!nocheck
--!optimize 2

--[[
	Asynchronous Memory Allocation & GC Pressure Benchmark

	Measures Peak Active RAM (Cold/Warm footprint) and Total GC Garbage
	generated across hundreds of thousands of asynchronous cycles.

	Lower numbers are better.

	Contenders:
	- Vow (by checcerr | fridayqx)
	- Promise (by evaera)
	- Future (by RedBlox)
	- Future (by YetAnotherClown)

	Note: Run this benchmark with the Roblox Studio command bar.
]]

local RUN_VOW = true
local RUN_PROMISE = true
local RUN_REDBLOX = true
local RUN_YAC = true

local Vow = require('../sync/Vow')
local Promise = RUN_PROMISE and require('path to evaera`s Promise') or nil
local RedBloxFuture = RUN_REDBLOX and require('path to RedBlox`s Future') or nil
local YACFuture = RUN_YAC and require('path to YetAnotherClown`s Future') or nil

-- Hoisted callbacks
local function vowExec(id) Vow.resolve(id, 1) end
local function promiseExec(resolve) resolve(1) end
local function futureExec() return 1 end
local function chainFunc(val) return val + 1 end
local function yacChainFunc(val) return YACFuture.new(futureExec) end

local ACTIVE_ITERATIONS = 50_000
local GC_ITERATIONS = 200_000

local function printHeader(title)
	print("\n=================================================================")
	print(" " .. title)
	print("=================================================================")
end

local function runActiveTest(libName, setupFn, teardownFn, preAllocFn)
	task.wait(1.5)

	local startMem = gcinfo()

	if preAllocFn then preAllocFn() end

	local peakMem = gcinfo()

	for i = 1, ACTIVE_ITERATIONS do
		setupFn(i)

		if i % 50 == 0 then
			local currentMem = gcinfo()
			if currentMem > peakMem then
				peakMem = currentMem
			end
		end
	end

	local currentMemFinal = gcinfo()
	if currentMemFinal > peakMem then
		peakMem = currentMemFinal
	end

	for i = 1, ACTIVE_ITERATIONS do
		teardownFn(i)
	end

	local allocatedKB = math.max(0, peakMem - startMem)
	local bytesPerScope = (allocatedKB * 1024) / ACTIVE_ITERATIONS

	print(string.format("%-22s | Peak Active RAM: %8.2f KB | %6.2f Bytes per chain", libName, allocatedKB, bytesPerScope))
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
	print(string.format("%-22s | Total GC Garbage: %8.2f KB | %6.2f Bytes per cycle", libName, allocations, bytesPerCycle))
end

-- =======================================================================
-- LIBRARY ANCHORS (Pre-allocated so they don't corrupt the benchmark)
-- =======================================================================
local promiseAnchor = table.create(ACTIVE_ITERATIONS)
local redbloxAnchor = table.create(ACTIVE_ITERATIONS)
local yacAnchor = table.create(ACTIVE_ITERATIONS)
local vowAnchor1 = table.create(ACTIVE_ITERATIONS)
local vowAnchor2 = table.create(ACTIVE_ITERATIONS)

-- =======================================================================
-- EXECUTION
-- =======================================================================

print("\nStarting Ultimate Async Memory Benchmark...")
print(`Tracking {ACTIVE_ITERATIONS} active chains, and {GC_ITERATIONS} GC cycles.`)
print("Studio will freeze for a moment during calculations...\n")

-- --- PHASE 1: COLD START ---
printHeader("PHASE 1: COLD ACTIVE FOOTPRINT (Fresh Memory)")

if RUN_PROMISE then
	runActiveTest("evaera Promise",
		function(i) promiseAnchor[i] = Promise.new(promiseExec):andThen(chainFunc) end,
		function(i) promiseAnchor[i]:cancel(); promiseAnchor[i] = nil end
	)
end
if RUN_REDBLOX then
	runActiveTest("RedBlox Future",
		function(i) local f = RedBloxFuture.new(futureExec); f:After(chainFunc); redbloxAnchor[i] = f end,
		function(i) redbloxAnchor[i] = nil end
	)
end
if RUN_YAC then
	runActiveTest("YetAnotherClown Future",
		function(i) local f = YACFuture.new(futureExec); yacAnchor[i] = f:andThen(yacChainFunc); f:poll() end,
		function(i) yacAnchor[i] = nil end
	)
end
if RUN_VOW then
	runActiveTest("checcerr Vow",
		function(i)
			local v1 = Vow.new(vowExec)
			local v2 = Vow.andThen(v1, chainFunc)
			vowAnchor1[i] = v1
			vowAnchor2[i] = v2
		end,
		function(i)
			Vow.destroy(vowAnchor1[i])
			Vow.destroy(vowAnchor2[i])
		end,
		function()
			if Vow.reserve then
				Vow.reserve(ACTIVE_ITERATIONS * 2, ACTIVE_ITERATIONS * 2)
			end
		end
	)
end

-- --- PHASE 2: WARM START ---
printHeader("PHASE 2: WARM ACTIVE FOOTPRINT (Reused Memory)")

if RUN_PROMISE then
	runActiveTest("evaera Promise",
		function(i) promiseAnchor[i] = Promise.new(promiseExec):andThen(chainFunc) end,
		function(i) promiseAnchor[i]:cancel(); promiseAnchor[i] = nil end
	)
end
if RUN_REDBLOX then
	runActiveTest("RedBlox Future",
		function(i) local f = RedBloxFuture.new(futureExec); f:After(chainFunc); redbloxAnchor[i] = f end,
		function(i) redbloxAnchor[i] = nil end
	)
end
if RUN_YAC then
	runActiveTest("YetAnotherClown Future",
		function(i) local f = YACFuture.new(futureExec); yacAnchor[i] = f:andThen(yacChainFunc); f:poll() end,
		function(i) yacAnchor[i] = nil end
	)
end
if RUN_VOW then
	runActiveTest("checcerr Vow",
		function(i)
			local v1 = Vow.new(vowExec)
			local v2 = Vow.andThen(v1, chainFunc)
			vowAnchor1[i] = v1
			vowAnchor2[i] = v2
		end,
		function(i)
			Vow.destroy(vowAnchor1[i])
			Vow.destroy(vowAnchor2[i])
		end
		-- Note: No reserve function passed here, because it's already reserved from Phase 1!
	)
end


-- --- PHASE 3: GARBAGE COLLECTION ---
printHeader("PHASE 3: STEADY-STATE GARBAGE GENERATION (200,000 Cycles)")

if RUN_PROMISE then
	runGCTest("evaera Promise", function()
		Promise.new(promiseExec):andThen(chainFunc)
	end)
end
if RUN_REDBLOX then
	runGCTest("RedBlox Future", function()
		local f = RedBloxFuture.new(futureExec)
		f:After(chainFunc)
	end)
end
if RUN_YAC then
	runGCTest("YetAnotherClown Future", function()
		local f = YACFuture.new(futureExec)
		f:andThen(yacChainFunc)
		f:poll()
	end)
end
if RUN_VOW then
	runGCTest("checcerr Vow", function()
		local v1 = Vow.new(vowExec)
		local v2 = Vow.andThen(v1, chainFunc)
		Vow.destroy(v1)
		Vow.destroy(v2)
	end)
end

print("\nBenchmark Complete! 🚀")
