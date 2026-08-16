--!strict
--!optimize 2

--[[
	@name PoseController
	@arch server

	@desc Evaluates equipped locomotion tracks and poses with smooth local transforms and bounded Team Create sync.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local Config = require("./Config")
local Types = require("./Types")

--/ Types
type AnimationIds = Types.AnimationIds
type Rig = Types.Rig
type MotorRecord = {
	motor: Motor6D,
	dummyMotor: Motor6D,
	restC0: CFrame,
	replicatedPose: CFrame,
}
type Self = {
	rig: Rig,
	tracks: { [string]: AnimationTrack },
	motors: { MotorRecord },
	state: string,
	replicationClock: number,
}

--/ Class
local PoseController = {}
PoseController.__index = PoseController

--/ Functions

--[[
	@name convertAnimationConstraints
	@arch server

	@desc Converts modern AnimationConstraint joints to serializable Motor6D joints.

	@param model Model Avatar model.
	@returns nil
	@raises nil
]]
local function convertAnimationConstraints(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			const attachment0 = descendant.Attachment0
			const attachment1 = descendant.Attachment1
			if attachment0 and attachment1 then
				const part0 = attachment0.Parent
				const part1 = attachment1.Parent
				if part0 and part0:IsA("BasePart") and part1 and part1:IsA("BasePart") then
					const motor = Instance.new("Motor6D")
					motor.Name = descendant.Name:gsub("Constraint$", "")
					motor.Part0 = part0
					motor.Part1 = part1
					motor.C0 = attachment0.CFrame
					motor.C1 = attachment1.CFrame
					motor.Parent = part0
					descendant:Destroy()
				end
			end
		end
	end
end

--[[
	@name collectMotors
	@arch server

	@desc Maps real avatar body motors to dummy animator motors.

	@param model Model Character model.
	@param dummyModel Model Separate dummy rig model.
	@returns { MotorRecord } Motor records.
	@raises nil
]]
local function collectMotors(model: Model, dummyModel: Model): { MotorRecord }
	local motors: { MotorRecord } = {}
	local dummyMotors = {}
	for _, descendant in dummyModel:GetDescendants() do
		if descendant:IsA("Motor6D") then
			dummyMotors[descendant.Name] = descendant
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and not descendant:IsDescendantOf(dummyModel) then
			const dummyMotor = dummyMotors[descendant.Name]
			if dummyMotor then
				table.insert(motors, {
					motor = descendant,
					dummyMotor = dummyMotor,
					restC0 = descendant.C0,
					replicatedPose = CFrame.identity,
				})
			end
		end
	end
	return motors
end

--[[
	@name tryLoadTrack
	@arch server

	@desc Attempts to load an animation track onto the dummy animator.

	@param animator Animator Dummy rig animator.
	@param name string Track name identifier.
	@param assetId number Animation asset ID.
	@returns AnimationTrack? Loaded track if successful.
	@raises nil
]]
local function tryLoadTrack(animator: Animator, name: string, assetId: number): AnimationTrack?
	const animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = `rbxassetid://{assetId}`
	const success, result = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not success then
		return nil
	end
	const track = result :: AnimationTrack
	track.Name = name
	track.Looped = name ~= "jump"
	track.Priority = if name == "idle"
		then Enum.AnimationPriority.Idle
		elseif name == "walk" or name == "swim" or name == "swimidle" then Enum.AnimationPriority.Movement
		else Enum.AnimationPriority.Action
	return track
end

--[[
	@name addTrack
	@arch server

	@desc Loads an equipped animation track with automatic default fallback.

	@param tracks { [string]: AnimationTrack } Track dictionary.
	@param animator Animator Animator instance.
	@param name string Track identifier.
	@param assetId number Catalog asset ID.
	@param fallbackId number Fallback default asset ID.
	@returns nil
	@raises nil
]]
local function addTrack(
	tracks: { [string]: AnimationTrack },
	animator: Animator,
	name: string,
	assetId: number,
	fallbackId: number
)
	local track = tryLoadTrack(animator, name, assetId)
	if not track and fallbackId ~= assetId then
		track = tryLoadTrack(animator, name, fallbackId)
	end
	if track then
		tracks[name] = track
	end
end

--[[
	@name loadTracks
	@arch server

	@desc Loads all primary locomotion tracks for avatar rig.

	@param rig Rig Avatar rig structure.
	@returns { [string]: AnimationTrack } Loaded track dictionary.
	@raises nil
]]
local function loadTracks(rig: Rig): { [string]: AnimationTrack }
	const config = Config.get()
	const ids = rig.animationIds
	const fallback: AnimationIds = if rig.isR15 then config.ANIMATIONS.R15 else config.ANIMATIONS.R6
	local tracks: { [string]: AnimationTrack } = {}
	addTrack(tracks, rig.animator, "idle", ids.idle, fallback.idle)
	addTrack(tracks, rig.animator, "walk", ids.walk, fallback.walk)
	addTrack(tracks, rig.animator, "jump", ids.jump, fallback.jump)
	addTrack(tracks, rig.animator, "fall", ids.fall, fallback.fall)
	addTrack(tracks, rig.animator, "climb", ids.climb, fallback.climb)
	addTrack(tracks, rig.animator, "swim", ids.swim, fallback.swim)
	addTrack(tracks, rig.animator, "swimidle", ids.swimidle, fallback.swimidle)
	addTrack(tracks, rig.animator, "sit", ids.sit, fallback.sit)
	return tracks
end

--[[
	@name new
	@arch server

	@desc Initializes PoseController for character rig.

	@param rig Rig Avatar rig structure.
	@returns Self PoseController instance.
	@raises nil
]]
function PoseController.new(rig: Rig): Self
	convertAnimationConstraints(rig.model)
	convertAnimationConstraints(rig.dummyModel)

	const self: Self = setmetatable({
		rig = rig,
		tracks = loadTracks(rig),
		motors = collectMotors(rig.model, rig.dummyModel),
		state = "idle",
		replicationClock = 0,
	}, PoseController) :: any

	const idleTrack = self.tracks.idle
	if idleTrack then
		idleTrack:Play(0)
	end

	return self
end

--[[
	@name SetState
	@arch server

	@desc Crossfades to target locomotion animation state and updates speed.

	@param self Self PoseController instance.
	@param state string Locomotion state string.
	@param speed number Horizontal movement speed.
	@returns nil
	@raises nil
]]
function PoseController.SetState(self: Self, state: string, speed: number)
	if state ~= self.state then
		const oldTrack = self.tracks[self.state]
		if oldTrack then
			oldTrack:Stop(0.12)
		end
		self.state = state
		const newTrack = self.tracks[state]
		if newTrack then
			newTrack:Play(0.12)
		end
	end

	const track = self.tracks[state]
	if track then
		if state == "walk" or state == "swim" then
			track:AdjustSpeed(math.clamp(speed / 14, 0.2, 2.5))
		elseif state == "climb" then
			track:AdjustSpeed(if speed > 0.1 then 1 else 0)
		end
	end
end

--[[
	@name holdRestPose
	@arch server

	@desc Holds neutral pose for flight mode.

	@param record MotorRecord Motor binding record.
	@param replicate boolean Replication snapshot flag.
	@returns nil
	@raises nil
]]
local function holdRestPose(record: MotorRecord, replicate: boolean)
	if replicate then
		record.replicatedPose = CFrame.identity
		record.motor.C0 = record.restC0
		record.motor.Transform = CFrame.identity
	else
		record.motor.Transform = record.replicatedPose:Inverse()
	end
end

--[[
	@name applyPose
	@arch server

	@desc Evaluates motor transforms from dummy animator.

	@param record MotorRecord Motor binding record.
	@param replicate boolean Replication snapshot flag.
	@returns nil
	@raises nil
]]
local function applyPose(record: MotorRecord, replicate: boolean)
	const targetPose = record.dummyMotor.Transform
	if replicate then
		record.replicatedPose = targetPose
		record.motor.C0 = record.restC0 * targetPose
		record.motor.Transform = CFrame.identity
	else
		record.motor.Transform = record.replicatedPose:Inverse() * targetPose
	end
end

--[[
	@name Step
	@arch server

	@desc Advances animation evaluation and updates Motor6D transforms.

	@param self Self PoseController instance.
	@param deltaTime number Frame delta time.
	@returns nil
	@raises nil
]]
function PoseController.Step(self: Self, deltaTime: number)
	const config = Config.get()
	self.replicationClock += deltaTime
	const replicate = self.replicationClock >= config.POSE_REPLICATION_INTERVAL
	if replicate then
		self.replicationClock %= config.POSE_REPLICATION_INTERVAL
	end

	if self.state == "fly" then
		for _, record in self.motors do
			holdRestPose(record, replicate)
		end
		return
	end

	self.rig.animator:StepAnimations(deltaTime)
	for _, record in self.motors do
		applyPose(record, replicate)
	end
end

--[[
	@name Destroy
	@arch server

	@desc Stops loaded tracks and resets motor joints.

	@param self Self PoseController instance.
	@returns nil
	@raises nil
]]
function PoseController.Destroy(self: Self)
	for _, track in self.tracks do
		track:Stop(0)
		track:Destroy()
	end
	for _, record in self.motors do
		record.motor.C0 = record.restC0
		record.motor.Transform = CFrame.identity
	end
end

export type Controller = typeof(setmetatable({} :: Self, PoseController))

return PoseController

-- checcerr.
