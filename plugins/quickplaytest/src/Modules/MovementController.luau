--!strict
--!optimize 2

--[[
	@name MovementController
	@arch server

	@desc Kinematic movement controller with responsive Roblox-style physics:
	      - Zero floor icyness & zero air momentum (instant direction response)
	      - Continuous spacebar hopping
	      - Multi-plane vertical wall slide (no wall sticking or ceiling climbing)
	      - Ground level alignment
	      - Seat cooldown protection
	      - Floor-blocked ladder/truss descent

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local Config = require("./Config")
local Constants = require("./Constants")
local MathUtils = require("./MathUtils")
local Types = require("./Types")

--/ Types
type InputState = Types.InputState
type MovementSettings = Types.MovementSettings
type MotionResult = Types.MotionResult
type Rig = Types.Rig
type SweepHit = {
	fraction: number,
	endPos: Vector3,
	normal: Vector3,
	startSolid: boolean,
	allSolid: boolean,
	planeKey: string,
	instance: Instance?,
	material: Enum.Material?,
	distance: number,
}
type GroundHit = {
	grounded: boolean,
	normal: Vector3,
	position: Vector3,
	instance: Instance?,
	material: Enum.Material?,
}
type Self = {
	rig: Rig,
	position: Vector3,
	velocity: Vector3,
	moveDirection: Vector3,
	state: string,
	grounded: boolean,
	swimming: boolean,
	isClimbing: boolean,
	climbCooldown: number,
	seat: BasePart?,
	seatCooldown: number,
	accumulator: number,
	waterClock: number,
	seatClock: number,
	climbClock: number,
	nearTruss: boolean,
	trussPart: BasePart?,
	jumpWasDown: boolean,
	lastFly: boolean,
	raycastParams: RaycastParams,
	overlapParams: OverlapParams,
}

--/ Constants
const MAX_COLLISION_PLANES = 4
const SKIN_THICKNESS = 0.035
const GROUND_PROBE_UP = 0.4
const GROUND_PROBE_DOWN = 0.5
const SEAT_COOLDOWN_TIME = 1.2
const PUSH_OUT_DISTANCES = { 0.05, 0.1, 0.25, 0.5 }
const DEPENETRATE_DIRECTIONS = {
	Vector3.yAxis,
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	-Vector3.yAxis,
}
const FOOT_SAMPLES = {
	Vector3.zero,
	Vector3.new(0.4, 0, 0.4),
	Vector3.new(-0.4, 0, 0.4),
	Vector3.new(0.4, 0, -0.4),
	Vector3.new(-0.4, 0, -0.4),
}

--/ Class
local MovementController = {}
MovementController.__index = MovementController

--/ Functions

--[[
	@name quantizePlane
	@arch server

	@desc Creates a hash key for a collision plane to detect repeating impacts in one frame.

	@param normal Vector3 Normal vector.
	@param position Vector3 Position on plane.
	@returns string Quantized key.
	@raises nil
]]
local function quantizePlane(normal: Vector3, position: Vector3): string
	const nx = math.floor(normal.X * 100 + 0.5)
	const ny = math.floor(normal.Y * 100 + 0.5)
	const nz = math.floor(normal.Z * 100 + 0.5)
	const d = math.floor(normal:Dot(position) * 10 + 0.5)
	return `{nx}_{ny}_{nz}_{d}`
end

--[[
	@name sweep
	@arch server

	@desc Performs a swept boxcast from startPos to endPos, respecting collision skin and surface planes.

	@param startPos Vector3 Start avatar world position.
	@param endPos Vector3 Desired end avatar world position.
	@param colliderSize Vector3 Bounding collider size.
	@param centerOffset number Offset from foot to collider center.
	@param raycastParams RaycastParams Exclusion filter and collision settings.
	@returns SweepHit Detailed sweep results.
	@raises nil
]]
local function sweep(
	startPos: Vector3,
	endPos: Vector3,
	colliderSize: Vector3,
	centerOffset: number,
	raycastParams: RaycastParams
): SweepHit
	const displacement = endPos - startPos
	const distance = displacement.Magnitude

	if distance < 0.0001 then
		return {
			fraction = 1,
			endPos = startPos,
			normal = Vector3.yAxis,
			startSolid = false,
			allSolid = false,
			planeKey = "none",
			instance = nil,
			material = nil,
			distance = 0,
		}
	end

	const reducedSize = Vector3.new(
		math.max(0.1, colliderSize.X - (SKIN_THICKNESS * 2)),
		math.max(0.1, colliderSize.Y - (SKIN_THICKNESS * 2)),
		math.max(0.1, colliderSize.Z - (SKIN_THICKNESS * 2))
	)

	const startCenter = startPos + Vector3.yAxis * centerOffset
	const castCFrame = CFrame.new(startCenter)
	const hit = workspace:Blockcast(castCFrame, reducedSize, displacement, raycastParams)

	if not hit then
		return {
			fraction = 1,
			endPos = endPos,
			normal = Vector3.yAxis,
			startSolid = false,
			allSolid = false,
			planeKey = "none",
			instance = nil,
			material = nil,
			distance = distance,
		}
	end

	const hitDist = hit.Distance
	if hitDist <= 0.0001 then
		return {
			fraction = 0,
			endPos = startPos,
			normal = hit.Normal,
			startSolid = true,
			allSolid = true,
			planeKey = quantizePlane(hit.Normal, hit.Position),
			instance = hit.Instance,
			material = hit.Material,
			distance = 0,
		}
	end

	const safeDistance = math.max(0, hitDist - SKIN_THICKNESS)
	const fraction = math.clamp(safeDistance / distance, 0, 1)
	const endPosition = startPos + displacement.Unit * safeDistance

	return {
		fraction = fraction,
		endPos = endPosition,
		normal = hit.Normal,
		startSolid = false,
		allSolid = false,
		planeKey = quantizePlane(hit.Normal, hit.Position),
		instance = hit.Instance,
		material = hit.Material,
		distance = safeDistance,
	}
end

--[[
	@name depenetrate
	@arch server

	@desc Detects if collider is embedded inside solids/terrain and nudges it into closest open space.

	@param pos Vector3 Current avatar foot position.
	@param colliderSize Vector3 Collider dimensions.
	@param centerOffset number Foot-to-center offset.
	@param overlapParams OverlapParams Spatial overlap query parameters.
	@returns Vector3 Adjusted position free of initial penetration.
	@raises nil
]]
local function depenetrate(
	pos: Vector3,
	colliderSize: Vector3,
	centerOffset: number,
	overlapParams: OverlapParams
): Vector3
	const center = pos + Vector3.yAxis * centerOffset
	const intersectingParts = workspace:GetPartBoundsInBox(CFrame.new(center), colliderSize * 0.9, overlapParams)
	if #intersectingParts == 0 then
		return pos
	end

	for _, dist in PUSH_OUT_DISTANCES do
		for _, dir in DEPENETRATE_DIRECTIONS do
			const probePos = center + dir * dist
			const parts = workspace:GetPartBoundsInBox(CFrame.new(probePos), colliderSize * 0.9, overlapParams)
			if #parts == 0 then
				return pos + dir * dist
			end
		end
	end

	return pos
end

--[[
	@name checkGround
	@arch server

	@desc Robust ground probe checking whether avatar feet are supported by walkable surface.

	@param pos Vector3 Current avatar root position.
	@param groundOffset number Distance from root part to bottom of feet.
	@param maxSlopeAngle number Max walkable slope angle in degrees.
	@param raycastParams RaycastParams Raycast parameters.
	@returns GroundHit Detailed ground detection status.
	@raises nil
]]
local function checkGround(
	pos: Vector3,
	groundOffset: number,
	maxSlopeAngle: number,
	raycastParams: RaycastParams
): GroundHit
	const minNormalY = math.cos(math.rad(maxSlopeAngle))
	const footY = pos.Y - groundOffset

	local bestHit: RaycastResult? = nil
	local highestFloorY = -math.huge

	for _, sample in FOOT_SAMPLES do
		const rayOrigin = Vector3.new(pos.X + sample.X, footY + GROUND_PROBE_UP, pos.Z + sample.Z)
		const rayDir = Vector3.yAxis * -(GROUND_PROBE_UP + GROUND_PROBE_DOWN)
		const hit = workspace:Raycast(rayOrigin, rayDir, raycastParams)

		if hit and hit.Normal.Y >= minNormalY then
			const dist = footY - hit.Position.Y
			if dist >= -0.15 and dist <= GROUND_PROBE_DOWN and hit.Position.Y > highestFloorY then
				highestFloorY = hit.Position.Y
				bestHit = hit
			end
		end
	end

	if bestHit then
		return {
			grounded = true,
			normal = bestHit.Normal,
			position = Vector3.new(pos.X, highestFloorY + groundOffset, pos.Z),
			instance = bestHit.Instance,
			material = bestHit.Material,
		}
	end

	return {
		grounded = false,
		normal = Vector3.yAxis,
		position = pos,
		instance = nil,
		material = nil,
	}
end

--[[
	@name getGroundDirection
	@arch server

	@desc Converts digital input into camera-relative horizontal movement direction.

	@param input InputState User keyboard input.
	@param cameraCFrame CFrame Camera orientation CFrame.
	@returns Vector3 Normalized horizontal wish direction.
	@raises nil
]]
local function getGroundDirection(input: InputState, cameraCFrame: CFrame): Vector3
	local forward = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
	local right = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
	forward = if forward.Magnitude > 0.001 then forward.Unit else Vector3.new(0, 0, -1)
	right = if right.Magnitude > 0.001 then right.Unit else Vector3.xAxis
	const x = (if input.D then 1 else 0) - (if input.A then 1 else 0)
	const z = (if input.W then 1 else 0) - (if input.S then 1 else 0)
	const direction = right * x + forward * z
	return if direction.Magnitude > 1 then direction.Unit else direction
end

--[[
	@name getFlyDirection
	@arch server

	@desc Converts digital input into full 3D camera-relative flight vector.

	@param input InputState User keyboard input.
	@param cameraCFrame CFrame Camera orientation CFrame.
	@returns Vector3 Normalized 3D flight direction.
	@raises nil
]]
local function getFlyDirection(input: InputState, cameraCFrame: CFrame): Vector3
	const x = (if input.D then 1 else 0) - (if input.A then 1 else 0)
	const z = (if input.W then 1 else 0) - (if input.S then 1 else 0)
	const y = (if input.E then 1 else 0) - (if input.Q then 1 else 0)
	const direction = cameraCFrame.RightVector * x + cameraCFrame.LookVector * z + Vector3.yAxis * y
	return if direction.Magnitude > 1 then direction.Unit else direction
end

--[[
	@name new
	@arch server

	@desc Constructs a new kinematic movement controller for an avatar rig.

	@param rig Rig Avatar rig and collider properties.
	@param startPosition Vector3 Initial world position.
	@returns Self Initialized controller instance.
	@raises nil
]]
function MovementController.new(rig: Rig, startPosition: Vector3): Self
	const raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { rig.model }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	const overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { rig.model }
	overlapParams.RespectCanCollide = false
	overlapParams.MaxParts = 24

	return setmetatable({
		rig = rig,
		position = startPosition,
		velocity = Vector3.zero,
		moveDirection = Vector3.zero,
		state = "idle",
		grounded = false,
		swimming = false,
		isClimbing = false,
		climbCooldown = 0,
		seat = nil,
		seatCooldown = 0,
		accumulator = 0,
		waterClock = Constants.WATER_SCAN_INTERVAL,
		seatClock = 0,
		climbClock = Constants.CLIMB_SCAN_INTERVAL,
		nearTruss = false,
		trussPart = nil,
		jumpWasDown = false,
		lastFly = false,
		raycastParams = raycastParams,
		overlapParams = overlapParams,
	}, MovementController) :: any
end

--[[
	@name projectVelocity
	@arch server

	@desc Projects motion along collision planes, preventing wall sticking by preserving vertical gravity.

	@param self Self Controller state.
	@param startPos Vector3 Initial world position.
	@param startVel Vector3 Starting velocity.
	@param deltaTime number Step duration.
	@returns (Vector3, Vector3, boolean) Final position, final velocity, and whether any solid was hit.
	@raises nil
]]
local function projectVelocity(
	self: Self,
	startPos: Vector3,
	startVel: Vector3,
	deltaTime: number
): (Vector3, Vector3, boolean)
	local currentPos = startPos
	local currentVel = startVel
	local timeLeft = deltaTime
	local hitSomething = false
	local visitedPlanes: { [string]: boolean } = {}

	for _ = 1, MAX_COLLISION_PLANES do
		if currentVel.Magnitude < 0.001 or timeLeft <= 0.00001 then
			break
		end

		const displacement = currentVel * timeLeft
		const hit = sweep(
			currentPos,
			currentPos + displacement,
			self.rig.colliderSize,
			self.rig.centerOffset,
			self.raycastParams
		)

		if hit.fraction > 0 then
			currentPos = hit.endPos
		end

		if hit.fraction >= 1 then
			break
		end

		hitSomething = true

		if hit.allSolid then
			currentVel = Vector3.zero
			break
		end

		timeLeft -= (timeLeft * hit.fraction)

		if hit.normal.Y < 0.7 then
			-- Vertical wall: deflect only horizontal velocity so falling gravity isn't cancelled
			const flatInput = Vector3.new(currentVel.X, 0, currentVel.Z)
			const flatNormal = Vector3.new(hit.normal.X, 0, hit.normal.Z)
			const normUnit = if flatNormal.Magnitude > 0.001 then flatNormal.Unit else Vector3.xAxis
			const deflectedHoriz = MathUtils.clipVelocity(flatInput, normUnit, 1.001)
			currentVel = Vector3.new(deflectedHoriz.X, currentVel.Y, deflectedHoriz.Z)
		else
			-- Floor / ceiling surface
			if not visitedPlanes[hit.planeKey] then
				visitedPlanes[hit.planeKey] = true
				currentVel = MathUtils.clipVelocity(currentVel, hit.normal, 1.001)
			else
				currentPos += hit.normal * 0.005
				currentVel = MathUtils.clipVelocity(currentVel, hit.normal, 1.001) + hit.normal * 0.05
				break
			end
		end
	end

	return currentPos, currentVel, hitSomething
end

--[[
	@name doStepUp
	@arch server

	@desc Performs stair & curb traversal: sweeps upwards, projects forward over step, traces down.

	@param self Self Controller state.
	@param pos Vector3 Current world position.
	@param vel Vector3 Current velocity.
	@param deltaTime number Step duration.
	@param maxSlopeAngle number Maximum walkable slope angle.
	@returns { pos: Vector3, vel: Vector3 }? Step result if successful.
	@raises nil
]]
local function doStepUp(
	self: Self,
	pos: Vector3,
	vel: Vector3,
	deltaTime: number,
	maxSlopeAngle: number
): { pos: Vector3, vel: Vector3 }?
	const flatVel = MathUtils.flatVec(vel)
	if flatVel.Magnitude < 0.01 then
		return nil
	end

	const config = Config.get()
	const stepHeight = config.STEP_HEIGHT or Constants.STEP_HEIGHT
	const stepVec = Vector3.new(0, stepHeight, 0)

	const headHit = sweep(pos, pos + stepVec, self.rig.colliderSize, self.rig.centerOffset, self.raycastParams)
	if headHit.startSolid then
		return nil
	end

	const stepUpNewPos, stepUpNewVel, _ = projectVelocity(self, headHit.endPos, flatVel, deltaTime)

	const downHit =
		sweep(stepUpNewPos, stepUpNewPos - stepVec, self.rig.colliderSize, self.rig.centerOffset, self.raycastParams)
	if downHit.startSolid then
		return nil
	end

	const candidatePos = downHit.endPos
	const groundCheck = checkGround(candidatePos, self.rig.groundOffset, maxSlopeAngle, self.raycastParams)
	if not groundCheck.grounded then
		return nil
	end

	const stepDelta = candidatePos.Y - pos.Y
	if stepDelta <= 0.01 or stepDelta > stepHeight then
		return nil
	end

	return {
		pos = candidatePos,
		vel = stepUpNewVel,
	}
end

--[[
	@name doStepDown
	@arch server

	@desc Keeps the avatar glued to stairs and descending terrain without entering falling state.

	@param self Self Controller state.
	@param pos Vector3 Current world position.
	@param maxSlopeAngle number Max walkable slope angle.
	@returns Vector3? Step down position if snapped.
	@raises nil
]]
local function doStepDown(self: Self, pos: Vector3, maxSlopeAngle: number): Vector3?
	const config = Config.get()
	const stepHeight = config.STEP_HEIGHT or Constants.STEP_HEIGHT
	const groundCheck =
		checkGround(pos - Vector3.new(0, stepHeight * 0.5, 0), self.rig.groundOffset, maxSlopeAngle, self.raycastParams)

	if groundCheck.grounded then
		const delta = pos.Y - groundCheck.position.Y
		if delta > 0.01 and delta <= stepHeight then
			return groundCheck.position
		end
	end

	return nil
end

--[[
	@name sweepNoclipFloor
	@arch server

	@desc Finds highest walkable floor crossed during floor-safe noclip mode.

	@param self Self Controller state.
	@param oldPosition Vector3 Previous world position.
	@param newPosition Vector3 New target position.
	@param maxSlopeAngle number Max slope angle.
	@returns (Vector3, boolean) Clamped position and whether grounded.
	@raises nil
]]
local function sweepNoclipFloor(
	self: Self,
	oldPosition: Vector3,
	newPosition: Vector3,
	maxSlopeAngle: number
): (Vector3, boolean)
	const minNormalY = math.cos(math.rad(maxSlopeAngle))
	const radius = self.rig.colliderSize.X / 2
	local highestFloor: number? = nil
	const startFootY = oldPosition.Y - self.rig.groundOffset + Constants.GROUND_SNAP
	const endFootY = newPosition.Y - self.rig.groundOffset - SKIN_THICKNESS
	const distance = endFootY - startFootY
	for _, sample in FOOT_SAMPLES do
		const offset = Vector3.new(sample.X * radius, 0, sample.Z * radius)
		const origin = Vector3.new(newPosition.X, startFootY, newPosition.Z) + offset
		const hit = workspace:Raycast(origin, Vector3.yAxis * distance, self.raycastParams)
		if hit and hit.Normal.Y >= minNormalY and (not highestFloor or hit.Position.Y > highestFloor) then
			highestFloor = hit.Position.Y
		end
	end
	if highestFloor then
		return Vector3.new(newPosition.X, highestFloor + self.rig.groundOffset, newPosition.Z), true
	end
	return newPosition, false
end

--[[
	@name isInWater
	@arch server

	@desc Samples occupied water terrain voxels around avatar collider.

	@param self Self Controller state.
	@returns boolean Whether avatar is submerged in water.
	@raises nil
]]
local function isInWater(self: Self): boolean
	const halfSize = self.rig.colliderSize / 2
	const center = self.position + Vector3.yAxis * self.rig.centerOffset
	const region = Region3.new(center - halfSize, center + halfSize):ExpandToGrid(4)
	const terrain = workspace:FindFirstChildOfClass("Terrain") :: Terrain?
	if not terrain then
		return false
	end
	const materials, occupancies = terrain:ReadVoxels(region, 4)
	const size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] == Enum.Material.Water and occupancies[x][y][z] > 0.05 then
					return true
				end
			end
		end
	end
	return false
end

--[[
	@name findSeat
	@arch server

	@desc Scans for unoccupied seat parts.

	@param self Self Controller state.
	@returns BasePart? Seat instance if found.
	@raises nil
]]
local function findSeat(self: Self): BasePart?
	const boxCFrame = CFrame.new(self.position - Vector3.yAxis * (self.rig.groundOffset * 0.35))
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(3, 3, 3), self.overlapParams) do
		if part:IsA("Seat") or part:IsA("VehicleSeat") then
			if part.Occupant == nil then
				return part
			end
		end
	end
	return nil
end

--[[
	@name scanTruss
	@arch server

	@desc Detects climbable trusses or ladders intersecting avatar collider.

	@param self Self Controller state.
	@returns (boolean, BasePart?) Whether truss is within reach and the part.
	@raises nil
]]
local function scanTruss(self: Self): (boolean, BasePart?)
	const boxCFrame = CFrame.new(self.position + Vector3.yAxis * self.rig.centerOffset)
	for _, part in
		workspace:GetPartBoundsInBox(boxCFrame, self.rig.colliderSize + Vector3.new(0.6, 0, 0.6), self.overlapParams)
	do
		if part:IsA("TrussPart") or part:GetAttribute("Climbable") == true then
			return true, part
		end
	end
	return false, nil
end

--[[
	@name getSeatPosition
	@arch server

	@desc Positions avatar relative to seat transform.

	@param self Self Controller state.
	@param seat BasePart Seat part.
	@returns Vector3 Seated world position.
	@raises nil
]]
local function getSeatPosition(self: Self, seat: BasePart): Vector3
	return seat.CFrame:PointToWorldSpace(Vector3.new(0, seat.Size.Y / 2 + self.rig.root.Size.Y / 2, 0))
end

--[[
	@name stepFly
	@arch server

	@desc Integrates free 3D flight with collision.

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param input InputState Input state.
	@param cameraCFrame CFrame Camera CFrame.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function stepFly(
	self: Self,
	deltaTime: number,
	input: InputState,
	cameraCFrame: CFrame,
	settings: MovementSettings
)
	const direction = getFlyDirection(input, cameraCFrame)
	self.velocity = direction * (settings.walkSpeed * Constants.FLY_SPEED_MULTIPLIER)

	if settings.noclip then
		self.position += self.velocity * deltaTime
	else
		const newPos, newVel, _ = projectVelocity(self, self.position, self.velocity, deltaTime)
		self.position = newPos
		self.velocity = newVel
	end

	self.moveDirection = direction
	self.grounded = false
	self.state = "fly"
end

--[[
	@name stepSwim
	@arch server

	@desc Integrates 3D buoyant swimming physics with solid boundaries.

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param input InputState Input state.
	@param cameraCFrame CFrame Camera CFrame.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function stepSwim(
	self: Self,
	deltaTime: number,
	input: InputState,
	cameraCFrame: CFrame,
	settings: MovementSettings
)
	const horizontal = getGroundDirection(input, cameraCFrame)
	const vertical = (if input.Space or input.E then 1 else 0) - (if input.Q then 1 else 0)
	local direction = horizontal + Vector3.yAxis * vertical
	direction = if direction.Magnitude > 1 then direction.Unit else direction

	self.velocity = direction * (settings.walkSpeed * Constants.SWIM_SPEED_MULTIPLIER)

	if direction.Magnitude < 0.01 then
		self.velocity += Vector3.yAxis * math.min(workspace.Gravity * 0.035 * deltaTime, 0.5)
	end

	const newPos, newVel, _ = projectVelocity(self, self.position, self.velocity, deltaTime)
	self.position = newPos
	self.velocity = newVel
	self.moveDirection = direction
	self.grounded = false
	self.state = if direction.Magnitude > 0.05 then "swim" else "swimidle"
end

--[[
	@name stepClimb
	@arch server

	@desc Integrates sticky ladder and truss climbing with ground floor barrier.

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param input InputState User keyboard input.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function stepClimb(self: Self, deltaTime: number, input: InputState, settings: MovementSettings)
	const verticalInput = (if input.W then 1 else 0) - (if input.S then 1 else 0)
	const horizontalInput = (if input.D then 1 else 0) - (if input.A then 1 else 0)
	const climbSpeed = settings.walkSpeed * 0.75

	if input.Space and not self.jumpWasDown then
		self.isClimbing = false
		self.climbCooldown = 0.35
		self.velocity = Vector3.new(0, settings.jumpPower, 0)
		self.grounded = false
		self.state = "jump"
		return
	end

	if verticalInput < 0 then
		const footOrigin = self.position - Vector3.yAxis * (self.rig.groundOffset - 0.1)
		const floorHit = workspace:Raycast(footOrigin, Vector3.yAxis * -0.4, self.raycastParams)
		if floorHit and floorHit.Normal.Y >= 0.5 then
			self.isClimbing = false
			self.position = Vector3.new(self.position.X, floorHit.Position.Y + self.rig.groundOffset, self.position.Z)
			self.velocity = Vector3.zero
			self.grounded = true
			self.state = "idle"
			return
		end
	end

	const climbVelocity = Vector3.new(horizontalInput * climbSpeed * 0.3, verticalInput * climbSpeed, 0)
	self.velocity = climbVelocity
	self.position += climbVelocity * deltaTime
	self.grounded = false
	self.state = "climb"
end

--[[
	@name stepGround
	@arch server

	@desc Direct, zero-momentum Roblox ground and air locomotion, continuous jumping, and surface snapping.

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param input InputState Input state.
	@param cameraCFrame CFrame Camera CFrame.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function stepGround(
	self: Self,
	deltaTime: number,
	input: InputState,
	cameraCFrame: CFrame,
	settings: MovementSettings
)
	self.position = depenetrate(self.position, self.rig.colliderSize, self.rig.centerOffset, self.overlapParams)

	const initialGround = checkGround(self.position, self.rig.groundOffset, settings.maxSlopeAngle, self.raycastParams)
	const startedOnGround = initialGround.grounded

	const wantsJump = input.Space and startedOnGround
	const direction = getGroundDirection(input, cameraCFrame)
	self.moveDirection = direction

	local horizontalVel: Vector3
	if startedOnGround then
		-- On ground: instant response on key press, instant stop on release
		horizontalVel = direction * settings.walkSpeed
	else
		-- In air: full air steering when holding keys, smooth quick momentum decay on release
		const currentFlat = MathUtils.flatVec(self.velocity)
		if direction.Magnitude > 0.01 then
			const targetVel = direction * settings.walkSpeed
			const maxChange = 55 * deltaTime * math.max(1, settings.walkSpeed / 16)
			const diff = targetVel - currentFlat
			if diff.Magnitude <= maxChange then
				horizontalVel = targetVel
			else
				horizontalVel = currentFlat + diff.Unit * maxChange
			end
		else
			const decayed = currentFlat * math.exp(-7 * deltaTime)
			horizontalVel = if decayed.Magnitude < 0.15 then Vector3.zero else decayed
		end
	end

	if wantsJump then
		self.velocity = Vector3.new(horizontalVel.X, settings.jumpPower, horizontalVel.Z)
		self.grounded = false
		self.state = "jump"
	else
		const gravity = if settings.includeGravity then workspace.Gravity else 0
		const currentY = if startedOnGround then 0 else self.velocity.Y - gravity * deltaTime
		self.velocity = Vector3.new(horizontalVel.X, currentY, horizontalVel.Z)
	end

	if settings.noclip then
		const desiredPos = self.position + self.velocity * deltaTime
		if desiredPos.Y < self.position.Y then
			self.position, self.grounded = sweepNoclipFloor(self, self.position, desiredPos, settings.maxSlopeAngle)
		else
			self.position = desiredPos
			self.grounded = false
		end
	else
		const walkNewPos, walkNewVel, hitSomething = projectVelocity(self, self.position, self.velocity, deltaTime)

		local stepUpResult: { pos: Vector3, vel: Vector3 }? = nil
		if startedOnGround and hitSomething and not wantsJump and self.velocity.Y <= 0.01 then
			stepUpResult = doStepUp(self, self.position, self.velocity, deltaTime, settings.maxSlopeAngle)
		end

		if stepUpResult then
			self.position = stepUpResult.pos
			self.velocity = stepUpResult.vel
		else
			self.position = walkNewPos
			self.velocity = walkNewVel
		end

		if startedOnGround and not stepUpResult and not wantsJump and self.velocity.Y <= 0.01 then
			const stepDownPos = doStepDown(self, self.position, settings.maxSlopeAngle)
			if stepDownPos then
				self.position = stepDownPos
			end
		end

		if not wantsJump and self.velocity.Y <= 0.05 then
			const finalGround =
				checkGround(self.position, self.rig.groundOffset, settings.maxSlopeAngle, self.raycastParams)
			self.grounded = finalGround.grounded
			if self.grounded then
				self.position = Vector3.new(self.position.X, finalGround.position.Y, self.position.Z)
				if self.velocity.Y < 0 then
					self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
				end
			end
		else
			self.grounded = false
		end
	end

	if self.grounded then
		self.state = if direction.Magnitude > 0.05 then "walk" else "idle"
	else
		self.state = if self.velocity.Y > 0 then "jump" else "fall"
	end
end

--[[
	@name updateEnvironment
	@arch server

	@desc Periodically updates environmental tags (water, seats, trusses).

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function updateEnvironment(self: Self, deltaTime: number, settings: MovementSettings)
	if self.climbCooldown > 0 then
		self.climbCooldown = math.max(0, self.climbCooldown - deltaTime)
	end
	if self.seatCooldown > 0 then
		self.seatCooldown = math.max(0, self.seatCooldown - deltaTime)
	end

	self.waterClock += deltaTime
	if self.waterClock >= Constants.WATER_SCAN_INTERVAL then
		self.waterClock = 0
		self.swimming = isInWater(self)
	end

	self.seatClock += deltaTime
	if
		self.seatClock >= Constants.SEAT_SCAN_INTERVAL
		and self.grounded
		and not settings.fly
		and not self.swimming
		and self.seatCooldown <= 0
	then
		self.seatClock = 0
		if not self.seat then
			self.seat = findSeat(self)
		end
	end

	self.climbClock += deltaTime
	if self.climbClock >= Constants.CLIMB_SCAN_INTERVAL then
		self.climbClock = 0
		const near, part = scanTruss(self)
		self.nearTruss = near
		self.trussPart = part
	end
end

--[[
	@name updateSeatMotion
	@arch server

	@desc Manages seat attachment or detachment with jump escape.

	@param self Self Controller state.
	@param jumpStarted boolean Whether jump started.
	@param settings MovementSettings Active settings.
	@returns boolean True if character remains seated.
	@raises nil
]]
local function updateSeatMotion(self: Self, jumpStarted: boolean, settings: MovementSettings): boolean
	if self.seat and (not self.seat.Parent or jumpStarted or settings.fly) then
		self.seat = nil
		self.seatCooldown = SEAT_COOLDOWN_TIME
		self.velocity = if jumpStarted then Vector3.yAxis * settings.jumpPower else Vector3.zero
		self.grounded = not jumpStarted
		if jumpStarted then
			self.state = "jump"
		end
	end

	if self.seat then
		self.position = getSeatPosition(self, self.seat)
		self.velocity = Vector3.zero
		self.moveDirection = Vector3.zero
		self.grounded = true
		self.state = "sit"
		return true
	end

	return false
end

--[[
	@name fixedStep
	@arch server

	@desc Advances a single fixed-rate simulation tick.

	@param self Self Controller state.
	@param deltaTime number Step duration.
	@param input InputState User keyboard input.
	@param cameraCFrame CFrame Camera CFrame.
	@param settings MovementSettings Active settings.
	@returns nil
	@raises nil
]]
local function fixedStep(
	self: Self,
	deltaTime: number,
	input: InputState,
	cameraCFrame: CFrame,
	settings: MovementSettings
)
	updateEnvironment(self, deltaTime, settings)
	const jumpStarted = input.Space and not self.jumpWasDown

	if updateSeatMotion(self, jumpStarted, settings) then
		self.jumpWasDown = input.Space
		return
	end

	if self.nearTruss and self.climbCooldown <= 0 and not settings.fly and not self.swimming then
		if not self.isClimbing and (input.W or input.S or not self.grounded) then
			self.isClimbing = true
		end
	else
		self.isClimbing = false
	end

	if settings.fly then
		self.isClimbing = false
		stepFly(self, deltaTime, input, cameraCFrame, settings)
	elseif self.swimming then
		self.isClimbing = false
		stepSwim(self, deltaTime, input, cameraCFrame, settings)
	elseif self.isClimbing then
		stepClimb(self, deltaTime, input, settings)
	else
		stepGround(self, deltaTime, input, cameraCFrame, settings)
	end

	self.jumpWasDown = input.Space
end

--[[
	@name Step
	@arch server

	@desc Advances simulation by deltaTime with fixed-step catch-up and returns updated motion result.

	@param self Self Controller state.
	@param deltaTime number Render deltaTime.
	@param input InputState User keyboard input.
	@param cameraCFrame CFrame Camera orientation CFrame.
	@param settings MovementSettings Active settings.
	@returns MotionResult Motion result.
	@raises nil
]]
function MovementController.Step(
	self: Self,
	deltaTime: number,
	input: InputState,
	cameraCFrame: CFrame,
	settings: MovementSettings
): MotionResult
	if settings.fly ~= self.lastFly then
		self.velocity = Vector3.zero
		self.seat = nil
		self.isClimbing = false
		self.lastFly = settings.fly
	end

	self.accumulator = math.min(self.accumulator + deltaTime, Constants.FIXED_STEP * Constants.MAX_STEPS)
	local stepCount = 0
	while self.accumulator >= Constants.FIXED_STEP and stepCount < Constants.MAX_STEPS do
		fixedStep(self, Constants.FIXED_STEP, input, cameraCFrame, settings)
		self.accumulator -= Constants.FIXED_STEP
		stepCount += 1
	end

	return {
		position = self.position,
		velocity = self.velocity,
		state = self.state,
		moveDirection = self.moveDirection,
		grounded = self.grounded,
		seat = self.seat,
	}
end

--[[
	@name TeleportTo
	@arch server

	@desc Teleports avatar to world location cleanly on top of hit geometry.

	@param self Self Controller state.
	@param targetPosition Vector3 Target point.
	@returns nil
	@raises nil
]]
function MovementController.TeleportTo(self: Self, targetPosition: Vector3)
	self.position = targetPosition
	self.velocity = Vector3.zero
	self.grounded = true
	self.seat = nil
	self.seatCooldown = 0.5
	self.isClimbing = false
end

export type Controller = typeof(setmetatable({} :: Self, MovementController))

return MovementController

-- checcerr.
