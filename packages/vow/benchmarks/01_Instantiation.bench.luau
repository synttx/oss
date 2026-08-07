--!strict
--!optimize 2

--[[
	Instantiation & Immediate Resolution Benchmark

	Measures the overhead of creating and resolving 1,000 asynchronous values.

	Lower execution time is better.

	Contenders:
	- Vow (by checcerr | fridayqx)
	- Promise (by evaera)
	- Future (by RedBlox)
	- Future (by YetAnotherClown)

	Note: Run this benchmark with boatbomber's Benchmarker or bitsplicer's Scriptbench plugins.
]]

local RUN_VOW = true
local RUN_PROMISE = true
local RUN_REDBLOX = true
local RUN_YAC = true

local Vow = require('../sync/Vow')
local Promise = RUN_PROMISE and require('path to evaera`s Promise') or nil
local RedBloxFuture = RUN_REDBLOX and require('path to RedBlox`s Future') or nil
local YACFuture = RUN_YAC and require('path to YetAnotherClown`s Future') or nil

local function vowExec(id) Vow.resolve(id, 1) end
local function promiseExec(resolve) resolve(1) end
local function futureExec() return 1 end

return {
	ParameterGenerator = function() return 1000 end,

	Functions = {
		["Vow"] = if RUN_VOW then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				local v = Vow.new(vowExec)
				Vow.destroy(v)
			end
		end else nil,

		["evaera Promise"] = if RUN_PROMISE then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				Promise.new(promiseExec)
			end
		end else nil,

		["RedBlox Future"] = if RUN_REDBLOX then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				RedBloxFuture.new(futureExec)
			end
		end else nil,

		["YetAnotherClown Future"] = if RUN_YAC then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				YACFuture.new(futureExec):poll()
			end
		end else nil,
	},
}
