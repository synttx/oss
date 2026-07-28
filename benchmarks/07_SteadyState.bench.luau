--!nocheck
--!optimize 2

--[[
    Steady-State Short-Lived Scope Benchmark

    Measures handle pooling and buffer reuse overhead across 100 rapid allocation and cleanup cycles (10 items each).

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
			for _ = 1, 100 do
				local scope = Scythe.scope()
				for _ = 1, 10 do
					Scythe.add(scope, noop)
				end
				Scythe.destroy(scope)
			end
		end,

		["Janitor"] = function(_Profiler, _Count: number)
			for _ = 1, 100 do
				local jan = Janitor.new()
				for _ = 1, 10 do
					jan:Add(noop)
				end
				jan:Destroy()
			end
		end,

		["Maid"] = function(_Profiler, _Count: number)
			for _ = 1, 100 do
				local maid = Maid.new()
				for _ = 1, 10 do
					maid:GiveTask(noop)
				end
				maid:Destroy()
			end
		end,

		["Trove"] = function(_Profiler, _Count: number)
			for _ = 1, 100 do
				local trove = Trove.new()
				for _ = 1, 10 do
					trove:Add(noop)
				end
				trove:Destroy()
			end
		end,
	},
}
