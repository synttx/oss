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
    - create-scope (by sap0bombado)

    Note: Run this benchmark with boatbomber's Benchmarker or bitsplicer's Scriptbench plugins.
]]


local RUN_SCYTHE = true
local RUN_CREATE_SCOPE = false
local RUN_JANITOR = false
local RUN_MAID = false
local RUN_TROVE = false

local Scythe = require('../src/scythe.luau')
local CreateScope = RUN_CREATE_SCOPE and require('path to sap0bombado`s create-scope') or nil
local Janitor = RUN_JANITOR and require('path to howmanysmall`s Janitor') or nil
local Maid = RUN_MAID and require('path to Quenty`s Maid') or nil
local Trove = RUN_TROVE and require('path to sleitnick`s Trove') or nil

local function noop() end

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = if RUN_SCYTHE then function(_Profiler, _Count: number)
			local scope = Scythe.scope()
			for _ = 1, 1000 do
				Scythe.add(scope, noop)
			end
			Scythe.clean(scope)
			Scythe.destroy(scope)
		end else nil,
		["CreateScope"] = if RUN_CREATE_SCOPE then function(_Profiler, _Count: number)
			local scope = CreateScope()
			for _ = 1, 1000 do
				scope(noop)
			end
			scope()
		end else nil,

		["Janitor"] = if RUN_JANITOR then function(_Profiler, _Count: number)
			local jan = Janitor.new()
			for _ = 1, 1000 do
				jan:Add(noop)
			end
			jan:Cleanup()
			jan:Destroy()
		end else nil,

		["Maid"] = if RUN_MAID then function(_Profiler, _Count: number)
			local maid = Maid.new()
			for _ = 1, 1000 do
				maid:GiveTask(noop)
			end
			maid:DoCleaning()
			maid:Destroy()
		end else nil,

		["Trove"] = if RUN_TROVE then function(_Profiler, _Count: number)
			local trove = Trove.new()
			for _ = 1, 1000 do
				trove:Add(noop)
			end
			trove:Clean()
			trove:Destroy()
		end else nil,
	},
}
