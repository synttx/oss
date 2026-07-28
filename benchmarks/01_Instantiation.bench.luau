--!nocheck
--!optimize 2

--[[
    Scope / Object Instantiation & Immediate Destruction Benchmark

    Measures the overhead of instantiating and destroying 1,000 empty cleanup objects/scopes.

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

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local scope = Scythe.scope()
				Scythe.destroy(scope)
			end
		end,

		["Janitor"] = function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local jan = Janitor.new()
				jan:Destroy()
			end
		end,

		["Maid"] = function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local maid = Maid.new()
				maid:Destroy()
			end
		end,

		["Trove"] = function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local trove = Trove.new()
				trove:Destroy()
			end
		end,
	},
}
