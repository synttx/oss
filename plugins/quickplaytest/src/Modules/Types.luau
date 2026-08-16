--!strict
--!optimize 2

--[[
	@name Types
	@arch shared

	@desc Shared type definitions across Quick Playtest modules.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Types
export type InputState = {
	W: boolean,
	A: boolean,
	S: boolean,
	D: boolean,
	Space: boolean,
	Q: boolean,
	E: boolean,
	Ctrl: boolean,
	RMB: boolean,
}

export type MovementSettings = {
	walkSpeed: number,
	jumpPower: number,
	fly: boolean,
	noclip: boolean,
	includeGravity: boolean,
	clickToTeleport: boolean,
	maxSlopeAngle: number,
}

export type AnimationIds = {
	idle: number,
	walk: number,
	jump: number,
	fall: number,
	climb: number,
	swim: number,
	swimidle: number,
	sit: number,
}

export type EmoteDefinition = {
	name: string,
	command: string,
	idR15: number,
	idR6: number,
	looped: boolean,
	isUserEmote: boolean?,
}

export type Rig = {
	model: Model,
	dummyModel: Model,
	humanoid: Humanoid,
	animator: Animator,
	root: BasePart,
	visualParts: { BasePart },
	animationIds: AnimationIds,
	groundOffset: number,
	centerOffset: number,
	colliderSize: Vector3,
	isR15: boolean,
	ownerUserId: number,
	ownerUsername: string,
}

export type MotionResult = {
	position: Vector3,
	velocity: Vector3,
	state: string,
	moveDirection: Vector3,
	grounded: boolean,
	seat: BasePart?,
}

export type Config = {
	DEBUG: boolean,
	COLLISION_SKIN: number,
	COLLISION_ITERATIONS: number,
	FIXED_STEP: number,
	MAX_STEPS: number,
	GROUND_SNAP: number,
	MAX_SLOPE_ANGLE: number,
	STEP_HEIGHT: number,
	GROUND_ACCELERATION: number,
	AIR_ACCELERATION: number,
	SWIM_ACCELERATION: number,
	FLY_ACCELERATION: number,
	FLY_SPEED_MULTIPLIER: number,
	SWIM_SPEED_MULTIPLIER: number,
	SEAT_SCAN_INTERVAL: number,
	WATER_SCAN_INTERVAL: number,
	CLIMB_SCAN_INTERVAL: number,
	POSE_REPLICATION_INTERVAL: number,
	CAMERA_ZOOM_MIN: number,
	CAMERA_ZOOM_MAX: number,
	CAMERA_ZOOM_DEFAULT: number,
	CAMERA_PITCH_MIN: number,
	CAMERA_PITCH_MAX: number,
	CAMERA_SENSITIVITY: number,
	FIRST_PERSON_TRANSITION_SPEED: number,
	ICON_ID: string,
	ANIMATIONS: {
		R15: AnimationIds,
		R6: AnimationIds,
	},
	DEFAULT_EMOTES: { [string]: EmoteDefinition },
}

export type Palette = {
	background: Color3,
	surface: Color3,
	surfaceHover: Color3,
	surfaceActive: Color3,
	border: Color3,
	text: Color3,
	dim: Color3,
	accent: Color3,
	accentHover: Color3,
	accentText: Color3,
	danger: Color3,
	dangerHover: Color3,
	input: Color3,
	tabActive: Color3,
	tabInactive: Color3,
}

return {}

-- checcerr.
