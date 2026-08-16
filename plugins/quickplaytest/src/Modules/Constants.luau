--!strict
--!optimize 2

--[[
	@name Constants
	@arch shared

	@desc Default tuning values, animation assets, emote IDs, and plugin constants.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Constants
const Constants = {
	DEBUG = true,

	-- Plugin Asset
	ICON_ID = "rbxassetid://75517704743986",

	-- Collision & Kinematics
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

	-- Sensor Intervals
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

	-- Avatar Locomotion Animations
	ANIMATIONS = {
		R15 = {
			idle = 507766666,
			walk = 507777826,
			jump = 507765000,
			fall = 507767968,
			climb = 507765644,
			swim = 507784897,
			swimidle = 507785072,
			sit = 2506281703,
		},
		R6 = {
			idle = 180435571,
			walk = 180426354,
			jump = 125750702,
			fall = 180436148,
			climb = 180436330,
			swim = 180426354,
			swimidle = 180435571,
			sit = 178130996,
		},
	},

	-- Default Emotes
	DEFAULT_EMOTES = {
		wave = {
			name = "Wave",
			command = "/e wave",
			idR15 = 507770239,
			idR6 = 128777973,
			looped = false,
		},
		cheer = {
			name = "Cheer",
			command = "/e cheer",
			idR15 = 507770677,
			idR6 = 128777973,
			looped = false,
		},
		laugh = {
			name = "Laugh",
			command = "/e laugh",
			idR15 = 507770818,
			idR6 = 129423131,
			looped = false,
		},
		point = {
			name = "Point",
			command = "/e point",
			idR15 = 507770453,
			idR6 = 128853357,
			looped = false,
		},
		dance1 = {
			name = "Dance 1",
			command = "/e dance1",
			idR15 = 507771019,
			idR6 = 182435998,
			looped = true,
		},
		dance2 = {
			name = "Dance 2",
			command = "/e dance2",
			idR15 = 507776720,
			idR6 = 182436842,
			looped = true,
		},
		dance3 = {
			name = "Dance 3",
			command = "/e dance3",
			idR15 = 507777268,
			idR6 = 182436935,
			looped = true,
		},
	},
}

return table.freeze(Constants)

-- checcerr.
