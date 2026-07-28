--!nocheck
--!optimize 2

--[[
    Bulk Cleanup (1,000 items) Benchmark

    Measures hot-loop cleanup throughput when disposing a large batch of 1,000 tracked items in a single scope.

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
		["Scythe"] = function(_Profiler, _Count: number)
			local scope = Scythe.scope()
			for _ = 1, 1000 do
				Scythe.add(scope, noop)
			end
			Scythe.clean(scope)
			Scythe.destroy(scope)
		end,

		["Janitor"] = function(_Profiler, _Count: number)
			local jan = Janitor.new()
			for _ = 1, 1000 do
				jan:Add(noop)
			end
			jan:Cleanup()
			jan:Destroy()
		end,

		["Maid"] = function(_Profiler, _Count: number)
			local maid = Maid.new()
			for _ = 1, 1000 do
				maid:GiveTask(noop)
			end
			maid:DoCleaning()
			maid:Destroy()
		end,

		["Trove"] = function(_Profiler, _Count: number)
			local trove = Trove.new()
			for _ = 1, 1000 do
				trove:Add(noop)
			end
			trove:Clean()
			trove:Destroy()
		end,
	},
}
