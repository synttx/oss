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

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = if RUN_SCYTHE then function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local scope = Scythe.scope()
				Scythe.destroy(scope)
			end
		end else nil,
		["CreateScope"] = if RUN_CREATE_SCOPE then function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local scope = CreateScope()
				scope()
			end
		end else nil,

		["Janitor"] = if RUN_JANITOR then function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local jan = Janitor.new()
				jan:Destroy()
			end
		end else nil,

		["Maid"] = if RUN_MAID then function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local maid = Maid.new()
				maid:Destroy()
			end
		end else nil,

		["Trove"] = if RUN_TROVE then function(_Profiler, _Count: number)
			for _ = 1, 1000 do
				local trove = Trove.new()
				trove:Destroy()
			end
		end else nil,
	},
}
