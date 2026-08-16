--!strict
--!optimize 2

--[[
	@name CharacterFactory
	@arch server

	@desc Creates edit-mode avatars named {username}_QP with embedded dummy rigs and derived collision geometry.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local StudioService = game:GetService("StudioService")

local Constants = require("./Constants")
local Types = require("./Types")

--/ Types
type AnimationIds = Types.AnimationIds
type Rig = Types.Rig

--/ Module
local CharacterFactory = {}

--/ Functions

--[[
	@name getUserId
	@arch server

	@desc Returns Studio user ID with stable fallback.

	@returns number Studio user ID.

	@raises nil
]]
local function getUserId(): number
	local userId = 0
	pcall(function()
		userId = StudioService:GetUserId()
	end)
	return if userId <= 0 then 1 else userId
end

--[[
	@name getUsername
	@arch server

	@desc Resolves username for given user ID with fallback.

	@param userId number User ID.

	@returns string Resolved username.

	@raises nil
]]
local function getUsername(userId: number): string
	local username = "Player"
	pcall(function()
		username = Players:GetNameFromUserIdAsync(userId)
	end)
	return username
end

--[[
	@name getDescription
	@arch server

	@desc Retrieves equipped avatar description for user.

	@param userId number User ID.

	@returns HumanoidDescription Equipped description.

	@raises nil
]]
local function getDescription(userId: number): HumanoidDescription
	local success, result = pcall(function(): HumanoidDescription
		return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
	end)
	if success and result then
		return result :: HumanoidDescription
	end
	return Instance.new("HumanoidDescription")
end

--[[
	@name getAnimationIds
	@arch server

	@desc Resolves animation asset IDs from description with fallbacks for R15 and R6.

	@param description HumanoidDescription Avatar description.
	@param rigType Enum.HumanoidRigType Rig type enum.

	@returns AnimationIds Resolved animation IDs.

	@raises nil
]]
local function getAnimationIds(description: HumanoidDescription, rigType: Enum.HumanoidRigType): AnimationIds
	local catalogIds: AnimationIds
	if rigType == Enum.HumanoidRigType.R6 then
		catalogIds = table.clone(Constants.ANIMATIONS.R6)
	else
		const fallback = Constants.ANIMATIONS.R15
		const swimId = if description.SwimAnimation > 0 then description.SwimAnimation else fallback.swim
		catalogIds = {
			idle = if description.IdleAnimation > 0 then description.IdleAnimation else fallback.idle,
			walk = if description.WalkAnimation > 0
				then description.WalkAnimation
				elseif description.RunAnimation > 0 then description.RunAnimation
				else fallback.walk,
			jump = if description.JumpAnimation > 0 then description.JumpAnimation else fallback.jump,
			fall = if description.FallAnimation > 0 then description.FallAnimation else fallback.fall,
			climb = if description.ClimbAnimation > 0 then description.ClimbAnimation else fallback.climb,
			swim = swimId,
			swimidle = swimId,
			sit = fallback.sit,
		}
	end

	const resolved = table.clone(catalogIds)
	const bindable = Instance.new("BindableEvent")
	local count = 0
	for key, assetId in catalogIds :: { [string]: number } do
		task.spawn(function()
			local success, result = pcall(function()
				return InsertService:LoadAsset(assetId)
			end)
			if success and result then
				const anim = result:FindFirstChildWhichIsA("Animation", true)
				if anim then
					const num = anim.AnimationId:match("%d+")
					if num then
						(resolved :: any)[key] = tonumber(num) or assetId
					end
				end
				result:Destroy()
			end
			count += 1
			if count == 8 then
				bindable:Fire()
			end
		end)
	end
	if count < 8 then
		bindable.Event:Wait()
	end
	bindable:Destroy()

	return resolved
end

--[[
	@name createModel
	@arch server

	@desc Creates avatar character model from description.

	@param description HumanoidDescription Avatar description.
	@param rigType Enum.HumanoidRigType Rig type enum.

	@returns Model Avatar model.

	@raises nil
]]
local function createModel(description: HumanoidDescription, rigType: Enum.HumanoidRigType): Model
	local success, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescriptionAsync(description, rigType, Enum.AssetTypeVerification.Default)
	end)
	if success and result then
		return result :: Model
	end
	return Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), rigType)
end

--[[
	@name getContainer
	@arch server

	@desc Retrieves or creates the dedicated Terrain folder for plugin models.

	@returns Folder Container folder.

	@raises nil
]]
local function getContainer(): Folder
	local terrain = workspace:WaitForChild("Terrain") :: Terrain
	local container = terrain:FindFirstChild("QuickPlaytestContainer")
	if not container then
		container = Instance.new("Folder")
		container.Name = "QuickPlaytestContainer"
		container.Parent = terrain
	end
	return container :: Folder
end

--[[
	@name removeStaleAvatar
	@arch server

	@desc Destroys any previously spawned avatars for this user.

	@param userId number Studio user ID.
	@param username string Username.

	@returns nil

	@raises nil
]]
local function removeStaleAvatar(userId: number, username: string)
	const targetName = `{username}_QP`
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and (child.Name == targetName or child:GetAttribute("PlaytestOwner") == userId) then
			child:Destroy()
		end
	end
	const container = getContainer()
	for _, child in container:GetChildren() do
		if child:IsA("Model") and (child.Name == targetName or child:GetAttribute("PlaytestOwner") == userId) then
			child:Destroy()
		end
	end
end

--[[
	@name measureBody
	@arch server

	@desc Measures body part extents (excluding accessories and dummy rig) for exact collision calculations.

	@param model Model Avatar model.
	@param root BasePart HumanoidRootPart.
	@param dummyModel Model Embedded dummy rig.

	@returns (number, number, Vector3) groundOffset, centerOffset, colliderSize.

	@raises nil
]]
local function measureBody(model: Model, root: BasePart, dummyModel: Model): (number, number, Vector3)
	local lowest = root.Position.Y - root.Size.Y / 2
	local highest = root.Position.Y + root.Size.Y / 2
	local torsoSize = root.Size
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root and child ~= dummyModel and not child:IsDescendantOf(dummyModel) then
			lowest = math.min(lowest, child.Position.Y - child.Size.Y / 2)
			highest = math.max(highest, child.Position.Y + child.Size.Y / 2)
			if child.Name == "UpperTorso" or child.Name == "Torso" then
				torsoSize = child.Size
			end
		end
	end
	const groundOffset = math.max(root.Size.Y / 2, root.Position.Y - lowest)
	const topOffset = math.max(root.Size.Y / 2, highest - root.Position.Y)
	const centerOffset = (topOffset - groundOffset) / 2
	const colliderSize = Vector3.new(
		math.max(1.5, torsoSize.X * 0.9),
		math.max(2, topOffset + groundOffset),
		math.max(1.2, torsoSize.Z * 0.9)
	)
	return groundOffset, centerOffset, colliderSize
end

--[[
	@name create
	@arch server

	@desc Creates and configures a non-physical edit-mode avatar named {username}_QP with embedded dummy rig.

	@param rigType Enum.HumanoidRigType Rig type enum (R15 or R6).
	@param startCFrame CFrame Initial world transform.

	@returns Rig Complete Rig data structure.

	@raises nil
]]
function CharacterFactory.create(rigType: Enum.HumanoidRigType, startCFrame: CFrame): Rig
	const userId = getUserId()
	const username = getUsername(userId)
	removeStaleAvatar(userId, username)

	const description = getDescription(userId)
	const model = createModel(description, rigType)
	model.Name = `{username}_QP`
	model:SetAttribute("PlaytestOwner", userId)
	model:SetAttribute("PlaytestUsername", username)
	model.Archivable = true

	const dummyModel = model:Clone()
	dummyModel.Name = "DummyRig"
	dummyModel:PivotTo(CFrame.new(0, 100000, 0))
	for _, descendant in dummyModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Light")
		then
			descendant.Enabled = false
		end
	end

	const dummyRoot = dummyModel:WaitForChild("HumanoidRootPart") :: BasePart
	dummyRoot.Anchored = true
	dummyModel.Parent = model
	model.Archivable = false

	const root = model:WaitForChild("HumanoidRootPart") :: BasePart
	const humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local realAnimator = humanoid:FindFirstChildOfClass("Animator")
	if realAnimator then
		realAnimator:Destroy()
	end

	const dummyHumanoid = dummyModel:WaitForChild("Humanoid") :: Humanoid
	local dummyAnimator = dummyHumanoid:FindFirstChildOfClass("Animator")
	if not dummyAnimator then
		dummyAnimator = Instance.new("Animator")
		dummyAnimator.Parent = dummyHumanoid
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.AutoRotate = false
	model:PivotTo(startCFrame)

	local visualParts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:IsDescendantOf(dummyModel) then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			table.insert(visualParts, descendant)
		end
	end

	const groundOffset, centerOffset, colliderSize = measureBody(model, root, dummyModel)
	model.Parent = getContainer()

	return {
		model = model,
		dummyModel = dummyModel,
		humanoid = humanoid,
		animator = dummyAnimator :: Animator,
		root = root,
		visualParts = visualParts,
		animationIds = getAnimationIds(description, rigType),
		groundOffset = groundOffset,
		centerOffset = centerOffset,
		colliderSize = colliderSize,
		isR15 = rigType == Enum.HumanoidRigType.R15,
		ownerUserId = userId,
		ownerUsername = username,
	}
end

return table.freeze(CharacterFactory)

-- checcerr.
