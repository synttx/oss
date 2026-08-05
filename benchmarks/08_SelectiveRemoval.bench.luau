--!nocheck
--!optimize 2

--[[
    Selective Item Removal Benchmark

    Measures the performance of untracking 250 items out of 500 without triggering cleanup.

    Lower execution time is better.

    Contenders:
    - Scythe (by checcerr | fridayqx)
    - Janitor (by howmanysmall)
    - Trove (by sleitnick)
    - create-scope (by sap0bombado)

    Quenty's Maid and sap0bombado's create-scope are excluded because they do not support untracking arbitrary object references without disposing them (e.g. setting maid[key] = nil immediately executes cleanup, and create-scope doesn't expose a removal method at all).

    Note: Run this benchmark with boatbomber's Benchmarker or bitsplicer's Scriptbench plugins.
]]

local RUN_SCYTHE = true
local RUN_JANITOR = false
local RUN_TROVE = false

local Scythe = require('../src/scythe.luau')
local Janitor = RUN_JANITOR and require('path to howmanysmall`s Janitor') or nil
local Trove = RUN_TROVE and require('path to sleitnick`s Trove') or nil

local function createMockConnection()
	return {
		Connected = true,
		Disconnect = function(self)
			self.Connected = false
		end,
	}
end

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = if RUN_SCYTHE then function(_Profiler, _Count: number)
			local scope = Scythe.scope()
			local items = {}
			for i = 1, 500 do
				local conn = createMockConnection()
				items[i] = conn
				Scythe.add(scope, conn)
			end
			for i = 1, 250 do
				Scythe.remove(scope, items[i])
			end
			Scythe.destroy(scope)
		end else nil,

		["Janitor"] = if RUN_JANITOR then function(_Profiler, _Count: number)
			local jan = Janitor.new()
			local items = {}
			for i = 1, 500 do
				local conn = createMockConnection()
				items[i] = conn
				jan:Add(conn, "Disconnect", i)
			end
			for i = 1, 250 do
				jan:RemoveNoClean(i)
			end
			jan:Destroy()
		end else nil,

		["Trove"] = if RUN_TROVE then function(_Profiler, _Count: number)
			local trove = Trove.new()
			local items = {}
			for i = 1, 500 do
				local conn = createMockConnection()
				items[i] = conn
				trove:Add(conn, "Disconnect")
			end
			for i = 1, 250 do
				trove:Remove(items[i])
			end
			trove:Destroy()
		end else nil,
	},
}
