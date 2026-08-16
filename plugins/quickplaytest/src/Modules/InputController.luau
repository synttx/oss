--!strict
--!optimize 2

--[[
	@name InputController
	@arch client

	@desc Captures keyboard and mouse input for movement, camera, and click-to-teleport actions.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local UserInputService = game:GetService("UserInputService")

local Types = require("./Types")

--/ Types
type InputState = Types.InputState
type Self = {
	state: InputState,
	connections: { RBXScriptConnection },
	lookDelta: Vector2,
	zoomDelta: number,
	shiftToggleRequested: boolean,
	teleportRequested: boolean,
	teleportScreenPosition: Vector2,
	captureRequested: boolean,
	originalMouseBehavior: Enum.MouseBehavior,
	originalMouseIconEnabled: boolean,
}

--/ Class
local InputController = {}
InputController.__index = InputController

--/ Functions

--[[
	@name setKey
	@arch client

	@desc Updates key state in InputState table without dynamic indexing.

	@param state InputState Input state.
	@param keyCode Enum.KeyCode Key code.
	@param enabled boolean State.
	@returns nil
	@raises nil
]]
local function setKey(state: InputState, keyCode: Enum.KeyCode, enabled: boolean)
	if keyCode == Enum.KeyCode.W then
		state.W = enabled
	elseif keyCode == Enum.KeyCode.A then
		state.A = enabled
	elseif keyCode == Enum.KeyCode.S then
		state.S = enabled
	elseif keyCode == Enum.KeyCode.D then
		state.D = enabled
	elseif keyCode == Enum.KeyCode.Space then
		state.Space = enabled
	elseif keyCode == Enum.KeyCode.Q then
		state.Q = enabled
	elseif keyCode == Enum.KeyCode.E then
		state.E = enabled
	elseif keyCode == Enum.KeyCode.LeftControl or keyCode == Enum.KeyCode.RightControl then
		state.Ctrl = enabled
	end
end

--[[
	@name new
	@arch client

	@desc Constructs and connects Studio input listeners.

	@returns Self Initialized input controller.
	@raises nil
]]
function InputController.new(): Self
	local self: Self = setmetatable({
		state = {
			W = false,
			A = false,
			S = false,
			D = false,
			Space = false,
			Q = false,
			E = false,
			Ctrl = false,
			RMB = false,
		},
		connections = {},
		lookDelta = Vector2.zero,
		zoomDelta = 0,
		shiftToggleRequested = false,
		teleportRequested = false,
		teleportScreenPosition = Vector2.zero,
		captureRequested = false,
		originalMouseBehavior = UserInputService.MouseBehavior,
		originalMouseIconEnabled = UserInputService.MouseIconEnabled,
	}, InputController) :: any

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.state.RMB = true
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if self.state.Ctrl then
					self.teleportRequested = true
					self.teleportScreenPosition = Vector2.new(input.Position.X, input.Position.Y)
					return
				end
			end

			if gameProcessed then
				return
			end

			if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
				self.shiftToggleRequested = true
				return
			end

			setKey(self.state, input.KeyCode, true)
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.state.RMB = false
				return
			end
			setKey(self.state, input.KeyCode, false)
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and self.captureRequested then
				self.lookDelta += Vector2.new(input.Delta.X, input.Delta.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				self.zoomDelta += input.Position.Z
			end
		end)
	)

	return self
end

--[[
	@name GetState
	@arch client

	@desc Returns current keyboard and mouse state table.

	@param self Self InputController instance.
	@returns InputState State table.
	@raises nil
]]
function InputController.GetState(self: Self): InputState
	return self.state
end

--[[
	@name ConsumeLookDelta
	@arch client

	@desc Returns and clears accumulated mouse delta.

	@param self Self InputController instance.
	@returns Vector2 Accumulated mouse delta.
	@raises nil
]]
function InputController.ConsumeLookDelta(self: Self): Vector2
	const delta = self.lookDelta
	self.lookDelta = Vector2.zero
	return delta
end

--[[
	@name ConsumeZoomDelta
	@arch client

	@desc Returns and clears accumulated zoom wheel delta.

	@param self Self InputController instance.
	@returns number Accumulated zoom delta.
	@raises nil
]]
function InputController.ConsumeZoomDelta(self: Self): number
	const delta = self.zoomDelta
	self.zoomDelta = 0
	return delta
end

--[[
	@name ConsumeShiftToggle
	@arch client

	@desc Returns and clears pending shift lock toggle request.

	@param self Self InputController instance.
	@returns boolean Toggle requested flag.
	@raises nil
]]
function InputController.ConsumeShiftToggle(self: Self): boolean
	const requested = self.shiftToggleRequested
	self.shiftToggleRequested = false
	return requested
end

--[[
	@name ConsumeTeleportRequest
	@arch client

	@desc Returns and clears pending Ctrl+Click teleport request with screen coordinates.

	@param self Self InputController instance.
	@returns (boolean, Vector2) Teleport requested flag and screen point.
	@raises nil
]]
function InputController.ConsumeTeleportRequest(self: Self): (boolean, Vector2)
	const requested = self.teleportRequested
	const position = self.teleportScreenPosition
	self.teleportRequested = false
	return requested, position
end

--[[
	@name SetCapture
	@arch client

	@desc Updates mouse lock center behavior and visibility.

	@param self Self InputController instance.
	@param forced boolean Whether mouse lock is forced by camera mode.
	@returns nil
	@raises nil
]]
function InputController.SetCapture(self: Self, forced: boolean)
	self.captureRequested = forced or self.state.RMB
	UserInputService.MouseBehavior = if self.captureRequested
		then Enum.MouseBehavior.LockCenter
		else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not self.captureRequested
end

--[[
	@name Destroy
	@arch client

	@desc Disconnects input event connections and restores mouse settings.

	@param self Self InputController instance.
	@returns nil
	@raises nil
]]
function InputController.Destroy(self: Self)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	UserInputService.MouseBehavior = self.originalMouseBehavior
	UserInputService.MouseIconEnabled = self.originalMouseIconEnabled
end

export type Controller = typeof(setmetatable({} :: Self, InputController))

return InputController

-- checcerr.
