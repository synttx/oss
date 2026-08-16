--!strict
--!optimize 2

--[[
	@name CameraController
	@arch client

	@desc Drives orbit, smooth first-person fade, shift-lock, and obstruction-aware edit camera.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local Constants = require("./Constants")
local InputController = require("./InputController")
local Types = require("./Types")

--/ Types
type Rig = Types.Rig
type InputControllerType = InputController.Controller
type Self = {
	camera: Camera,
	rig: Rig,
	input: InputControllerType,
	yaw: number,
	pitch: number,
	zoom: number,
	shiftLock: boolean,
	currentTransparency: number,
	originalCameraType: Enum.CameraType,
	originalFieldOfView: number,
	raycastParams: RaycastParams,
}

--/ Class
local CameraController = {}
CameraController.__index = CameraController

--/ Functions

--[[
	@name new
	@arch client

	@desc Creates a camera controller around the active Studio camera.

	@param rig Rig Character rig data.
	@param input InputController Controller instance.
	@returns Self Initialized camera controller.
	@raises nil
]]
function CameraController.new(rig: Rig, input: InputControllerType): Self
	const camera = workspace.CurrentCamera :: Camera
	local pitch, yaw = camera.CFrame:ToOrientation()
	const raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { rig.model }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	const self: Self = setmetatable({
		camera = camera,
		rig = rig,
		input = input,
		yaw = math.deg(yaw),
		pitch = math.clamp(math.deg(pitch), Constants.CAMERA_PITCH_MIN, Constants.CAMERA_PITCH_MAX),
		zoom = Constants.CAMERA_ZOOM_DEFAULT,
		shiftLock = false,
		currentTransparency = 0,
		originalCameraType = camera.CameraType,
		originalFieldOfView = camera.FieldOfView,
		raycastParams = raycastParams,
	}, CameraController) :: any

	camera.CameraType = Enum.CameraType.Scriptable
	return self
end

--[[
	@name updateFirstPersonTransparency
	@arch client

	@desc Smoothly transitions local character transparency when zooming into first person.

	@param self Self CameraController instance.
	@param deltaTime number Frame delta time.
	@param firstPerson boolean Whether camera is in first-person range.
	@returns nil
	@raises nil
]]
local function updateFirstPersonTransparency(self: Self, deltaTime: number, firstPerson: boolean)
	const target = if firstPerson then 1 else 0
	const alpha = 1 - math.exp(-Constants.FIRST_PERSON_TRANSITION_SPEED * math.min(deltaTime, 0.1))
	self.currentTransparency += (target - self.currentTransparency) * alpha

	if math.abs(self.currentTransparency - target) < 0.005 then
		self.currentTransparency = target
	end

	for _, part in self.rig.visualParts do
		part.LocalTransparencyModifier = self.currentTransparency
	end
end

--[[
	@name Step
	@arch client

	@desc Updates camera rotation, zoom, obstruction, and character transparency.

	@param self Self CameraController instance.
	@param deltaTime number Frame delta time.
	@param focusPosition Vector3 World focus point.
	@returns CFrame Computed camera CFrame.
	@raises nil
]]
function CameraController.Step(self: Self, deltaTime: number, focusPosition: Vector3): CFrame
	if self.input:ConsumeShiftToggle() then
		self.shiftLock = not self.shiftLock
	end

	const zoomDelta = self.input:ConsumeZoomDelta()
	self.zoom = math.clamp(self.zoom - zoomDelta * 2, Constants.CAMERA_ZOOM_MIN, Constants.CAMERA_ZOOM_MAX)
	const firstPerson = self.zoom <= 0.5
	self.input:SetCapture(firstPerson or self.shiftLock)

	const lookDelta = self.input:ConsumeLookDelta()
	self.yaw -= lookDelta.X * Constants.CAMERA_SENSITIVITY
	self.pitch = math.clamp(
		self.pitch - lookDelta.Y * Constants.CAMERA_SENSITIVITY,
		Constants.CAMERA_PITCH_MIN,
		Constants.CAMERA_PITCH_MAX
	)

	const rotation = CFrame.fromOrientation(math.rad(self.pitch), math.rad(self.yaw), 0)
	const lateralOffset = if self.shiftLock and not firstPerson then rotation.RightVector * 1.75 else Vector3.zero
	const focus = focusPosition + Vector3.new(0, 1.5, 0) + lateralOffset
	const desiredPosition = focus + rotation:VectorToWorldSpace(Vector3.new(0, 0, self.zoom))
	const obstruction = workspace:Raycast(focus, desiredPosition - focus, self.raycastParams)
	local cameraPosition = desiredPosition
	if obstruction then
		cameraPosition = focus + (desiredPosition - focus).Unit * math.max(0.1, obstruction.Distance - 0.2)
	end

	self.camera.CFrame = CFrame.new(cameraPosition) * rotation
	self.camera.Focus = CFrame.new(focus)
	updateFirstPersonTransparency(self, deltaTime, firstPerson)
	return self.camera.CFrame
end

--[[
	@name ShouldFaceCamera
	@arch client

	@desc Returns whether character yaw should align to camera facing direction.

	@param self Self CameraController instance.
	@returns boolean Facing flag.
	@raises nil
]]
function CameraController.ShouldFaceCamera(self: Self): boolean
	return self.shiftLock or self.zoom <= 0.5
end

--[[
	@name Destroy
	@arch client

	@desc Restores original camera settings and resets character transparency modifiers.

	@param self Self CameraController instance.
	@returns nil
	@raises nil
]]
function CameraController.Destroy(self: Self)
	for _, part in self.rig.visualParts do
		part.LocalTransparencyModifier = 0
	end
	self.camera.CameraType = self.originalCameraType
	self.camera.FieldOfView = self.originalFieldOfView
end

export type Controller = typeof(setmetatable({} :: Self, CameraController))

return CameraController

-- checcerr.
