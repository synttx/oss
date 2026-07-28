--!nocheck
--!optimize 2

--[[
    Mixed Workload Benchmark

    Measures performance under a realistic mixed workload (functions, connections, instances, threads - 200 items total) cleaned and destroyed.

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

local function createMockConnection()
	return {
		Connected = true,
		Disconnect = function(self)
			self.Connected = false
		end,
	}
end

local function createMockInstance()
	return {
		Destroy = function(self)
			self._destroyed = true
		end,
	}
end

local function createMockThread()
	return coroutine.create(function()
		task.wait(100)
	end)
end

return {
	ParameterGenerator = function()
		return 100
	end,

	Functions = {
		["Scythe"] = function(_Profiler, _Count: number)
			local scope = Scythe.scope()
			for _ = 1, 50 do
				Scythe.add(scope, noop)
				Scythe.add(scope, createMockConnection())
				Scythe.add(scope, createMockInstance())
				Scythe.add(scope, createMockThread())
			end
			Scythe.clean(scope)
			Scythe.destroy(scope)
		end,

		["Janitor"] = function(_Profiler, _Count: number)
			local jan = Janitor.new()
			for _ = 1, 50 do
				jan:Add(noop)
				jan:Add(createMockConnection(), "Disconnect")
				jan:Add(createMockInstance(), "Destroy")
				jan:Add(createMockThread())
			end
			jan:Cleanup()
			jan:Destroy()
		end,

		["Maid"] = function(_Profiler, _Count: number)
			local maid = Maid.new()
			for _ = 1, 50 do
				maid:GiveTask(noop)
				maid:GiveTask(createMockConnection())
				maid:GiveTask(createMockInstance())
				maid:GiveTask(createMockThread())
			end
			maid:DoCleaning()
			maid:Destroy()
		end,

		["Trove"] = function(_Profiler, _Count: number)
			local trove = Trove.new()
			for _ = 1, 50 do
				trove:Add(noop)
				trove:Add(createMockConnection(), "Disconnect")
				trove:Add(createMockInstance(), "Destroy")
				trove:Add(createMockThread())
			end
			trove:Clean()
			trove:Destroy()
		end,
	},
}
