--!strict
--!optimize 2

--[[
	@name Config
	@arch shared

	@desc Dynamic configuration manager storing customizable settings in TestService.QuickPlaytestConfig with safe default fallback.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local Selection = game:GetService("Selection")
local TestService = game:GetService("TestService")

local Constants = require("./Constants")
local Types = require("./Types")

--/ Types
type ConfigType = Types.Config

--/ Constants
const CONFIG_SCRIPT_NAME = "QuickPlaytestConfig"

const DEFAULT_CONFIG_SOURCE = [===[--!strict
--!optimize 2

--[[
	Quick Playtest Configuration
	You can modify any setting below. Changes take effect on next playtest spawn.
	If any field is missing or invalid, Quick Playtest will safely fall back to defaults.
]]

return {
	-- Enable debug assertions and logs
	DEBUG = true,

	-- Collision & Physics
	COLLISION_SKIN = 0.035,
	COLLISION_ITERATIONS = 4,
	FIXED_STEP = 1 / 120,
	MAX_STEPS = 12,
	GROUND_SNAP = 0.35,
	MAX_SLOPE_ANGLE = 55,
	STEP_HEIGHT = 1.25,
	GROUND_ACCELERATION = 60,
	AIR_ACCELERATION = 35,
	SWIM_ACCELERATION = 8,
	FLY_ACCELERATION = 10,
	FLY_SPEED_MULTIPLIER = 2.5,
	SWIM_SPEED_MULTIPLIER = 0.7,

	-- Sensor Intervals (seconds)
	SEAT_SCAN_INTERVAL = 0.12,
	WATER_SCAN_INTERVAL = 0.1,
	CLIMB_SCAN_INTERVAL = 0.08,
	POSE_REPLICATION_INTERVAL = 1 / 60,

	-- Camera
	CAMERA_ZOOM_MIN = 0,
	CAMERA_ZOOM_MAX = 40,
	CAMERA_ZOOM_DEFAULT = 10,
	CAMERA_PITCH_MIN = -80,
	CAMERA_PITCH_MAX = 80,
	CAMERA_SENSITIVITY = 0.3,
	FIRST_PERSON_TRANSITION_SPEED = 12,
}
]===]

--/ Module
local Config = {}

--/ Functions

--[[
	@name getOrCreateConfigScript
	@arch shared

	@desc Locates or creates the QuickPlaytestConfig ModuleScript in TestService.

	@returns ModuleScript Config script instance.

	@raises nil
]]
local function getOrCreateConfigScript(): ModuleScript
	local configScript = TestService:FindFirstChild(CONFIG_SCRIPT_NAME)
	if not configScript or not configScript:IsA("ModuleScript") then
		const newScript = Instance.new("ModuleScript")
		newScript.Name = CONFIG_SCRIPT_NAME
		newScript.Source = DEFAULT_CONFIG_SOURCE
		newScript.Parent = TestService
		return newScript
	end
	return configScript :: ModuleScript
end

--[[
	@name get
	@arch shared

	@desc Loads custom configuration from TestService with automatic fallback to Constants.

	@returns Config Complete configuration table.

	@raises nil
]]
function Config.get(): ConfigType
	const configScript = getOrCreateConfigScript()
	local customConfig: { [string]: any } = {}

	local success, result = pcall(function()
		return require(configScript)
	end)
	if success and type(result) == "table" then
		customConfig = result
	end

	const config: any = {}
	for key, defaultValue in Constants :: any do
		const userVal = customConfig[key]
		if userVal ~= nil and type(userVal) == type(defaultValue) then
			config[key] = userVal
		else
			config[key] = defaultValue
		end
	end

	return config :: ConfigType
end

--[[
	@name openConfig
	@arch server

	@desc Opens the configuration module script in Studio editor or selects it.

	@param pluginInstance Plugin Studio plugin instance.

	@returns nil

	@raises nil
]]
function Config.openConfig(pluginInstance: Plugin)
	const configScript = getOrCreateConfigScript()
	local opened = false
	pcall(function()
		pluginInstance:OpenScript(configScript)
		opened = true
	end)
	if not opened then
		Selection:Set({ configScript })
	end
end

return table.freeze(Config)

-- checcerr.
