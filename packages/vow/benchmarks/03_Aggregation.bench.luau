--!strict
--!optimize 2

--[[
	Aggregation Benchmark (All / JoinAll)

	Measures the overhead of grouping 100 pending asynchronous tasks into
	a single aggregate value that resolves when all inputs resolve.

	Contenders:
	- Vow (by checcerr | fridayqx)
	- Promise (by evaera)
	- Future (by YetAnotherClown)

	RedBlox's Future is omitted here because it doesn't natively have a `.all` method.

	Lower execution time is better.
]]

local RUN_VOW = true
local RUN_PROMISE = true
local RUN_YAC = true

local Vow = require('../sync/Vow')
local Promise = RUN_PROMISE and require('path to evaera`s Promise') or nil
local YACFuture = RUN_YAC and require('path to YetAnotherClown`s Future') or nil

local function vowExec(id) Vow.resolve(id, 1) end
local function futureExec() return 1 end

return {
	ParameterGenerator = function() return 100 end,

	Functions = {
		["Vow"] = if RUN_VOW then function(_Profiler, _Count: number)
			local list = table.create(_Count)
			for i = 1, _Count do
				list[i] = Vow.new(vowExec)
			end

			local agg = Vow.all(list)

			for i = 1, _Count do Vow.destroy(list[i]) end
			Vow.destroy(agg)
		end else nil,

		["evaera Promise"] = if RUN_PROMISE then function(_Profiler, _Count: number)
			local list = table.create(_Count)
			for i = 1, _Count do
				list[i] = Promise.resolve(1)
			end
			Promise.all(list)
		end else nil,

		["YetAnotherClown Future"] = if RUN_YAC then function(_Profiler, _Count: number)
			local list = table.create(_Count)
			for i = 1, _Count do
				list[i] = YACFuture.new(futureExec)
			end

			local agg = list[1]:joinAll(table.unpack(list, 2, _Count))
			agg:poll()
		end else nil,
	},
}
