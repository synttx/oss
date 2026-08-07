--!strict
--!optimize 2

--[[
	Chaining & Transformation Benchmark

	Measures the overhead of attaching fulfillment callbacks (`andThen` / `After`)
	to a resolved value to transform it 1,000 times.

	Contenders:
	- Vow (by checcerr | fridayqx)
	- Promise (by evaera)
	- Future (by RedBlox)
	- Future (by YetAnotherClown)


	Lower execution time is better.
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
local function chainFunc(val) return val + 1 end
local function yacChainFunc(val) return YACFuture.new(futureExec) end

return {
	ParameterGenerator = function() return 1000 end,

	Functions = {
		["Vow"] = if RUN_VOW then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				local v1 = Vow.new(vowExec)
				local v2 = Vow.andThen(v1, chainFunc)
				Vow.destroy(v1)
				Vow.destroy(v2)
			end
		end else nil,

		["evaera Promise"] = if RUN_PROMISE then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				Promise.resolve(1):andThen(chainFunc)
			end
		end else nil,

		["RedBlox Future (After)"] = if RUN_REDBLOX then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				local f = RedBloxFuture.new(futureExec)
				f:After(chainFunc)
			end
		end else nil,

		["YetAnotherClown Future"] = if RUN_YAC then function(_Profiler, _Count: number)
			for _ = 1, _Count do
				local f = YACFuture.new(futureExec)
				f:andThen(yacChainFunc)
				f:poll()
			end
		end else nil,
	},
}
