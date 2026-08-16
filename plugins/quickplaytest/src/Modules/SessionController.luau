--!strict
--!optimize 2

--[[
	@name SessionController
	@arch server

	@desc Coordinates edit-mode playtest sessions: avatar lifecycle, camera, kinematics, and emotes.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local RunService = game:GetService("RunService")

local CameraController = require("./CameraController")
local CharacterFactory = require("./CharacterFactory")
local Constants = require("./Constants")
local EmoteController = require("./EmoteController")
local InputController = require("./InputController")
local MovementController = require("./MovementController")
local PoseController = require("./PoseController")
local Types = require("./Types")
local Widget = require("./Widget")

--/ Types
type CameraControllerType = CameraController.Controller
type EmoteControllerType = EmoteController.Controller
type InputControllerType = InputController.Controller
type MovementControllerType = MovementController.Controller
type PoseControllerType = PoseController.Controller
type Rig = Types.Rig
type WidgetType = Widget.Controller
type Self = {
	plugin: Plugin,
	widget: WidgetType,
	connections: { RBXScriptConnection },
	isRendering: boolean,
	rig: Rig?,
	input: InputControllerType?,
	camera: CameraControllerType?,
	movement: MovementControllerType?,
	pose: PoseControllerType?,
	emote: EmoteControllerType?,
	rootRotation: CFrame,
	lastStatus: string,
	teleportRaycastParams: RaycastParams?,
}

--/ Class
local SessionController = {}
SessionController.__index = SessionController

--/ Functions

--[[
	@name getYawRotation
	@arch server

	@desc Returns upright yaw orientation transform from a horizontal direction.

	@param direction Vector3 Direction vector.
	@param fallback CFrame Fallback orientation.
	@returns CFrame Computed yaw orientation.
	@raises nil
]]
local function getYawRotation(direction: Vector3, fallback: CFrame): CFrame
	const horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude <= 0.001 then
		return fallback
	end
	return CFrame.lookAt(Vector3.zero, horizontal.Unit)
end

--[[
	@name findSpawnpoint
	@arch server

	@desc Finds first enabled SpawnLocation in workspace hierarchy.

	@returns SpawnLocation? Spawn location if found.
	@raises nil
]]
local function findSpawnpoint(): SpawnLocation?
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			return descendant
		end
	end
	return nil
end

--[[
	@name getCameraStartCFrame
	@arch server

	@desc Calculates spawn position in front of current Studio camera.

	@returns CFrame Spawn transform.
	@raises nil
]]
local function getCameraStartCFrame(): CFrame
	const camera = workspace.CurrentCamera :: Camera
	return CFrame.new(camera.CFrame.Position + camera.CFrame.LookVector * 4)
end

--[[
	@name getSpawnpointCFrame
	@arch server

	@desc Calculates spawn position on top of SpawnLocation using rig clearance.

	@param spawnpoint SpawnLocation Target spawn part.
	@param rig Rig Avatar rig structure.
	@returns CFrame Spawn transform.
	@raises nil
]]
local function getSpawnpointCFrame(spawnpoint: SpawnLocation, rig: Rig): CFrame
	const position = spawnpoint.Position
		+ Vector3.yAxis * (spawnpoint.Size.Y / 2 + rig.groundOffset + Constants.COLLISION_SKIN)
	const rotation = getYawRotation(spawnpoint.CFrame.LookVector, CFrame.identity)
	return CFrame.new(position) * rotation
end

--[[
	@name getTargetRotation
	@arch server

	@desc Computes avatar orientation for seats, camera facing, flight, and walking.

	@param motion Types.MotionResult Movement state.
	@param cameraCFrame CFrame Camera transform.
	@param input Types.InputState User inputs.
	@param faceCamera boolean Whether character faces camera.
	@param fallback CFrame Previous rotation.
	@returns CFrame Target orientation.
	@raises nil
]]
local function getTargetRotation(
	motion: Types.MotionResult,
	cameraCFrame: CFrame,
	input: Types.InputState,
	faceCamera: boolean,
	fallback: CFrame
): CFrame
	if motion.state == "fly" then
		const bankInput = (if input.D then 1 else 0) - (if input.A then 1 else 0)
		return CFrame.lookAt(Vector3.zero, cameraCFrame.LookVector, cameraCFrame.UpVector)
			* CFrame.Angles(0, 0, math.rad(-bankInput * 12))
	end
	if motion.state == "sit" and motion.seat then
		return motion.seat.CFrame.Rotation
	end
	if faceCamera then
		return getYawRotation(cameraCFrame.LookVector, fallback)
	end
	return getYawRotation(motion.moveDirection, fallback)
end

--[[
	@name handleTeleportRaycast
	@arch server

	@desc Raycasts from viewport click point and teleports avatar onto top surface.

	@param self Self SessionController instance.
	@param screenPosition Vector2 Screen coordinate.
	@returns nil
	@raises nil
]]
local function handleTeleportRaycast(self: Self, screenPosition: Vector2)
	const rig = self.rig
	const movement = self.movement
	const emote = self.emote
	if not rig or not movement then
		return
	end

	const camera = workspace.CurrentCamera :: Camera
	const unitRay = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)

	if not self.teleportRaycastParams then
		const raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { rig.model }
		raycastParams.IgnoreWater = true
		raycastParams.RespectCanCollide = true
		self.teleportRaycastParams = raycastParams
	end

	const hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, self.teleportRaycastParams)
	if hit then
		const surfaceNormal = hit.Normal
		local surfaceOffset = Vector3.new(0, rig.groundOffset + 0.05, 0)
		if surfaceNormal.Y < 0.7 then
			surfaceOffset = surfaceNormal * (rig.colliderSize.X * 0.6) + Vector3.yAxis * (rig.groundOffset + 0.05)
		end
		const targetPosition = hit.Position + surfaceOffset
		movement:TeleportTo(targetPosition)
		if emote then
			emote:HandleDisturbance()
		end
	end
end

--[[
	@name handleEmoteDisturbance
	@arch server

	@desc Cancels active emote if character performs intentional movement or has high velocity.

	@param emote EmoteControllerType? Active emote controller.
	@param input Types.InputState Current input state.
	@param velocityMagnitude number Current speed.
	@returns nil
	@raises nil
]]
local function handleEmoteDisturbance(emote: EmoteControllerType?, input: Types.InputState, velocityMagnitude: number)
	if not emote then
		return
	end
	const isMoving = input.W or input.A or input.S or input.D or input.Space or input.Q or input.E
	if isMoving or velocityMagnitude > 1 then
		emote:HandleDisturbance()
	end
end

--[[
	@name renderStep
	@arch server

	@desc Advances all active controllers for one rendered frame.

	@param self Self SessionController instance.
	@param deltaTime number Frame delta time.
	@returns nil
	@raises nil
]]
local function renderStep(self: Self, deltaTime: number)
	const rig = self.rig
	const inputController = self.input
	const cameraController = self.camera
	const movementController = self.movement
	const poseController = self.pose
	const emoteController = self.emote
	if not rig or not inputController or not cameraController or not movementController or not poseController then
		return
	end

	const input = inputController:GetState()

	const teleportRequested, screenPos = inputController:ConsumeTeleportRequest()
	if teleportRequested and self.widget:GetClickToTeleport() and input.Ctrl then
		handleTeleportRaycast(self, screenPos)
	end

	handleEmoteDisturbance(emoteController, input, movementController.velocity.Magnitude)

	const priorCameraCFrame = cameraController.camera.CFrame
	const settings: Types.MovementSettings = {
		walkSpeed = self.widget:GetWalkSpeed(),
		jumpPower = self.widget:GetJumpPower(),
		fly = self.widget:GetFly(),
		noclip = self.widget:GetNoclip(),
		includeGravity = self.widget:GetIncludeGravity(),
		clickToTeleport = self.widget:GetClickToTeleport(),
		maxSlopeAngle = self.widget:GetMaxSlopeAngle(),
	}

	const motion = movementController:Step(deltaTime, input, priorCameraCFrame, settings)
	const cameraCFrame = cameraController:Step(deltaTime, motion.position)

	const targetRotation =
		getTargetRotation(motion, cameraCFrame, input, cameraController:ShouldFaceCamera(), self.rootRotation)
	const rotationAlpha = 1 - math.exp(-14 * math.min(deltaTime, 0.1))
	self.rootRotation = self.rootRotation:Lerp(targetRotation, rotationAlpha)
	rig.root.CFrame = CFrame.new(motion.position) * self.rootRotation

	poseController:SetState(motion.state, motion.velocity.Magnitude)
	poseController:Step(math.min(deltaTime, 0.1))

	if motion.state ~= self.lastStatus then
		self.lastStatus = motion.state
		rig.model:SetAttribute("PlaytestState", motion.state)
	end
end

--[[
	@name new
	@arch server

	@desc Constructs a dormant session coordinator.

	@param pluginInstance Plugin Studio plugin instance.
	@param widget WidgetType Widget controller instance.
	@returns Self SessionController instance.
	@raises nil
]]
function SessionController.new(pluginInstance: Plugin, widget: WidgetType): Self
	return setmetatable({
		plugin = pluginInstance,
		widget = widget,
		connections = {},
		isRendering = false,
		rig = nil,
		input = nil,
		camera = nil,
		movement = nil,
		pose = nil,
		emote = nil,
		rootRotation = CFrame.identity,
		lastStatus = "",
		teleportRaycastParams = nil,
	}, SessionController) :: any
end

--[[
	@name Start
	@arch server

	@desc Starts an edit-mode avatar playtest session.

	@param self Self SessionController instance.
	@param atCamera boolean Whether to spawn at camera or SpawnLocation.
	@returns nil
	@raises nil
]]
function SessionController.Start(self: Self, atCamera: boolean)
	self:Stop()
	const spawnpoint = if atCamera then nil else findSpawnpoint()
	if not atCamera and not spawnpoint then
		warn("Quick Playtest: No enabled SpawnLocation found in workspace.")
		return
	end

	self.widget:SetPlaying(true)
	const provisionalCFrame = if atCamera
		then getCameraStartCFrame()
		else CFrame.new((spawnpoint :: SpawnLocation).Position + Vector3.yAxis * 4)

	local success, result = pcall(function(): Rig
		return CharacterFactory.create(self.widget:GetRigType(), provisionalCFrame)
	end)
	if not success or not result then
		self.widget:SetPlaying(false)
		warn(`Quick Playtest failed to create avatar: {result}`)
		return
	end

	const rig = result :: Rig
	const startCFrame = if atCamera then provisionalCFrame else getSpawnpointCFrame(spawnpoint :: SpawnLocation, rig)
	rig.model:PivotTo(startCFrame)

	const input = InputController.new()
	const camera = CameraController.new(rig, input)
	const movement = MovementController.new(rig, startCFrame.Position)
	const pose = PoseController.new(rig)
	const emote = EmoteController.new(rig)

	self.widget:SetUserEmotes(emote:GetUserEmotes())
	emote:SetOnEmoteChanged(function(emoteName)
		self.widget:SetActiveEmoteName(emoteName)
	end)

	self.rig = rig
	self.input = input
	self.camera = camera
	self.movement = movement
	self.pose = pose
	self.emote = emote
	self.rootRotation = startCFrame.Rotation
	self.lastStatus = ""
	self.teleportRaycastParams = nil
	self.isRendering = true

	RunService:BindToRenderStep("QuickPlaytestSession", Enum.RenderPriority.Last.Value, function(deltaTime)
		renderStep(self, deltaTime)
	end)
end

--[[
	@name Stop
	@arch server

	@desc Terminates active playtest session and cleans up controllers and models.

	@param self Self SessionController instance.
	@returns nil
	@raises nil
]]
function SessionController.Stop(self: Self)
	if self.isRendering then
		RunService:UnbindFromRenderStep("QuickPlaytestSession")
		self.isRendering = false
	end
	if self.emote then
		self.emote:Destroy()
	end
	if self.pose then
		self.pose:Destroy()
	end
	if self.camera then
		self.camera:Destroy()
	end
	if self.input then
		self.input:Destroy()
	end
	if self.rig then
		self.rig.model:Destroy()
	end

	self.rig = nil
	self.input = nil
	self.camera = nil
	self.movement = nil
	self.pose = nil
	self.emote = nil
	self.widget:SetPlaying(false)
	self.widget:SetActiveEmoteName(nil)
end

--[[
	@name Bind
	@arch server

	@desc Connects widget command callbacks to session actions.

	@param self Self SessionController instance.
	@returns nil
	@raises nil
]]
function SessionController.Bind(self: Self)
	self.widget:OnSpawnpoint(function()
		self:Start(false)
	end)
	self.widget:OnSpawnCamera(function()
		self:Start(true)
	end)
	self.widget:OnStop(function()
		self:Stop()
	end)
	self.widget:OnPlayEmote(function(emoteDef)
		if self.emote then
			self.emote:PlayEmote(emoteDef)
		end
	end)
	self.widget:OnStopEmote(function()
		if self.emote then
			self.emote:StopEmote()
		end
	end)
end

--[[
	@name Destroy
	@arch server

	@desc Cleans up session and all widget bindings.

	@param self Self SessionController instance.
	@returns nil
	@raises nil
]]
function SessionController.Destroy(self: Self)
	self:Stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

export type Controller = typeof(setmetatable({} :: Self, SessionController))

return SessionController

-- checcerr.
