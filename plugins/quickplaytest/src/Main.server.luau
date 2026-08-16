--!strict
--!optimize 2

--[[
	@name Main
	@arch server

	@desc Quick Playtest plugin composition root.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local SessionController = require("./Modules/SessionController")
local Widget = require("./Modules/Widget")

--/ Initialization
const widget = Widget.new(plugin)
const session = SessionController.new(plugin, widget)
session:Bind()

plugin.Unloading:Connect(function()
	session:Destroy()
	widget:Destroy()
end)

-- checcerr.
