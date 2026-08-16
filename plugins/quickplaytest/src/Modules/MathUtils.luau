--!strict
--!optimize 2

--[[
	@name MathUtils
	@arch shared

	@desc Vector and kinematic math utilities adapted from Chickynoid/Quake for character physics.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Constants
const THETA = math.pi * 2

--/ Module
local MathUtils = {}

--/ Functions

--[[
	@name normalizeAngle
	@arch shared

	@desc Wraps an angle in radians to [0, 2*pi).

	@param angle number Input angle in radians.

	@returns number Normalized angle.

	@raises nil
]]
function MathUtils.normalizeAngle(angle: number): number
	local result = angle % THETA
	if result < 0 then
		result += THETA
	end
	return result
end

--[[
	@name angleShortest
	@arch shared

	@desc Returns shortest angular delta from angle0 to angle1.

	@param angle0 number Start angle.
	@param angle1 number Target angle.

	@returns number Shortest delta.

	@raises nil
]]
function MathUtils.angleShortest(angle0: number, angle1: number): number
	const d1 = MathUtils.normalizeAngle(angle1 - angle0)
	const d2 = -MathUtils.normalizeAngle(angle0 - angle1)
	return if math.abs(d1) > math.abs(d2) then d2 else d1
end

--[[
	@name lerpAngle
	@arch shared

	@desc Interpolates between two angles along the shortest arc.

	@param angle0 number Start angle.
	@param angle1 number Target angle.
	@param frac number Interpolation factor [0, 1].

	@returns number Interpolated angle.

	@raises nil
]]
function MathUtils.lerpAngle(angle0: number, angle1: number, frac: number): number
	return angle0 + MathUtils.angleShortest(angle0, angle1) * frac
end

--[[
	@name friction
	@arch shared

	@desc DeltaTime-independent friction decay.

	@param val number Initial value.
	@param fric number Friction time constant (lower is faster decay).
	@param dt number Delta time in seconds.

	@returns number Decayed value.

	@raises nil
]]
function MathUtils.friction(val: number, fric: number, dt: number): number
	return (1 / (1 + (dt / math.max(fric, 0.0001)))) * val
end

--[[
	@name velocityFriction
	@arch shared

	@desc Applies friction decay to a velocity vector.

	@param vel Vector3 Velocity vector.
	@param fric number Friction time constant.
	@param dt number Delta time in seconds.

	@returns Vector3 Decayed velocity vector.

	@raises nil
]]
function MathUtils.velocityFriction(vel: Vector3, fric: number, dt: number): Vector3
	const speed = vel.Magnitude
	if speed < 0.001 then
		return Vector3.zero
	end
	const decayedSpeed = MathUtils.friction(speed, fric, dt)
	if decayedSpeed < 0.001 then
		return Vector3.zero
	end
	return vel.Unit * decayedSpeed
end

--[[
	@name flatVec
	@arch shared

	@desc Projects a 3D vector onto the horizontal XZ plane.

	@param vec Vector3 Input vector.

	@returns Vector3 Horizontal vector.

	@raises nil
]]
function MathUtils.flatVec(vec: Vector3): Vector3
	return Vector3.new(vec.X, 0, vec.Z)
end

--[[
	@name groundAccelerate
	@arch shared

	@desc Quake/Chickynoid-style ground acceleration with snappy redirection and friction clamping.

	@param wishDir Vector3 Normalized desired movement direction.
	@param wishSpeed number Target top speed.
	@param accel number Acceleration rate.
	@param currentVelocity Vector3 Current flat velocity.
	@param dt number Delta time.

	@returns Vector3 New flat velocity.

	@raises nil
]]
function MathUtils.groundAccelerate(
	wishDir: Vector3,
	wishSpeed: number,
	accel: number,
	currentVelocity: Vector3,
	dt: number
): Vector3
	local velocity = currentVelocity
	const speed = velocity.Magnitude
	if speed > wishSpeed and speed > 0.001 then
		velocity = velocity.Unit * wishSpeed
	end

	const wishVel = wishDir * wishSpeed
	const pushDir = wishVel - velocity
	const pushLen = pushDir.Magnitude

	local canPush = accel * dt * wishSpeed
	if canPush > pushLen then
		canPush = pushLen
	end
	if canPush < 0.00001 or pushLen < 0.00001 then
		return velocity
	end
	return velocity + (pushDir.Unit * canPush)
end

--[[
	@name airAccelerate
	@arch shared

	@desc Direct responsive air acceleration without slippery inertia.

	@param wishDir Vector3 Normalized desired movement direction.
	@param wishSpeed number Max air speed.
	@param accel number Air acceleration rate.
	@param currentVelocity Vector3 Current flat velocity.
	@param dt number Delta time.

	@returns Vector3 New flat velocity.

	@raises nil
]]
function MathUtils.airAccelerate(
	wishDir: Vector3,
	wishSpeed: number,
	accel: number,
	currentVelocity: Vector3,
	dt: number
): Vector3
	const targetVel = wishDir * wishSpeed
	const diff = targetVel - currentVelocity
	const maxChange = accel * wishSpeed * dt
	if diff.Magnitude <= maxChange then
		return targetVel
	end
	return currentVelocity + diff.Unit * maxChange
end

--[[
	@name clipVelocity
	@arch shared

	@desc Projects velocity onto a collision surface normal to slide smoothly along obstacles without losing tangential momentum.

	@param input Vector3 Incoming velocity vector.
	@param normal Vector3 Collision surface normal.
	@param overbounce number? Overbounce/restitution multiplier (typically 1.001 for clean sliding).

	@returns Vector3 Deflected velocity vector.

	@raises nil
]]
function MathUtils.clipVelocity(input: Vector3, normal: Vector3, overbounce: number?): Vector3
	const bounce = overbounce or 1.001
	local backoff = input:Dot(normal)

	if backoff < 0 then
		backoff *= bounce
	else
		backoff /= bounce
	end

	return Vector3.new(input.X - (normal.X * backoff), input.Y - (normal.Y * backoff), input.Z - (normal.Z * backoff))
end

--[[
	@name smoothLerp
	@arch shared

	@desc DeltaTime-independent exponential smoothing.

	@param current number Current value.
	@param target number Target value.
	@param fraction number Convergence factor.
	@param dt number Delta time in seconds.

	@returns number Smoothed value.

	@raises nil
]]
function MathUtils.smoothLerp(current: number, target: number, fraction: number, dt: number): number
	const f = 1.0 - math.pow(math.clamp(1.0 - fraction, 0, 1), dt)
	return (current * (1 - f)) + (target * f)
end

return table.freeze(MathUtils)

-- checcerr.
