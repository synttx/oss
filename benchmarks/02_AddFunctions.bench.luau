--!nocheck
--!optimize 2

--[[
    Add Functions Benchmark

    Measures the efficiency of tracking and invoking 100 function cleanup callbacks per scope.

    Lower execution time is better.

    Contenders:
    - Scythe (by checcerr | fridayqx)
    - Janitor (by howmanysmall)
    - Maid (by Quenty)
    - Trove (by sleitnick)

    Note: Run this benchmark with boatbomber's Benchmarker or bitsplicer's Scriptbench plugins.
]]


local Scythe = require('../src/scythe.luau')
local Janitor = require('path to howmanysmall`s Janitor')
local Maid = require('path to Quenty`s Maid')
local Trove = require('path to sleitnick`s Trove')

local function noop() end

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = function(_Profiler, Count: number)
			local scope = Scythe.scope()
			for _ = 1, Count do
				Scythe.add(scope, noop)
			end
			Scythe.destroy(scope)
		end,

		["Janitor"] = function(_Profiler, Count: number)
			local jan = Janitor.new()
			for _ = 1, Count do
				jan:Add(noop)
			end
			jan:Destroy()
		end,

		["Maid"] = function(_Profiler, Count: number)
			local maid = Maid.new()
			for _ = 1, Count do
				maid:GiveTask(noop)
			end
			maid:Destroy()
		end,

		["Trove"] = function(_Profiler, Count: number)
			local trove = Trove.new()
			for _ = 1, Count do
				trove:Add(noop)
			end
			trove:Destroy()
		end,
	},
}
