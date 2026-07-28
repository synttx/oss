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

    Quenty's Maid is excluded because it does not support untracking arbitrary object references without disposing them; setting maid[key] = nil immediately executes cleanup on the task.

    Note: Run this benchmark with boatbomber's Benchmarker or bitsplicer's Scriptbench plugins.
]]

local Scythe = require('../src/scythe.luau')
local Janitor = require('path to howmanysmall`s Janitor')
local Trove = require('path to sleitnick`s Trove')

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
		["Scythe"] = function(_Profiler, _Count: number)
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
		end,

		["Janitor"] = function(_Profiler, _Count: number)
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
		end,

		["Trove"] = function(_Profiler, _Count: number)
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
		end,
	},
}
