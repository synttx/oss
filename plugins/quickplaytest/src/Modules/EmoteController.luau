--!strict
--!optimize 2

--[[
	@name EmoteController
	@arch server

	@desc Manages user-equipped and standard Roblox emotes, playback on dummy animator, and disturbance auto-cancellation.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")

local Constants = require("./Constants")
local Types = require("./Types")

--/ Types
type EmoteDefinition = Types.EmoteDefinition
type Rig = Types.Rig
type Self = {
	rig: Rig,
	userEmotes: { EmoteDefinition },
	defaultEmotes: { EmoteDefinition },
	activeTrack: AnimationTrack?,
	activeEmoteName: string?,
	onEmoteChanged: ((string?) -> ())?,
}

--/ Class
local EmoteController = {}
EmoteController.__index = EmoteController

--/ Functions

--[[
	@name fetchUserEmotes
	@arch server

	@desc Discovers equipped and owned emotes for the active Studio user.

	@param userId number Studio user ID.
	@returns { EmoteDefinition } List of user emotes.
	@raises nil
]]
local function fetchUserEmotes(userId: number): { EmoteDefinition }
	local emotes: { EmoteDefinition } = {}

	local success, description = pcall(function(): HumanoidDescription
		return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
	end)
	if success and description then
		local equipped = description:GetEquippedEmotes()
		local allEmotes = description:GetEmotes()

		for _, item in equipped do
			const slotEmoteName = item.Name
			const ids = allEmotes[slotEmoteName]
			if ids and #ids > 0 then
				const assetId = ids[1]
				table.insert(emotes, {
					name = slotEmoteName,
					command = `/e {slotEmoteName:lower()}`,
					idR15 = assetId,
					idR6 = assetId,
					looped = false,
					isUserEmote = true,
				})
			end
		end

		if #emotes == 0 then
			for emoteName, ids in allEmotes do
				if #ids > 0 then
					table.insert(emotes, {
						name = emoteName,
						command = `/e {emoteName:lower()}`,
						idR15 = ids[1],
						idR6 = ids[1],
						looped = false,
						isUserEmote = true,
					})
				end
			end
		end
	end

	return emotes
end

--[[
	@name getDefaultEmotesList
	@arch server

	@desc Compiles standard Roblox default emotes (/e dance, wave, cheer, laugh, point).

	@returns { EmoteDefinition } List of default emotes.
	@raises nil
]]
local function getDefaultEmotesList(): { EmoteDefinition }
	local list: { EmoteDefinition } = {}
	for _, emote in Constants.DEFAULT_EMOTES do
		table.insert(list, emote)
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

--[[
	@name resolveAnimationAssetId
	@arch server

	@desc Resolves raw animation asset ID from an animation package or direct ID.

	@param assetId number Catalog asset ID.
	@returns number Resolved Animation object ID.
	@raises nil
]]
local function resolveAnimationAssetId(assetId: number): number
	local resolved = assetId
	pcall(function()
		const asset = InsertService:LoadAsset(assetId)
		const anim = asset:FindFirstChildWhichIsA("Animation", true)
		if anim then
			const num = anim.AnimationId:match("%d+")
			if num then
				resolved = tonumber(num) or assetId
			end
		end
		asset:Destroy()
	end)
	return resolved
end

--[[
	@name new
	@arch server

	@desc Constructs an EmoteController for an active avatar rig.

	@param rig Rig Avatar rig structure.
	@returns Self Initialized controller instance.
	@raises nil
]]
function EmoteController.new(rig: Rig): Self
	const userEmotes = fetchUserEmotes(rig.ownerUserId)
	const defaultEmotes = getDefaultEmotesList()

	return setmetatable({
		rig = rig,
		userEmotes = userEmotes,
		defaultEmotes = defaultEmotes,
		activeTrack = nil,
		activeEmoteName = nil,
		onEmoteChanged = nil,
	}, EmoteController) :: any
end

--[[
	@name SetOnEmoteChanged
	@arch server

	@desc Registers callback invoked whenever active emote changes or stops.

	@param self Self EmoteController instance.
	@param callback ((string?) -> ()) Callback function.
	@returns nil
	@raises nil
]]
function EmoteController.SetOnEmoteChanged(self: Self, callback: (string?) -> ())
	self.onEmoteChanged = callback
end

--[[
	@name PlayEmote
	@arch server

	@desc Loads and plays selected emote animation on dummy animator.

	@param self Self EmoteController instance.
	@param emote EmoteDefinition Emote definition.
	@returns boolean Whether playback started.
	@raises nil
]]
function EmoteController.PlayEmote(self: Self, emote: EmoteDefinition): boolean
	self:StopEmote()

	const targetId = if self.rig.isR15 then emote.idR15 else emote.idR6
	const actualAnimId = resolveAnimationAssetId(targetId)

	const animation = Instance.new("Animation")
	animation.Name = `Emote_{emote.name}`
	animation.AnimationId = `rbxassetid://{actualAnimId}`

	local success, track = pcall(function(): AnimationTrack
		return self.rig.animator:LoadAnimation(animation)
	end)

	if not success or not track then
		return false
	end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = emote.looped
	track:Play(0.2)

	self.activeTrack = track
	self.activeEmoteName = emote.name

	if not emote.looped then
		track.Stopped:Connect(function()
			if self.activeTrack == track then
				self.activeTrack = nil
				self.activeEmoteName = nil
				if self.onEmoteChanged then
					self.onEmoteChanged(nil)
				end
			end
		end)
	end

	if self.onEmoteChanged then
		self.onEmoteChanged(emote.name)
	end

	return true
end

--[[
	@name StopEmote
	@arch server

	@desc Halts active emote playback immediately.

	@param self Self EmoteController instance.
	@returns nil
	@raises nil
]]
function EmoteController.StopEmote(self: Self)
	if self.activeTrack then
		self.activeTrack:Stop(0.15)
		self.activeTrack:Destroy()
		self.activeTrack = nil
		self.activeEmoteName = nil
		if self.onEmoteChanged then
			self.onEmoteChanged(nil)
		end
	end
end

--[[
	@name HandleDisturbance
	@arch server

	@desc Cancels active emote immediately upon movement, jump, or physical disturbance.

	@param self Self EmoteController instance.
	@returns nil
	@raises nil
]]
function EmoteController.HandleDisturbance(self: Self)
	if self.activeTrack then
		self:StopEmote()
	end
end

--[[
	@name GetActiveEmoteName
	@arch server

	@desc Returns the name of currently playing emote if any.

	@param self Self EmoteController instance.
	@returns string? Active emote name.
	@raises nil
]]
function EmoteController.GetActiveEmoteName(self: Self): string?
	return self.activeEmoteName
end

--[[
	@name GetUserEmotes
	@arch server

	@desc Returns catalog of equipped and owned user emotes.

	@param self Self EmoteController instance.
	@returns { EmoteDefinition } List of user emotes.
	@raises nil
]]
function EmoteController.GetUserEmotes(self: Self): { EmoteDefinition }
	return self.userEmotes
end

--[[
	@name GetDefaultEmotes
	@arch server

	@desc Returns list of standard Roblox default emotes.

	@param self Self EmoteController instance.
	@returns { EmoteDefinition } List of default emotes.
	@raises nil
]]
function EmoteController.GetDefaultEmotes(self: Self): { EmoteDefinition }
	return self.defaultEmotes
end

--[[
	@name Destroy
	@arch server

	@desc Cleans up active emote tracks.

	@param self Self EmoteController instance.
	@returns nil
	@raises nil
]]
function EmoteController.Destroy(self: Self)
	self:StopEmote()
end

export type Controller = typeof(setmetatable({} :: Self, EmoteController))

return EmoteController

-- checcerr.
