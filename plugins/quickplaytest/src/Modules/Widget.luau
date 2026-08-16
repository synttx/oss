--!strict
--!optimize 2

--[[
	@name Widget
	@arch client

	@desc Studio dock widget interface with Vide reactive spring animations, interactive sliders, and 4-tab navigation.

	@version 2.0.0
	@license MPL-2.0
	@author checcerr
]]

--/ Dependencies
local Config = require("./Config")
local Constants = require("./Constants")
local Types = require("./Types")
local vide = require("../Vendor/Vide/init")

--/ Types
type EmoteDefinition = Types.EmoteDefinition
type Palette = Types.Palette
type Self = {
	toolbar: PluginToolbar,
	toolbarButton: PluginToolbarButton,
	gui: DockWidgetPluginGui,
	destroyRoot: () -> (),
	isPlaying: vide.Source<boolean>,
	isR15: vide.Source<boolean>,
	activeTab: vide.Source<string>,
	walkSpeed: vide.Source<string>,
	jumpPower: vide.Source<string>,
	maxSlopeAngle: vide.Source<string>,
	includeGravity: vide.Source<boolean>,
	fly: vide.Source<boolean>,
	noclip: vide.Source<boolean>,
	clickToTeleport: vide.Source<boolean>,
	activeEmoteName: vide.Source<string?>,
	userEmotes: vide.Source<{ EmoteDefinition }>,
	defaultEmotes: vide.Source<{ EmoteDefinition }>,
	onSpawnpointCallback: (() -> ())?,
	onSpawnCameraCallback: (() -> ())?,
	onStopCallback: (() -> ())?,
	onPlayEmoteCallback: ((EmoteDefinition) -> ())?,
	onStopEmoteCallback: (() -> ())?,
	connections: { RBXScriptConnection },
}

type TabInfo = {
	name: string,
	order: number,
}

--/ Constants
const TAB_ITEMS: { TabInfo } = {
	{ name = "Main", order = 1 },
	{ name = "Properties", order = 2 },
	{ name = "Emotes", order = 3 },
	{ name = "Credits", order = 4 },
}

--/ Class
local Widget = {}
Widget.__index = Widget

--/ Functions

--[[
	@name getPalette
	@arch client

	@desc Returns theme-aware color palette for Dark and Light Studio themes.

	@returns Palette Color palette table.
	@raises nil
]]
local function getPalette(): Palette
	local isDark = true
	pcall(function()
		const theme = settings().Studio.Theme
		if theme and theme.Name == "Light" then
			isDark = false
		end
	end)

	if isDark then
		return {
			background = Color3.fromRGB(24, 26, 31),
			surface = Color3.fromRGB(36, 39, 47),
			surfaceHover = Color3.fromRGB(48, 52, 63),
			surfaceActive = Color3.fromRGB(56, 61, 74),
			border = Color3.fromRGB(55, 60, 72),
			text = Color3.fromRGB(240, 243, 248),
			dim = Color3.fromRGB(150, 158, 172),
			accent = Color3.fromRGB(45, 119, 255),
			accentHover = Color3.fromRGB(65, 135, 255),
			accentText = Color3.fromRGB(255, 255, 255),
			danger = Color3.fromRGB(205, 55, 65),
			dangerHover = Color3.fromRGB(225, 70, 80),
			input = Color3.fromRGB(18, 20, 24),
			tabActive = Color3.fromRGB(45, 119, 255),
			tabInactive = Color3.fromRGB(36, 39, 47),
		}
	end

	return {
		background = Color3.fromRGB(246, 248, 251),
		surface = Color3.fromRGB(232, 235, 241),
		surfaceHover = Color3.fromRGB(220, 224, 232),
		surfaceActive = Color3.fromRGB(210, 215, 224),
		border = Color3.fromRGB(200, 206, 216),
		text = Color3.fromRGB(28, 32, 39),
		dim = Color3.fromRGB(100, 108, 122),
		accent = Color3.fromRGB(30, 105, 235),
		accentHover = Color3.fromRGB(45, 120, 250),
		accentText = Color3.fromRGB(255, 255, 255),
		danger = Color3.fromRGB(195, 45, 55),
		dangerHover = Color3.fromRGB(215, 60, 70),
		input = Color3.fromRGB(255, 255, 255),
		tabActive = Color3.fromRGB(30, 105, 235),
		tabInactive = Color3.fromRGB(232, 235, 241),
	}
end

--[[
	@name createStyledButton
	@arch client

	@desc Creates a themed interactive button with spring-animated hover transitions.

	@param props { text: any, onClick: () -> (), isPrimary: any, isDanger: any, disabled: any, height: number?, width: UDim?, position: UDim2? }
	@param paletteSource vide.Source<Palette>
	@returns Instance TextButton instance.
	@raises nil
]]
local function createStyledButton(
	props: {
		text: any,
		onClick: () -> (),
		isPrimary: any,
		isDanger: any,
		disabled: any,
		height: number?,
		width: UDim?,
		position: UDim2?,
	},
	paletteSource: vide.Source<Palette>
): Instance
	const create = vide.create
	const isHovered = vide.source(false)

	const btnHeight = props.height or 36
	const btnWidth = props.width or UDim.new(1, 0)

	const targetColor = function(): Color3
		const pal = paletteSource()
		const disabled = props.disabled and props.disabled()
		const isDanger = if type(props.isDanger) == "function" then props.isDanger() else props.isDanger
		const isPrimary = if type(props.isPrimary) == "function" then props.isPrimary() else props.isPrimary

		if isDanger then
			return if disabled then pal.surface elseif isHovered() then pal.dangerHover else pal.danger
		elseif isPrimary then
			return if disabled then pal.surface elseif isHovered() then pal.accentHover else pal.accent
		else
			return if disabled then pal.surface elseif isHovered() then pal.surfaceHover else pal.surface
		end
	end

	const animatedBg = vide.spring(targetColor, 0.15, 0.9)

	return create("TextButton")({
		Position = props.position or UDim2.new(),
		Size = UDim2.new(btnWidth.Scale, btnWidth.Offset, 0, btnHeight),
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansMedium,
		Text = props.text,
		TextSize = 13,
		AutoButtonColor = false,

		TextColor3 = function()
			const pal = paletteSource()
			if props.disabled and props.disabled() then
				return pal.dim
			end
			const isDanger = if type(props.isDanger) == "function" then props.isDanger() else props.isDanger
			const isPrimary = if type(props.isPrimary) == "function" then props.isPrimary() else props.isPrimary
			if isPrimary or isDanger then
				return pal.accentText
			end
			return pal.text
		end,

		BackgroundColor3 = animatedBg,

		BackgroundTransparency = function()
			if props.disabled and props.disabled() then
				return 0.45
			end
			return 0
		end,

		TextTransparency = function()
			if props.disabled and props.disabled() then
				return 0.45
			end
			return 0
		end,

		MouseEnter = function()
			if not (props.disabled and props.disabled()) then
				isHovered(true)
			end
		end,

		MouseLeave = function()
			isHovered(false)
		end,

		Activated = function()
			if not (props.disabled and props.disabled()) then
				props.onClick()
			end
		end,

		create("UICorner")({
			CornerRadius = UDim.new(0, 6),
		}),

		create("UIStroke")({
			Thickness = 1,
			Color = function()
				const pal = paletteSource()
				const isDanger = if type(props.isDanger) == "function" then props.isDanger() else props.isDanger
				const isPrimary = if type(props.isPrimary) == "function" then props.isPrimary() else props.isPrimary
				if isPrimary and not (props.disabled and props.disabled()) then
					return pal.accent
				elseif isDanger and not (props.disabled and props.disabled()) then
					return pal.danger
				end
				return pal.border
			end,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

--[[
	@name createCheckbox
	@arch client

	@desc Creates a themed binary checkbox control with spring transitions.

	@param labelText string Field label.
	@param checkedSource vide.Source<boolean> Reactive checked state.
	@param paletteSource vide.Source<Palette>
	@returns Instance Row frame instance.
	@raises nil
]]
local function createCheckbox(
	labelText: string,
	checkedSource: vide.Source<boolean>,
	paletteSource: vide.Source<Palette>
): Instance
	const create = vide.create
	const isHovered = vide.source(false)

	const targetBoxColor = function(): Color3
		const pal = paletteSource()
		if checkedSource() then
			return if isHovered() then pal.accentHover else pal.accent
		end
		return if isHovered() then pal.surfaceHover else pal.surface
	end
	const animBoxBg = vide.spring(targetBoxColor, 0.15, 0.9)

	return create("Frame")({
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		create("TextButton")({
			Size = UDim2.fromOffset(20, 20),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = function()
				return if checkedSource() then "✓" else ""
			end,
			TextSize = 13,
			Font = Enum.Font.BuilderSansBold,
			TextColor3 = function()
				return paletteSource().accentText
			end,
			BackgroundColor3 = animBoxBg,

			MouseEnter = function()
				isHovered(true)
			end,
			MouseLeave = function()
				isHovered(false)
			end,
			Activated = function()
				checkedSource(not checkedSource())
			end,

			create("UICorner")({
				CornerRadius = UDim.new(0, 4),
			}),
			create("UIStroke")({
				Thickness = 1,
				Color = function()
					return if checkedSource() then paletteSource().accent else paletteSource().border
				end,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),

		create("TextLabel")({
			Size = UDim2.new(1, -30, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSans,
			Text = labelText,
			TextSize = 13,
			TextColor3 = function()
				return paletteSource().text
			end,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

--[[
	@name createSliderRow
	@arch client

	@desc Creates an interactive slider with a linked numeric text box and spring animation.

	@param labelText string Field label.
	@param valueSource vide.Source<string> Reactive string value.
	@param minVal number Minimum slider value.
	@param maxVal number Maximum slider value.
	@param defaultVal number Fallback default value.
	@param paletteSource vide.Source<Palette> Theme palette source.
	@returns Instance Slider row frame instance.
	@raises nil
]]
local function createSliderRow(
	labelText: string,
	valueSource: vide.Source<string>,
	minVal: number,
	maxVal: number,
	defaultVal: number,
	paletteSource: vide.Source<Palette>
): Instance
	const create = vide.create

	const getFraction = function(): number
		const val = tonumber(valueSource()) or defaultVal
		return math.clamp((val - minVal) / math.max(1, maxVal - minVal), 0, 1)
	end

	const springFraction = vide.spring(getFraction, 0.1, 0.95)

	return create("Frame")({
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		-- Label + Numeric Box Header
		create("Frame")({
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			create("TextLabel")({
				Size = UDim2.new(1, -70, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.BuilderSansMedium,
				Text = labelText,
				TextSize = 13,
				TextColor3 = function()
					return paletteSource().dim
				end,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			create("TextBox")({
				Position = UDim2.new(1, -64, 0, 0),
				Size = UDim2.fromOffset(64, 24),
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Enum.Font.BuilderSansBold,
				Text = function()
					return valueSource()
				end,
				TextSize = 12,
				TextColor3 = function()
					return paletteSource().text
				end,
				BackgroundColor3 = function()
					return paletteSource().input
				end,
				TextXAlignment = Enum.TextXAlignment.Center,

				create("UICorner")({
					CornerRadius = UDim.new(0, 4),
				}),
				create("UIStroke")({
					Thickness = 1,
					Color = function()
						return paletteSource().border
					end,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),

				vide.action(function(box: TextBox)
					box:GetPropertyChangedSignal("Text"):Connect(function()
						const num = tonumber(box.Text)
						if num then
							valueSource(box.Text)
						end
					end)
					box.FocusLost:Connect(function()
						const num = tonumber(box.Text)
						if not num then
							box.Text = tostring(defaultVal)
							valueSource(tostring(defaultVal))
						else
							const clamped = math.clamp(num, minVal, maxVal)
							box.Text = tostring(clamped)
							valueSource(tostring(clamped))
						end
					end)
				end),
			}),
		}),

		-- Interactive Slider Track
		create("TextButton")({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,

			-- Inactive track background bar
			create("Frame")({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 6),
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return paletteSource().border
				end,

				create("UICorner")({
					CornerRadius = UDim.new(0, 3),
				}),
			}),

			-- Filled accent bar
			create("Frame")({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = function()
					return UDim2.new(springFraction(), 0, 0, 6)
				end,
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return paletteSource().accent
				end,

				create("UICorner")({
					CornerRadius = UDim.new(0, 3),
				}),
			}),

			-- Draggable slider knob
			create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromScale(springFraction(), 0.5)
				end,
				Size = UDim2.fromOffset(14, 14),
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return paletteSource().accentText
				end,

				create("UICorner")({
					CornerRadius = UDim.new(1, 0),
				}),
				create("UIStroke")({
					Thickness = 2,
					Color = function()
						return paletteSource().accent
					end,
				}),
			}),

			vide.action(function(trackButton: TextButton)
				local isDragging = false

				local function applyInput(inputObj: InputObject)
					const absX = trackButton.AbsolutePosition.X
					const absW = math.max(1, trackButton.AbsoluteSize.X)
					const frac = math.clamp((inputObj.Position.X - absX) / absW, 0, 1)
					const computedVal = math.round(minVal + frac * (maxVal - minVal))
					valueSource(tostring(computedVal))
				end

				trackButton.InputBegan:Connect(function(inputObj)
					if
						inputObj.UserInputType == Enum.UserInputType.MouseButton1
						or inputObj.UserInputType == Enum.UserInputType.Touch
					then
						isDragging = true
						applyInput(inputObj)
					end
				end)

				trackButton.InputChanged:Connect(function(inputObj)
					if
						isDragging
						and (
							inputObj.UserInputType == Enum.UserInputType.MouseMovement
							or inputObj.UserInputType == Enum.UserInputType.Touch
						)
					then
						applyInput(inputObj)
					end
				end)

				trackButton.InputEnded:Connect(function(inputObj)
					if
						inputObj.UserInputType == Enum.UserInputType.MouseButton1
						or inputObj.UserInputType == Enum.UserInputType.Touch
					then
						isDragging = false
					end
				end)
			end),
		}),
	})
end

--[[
	@name buildMainTab
	@arch client

	@desc Builds Main tab with full-width spawn buttons, avatar toggle, and stop button.

	@param self Self Widget instance.
	@param paletteSource vide.Source<Palette>
	@returns Instance Frame containing Main tab controls.
	@raises nil
]]
local function buildMainTab(self: Self, paletteSource: vide.Source<Palette>): Instance
	const create = vide.create

	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		create("UIListLayout")({
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		createStyledButton({
			text = function()
				return `Avatar  {if self.isR15() then "R15" else "R6"}`
			end,
			onClick = function()
				self.isR15(not self.isR15())
			end,
			isPrimary = false,
			isDanger = false,
			disabled = function()
				return self.isPlaying()
			end,
			height = 36,
		}, paletteSource),

		createStyledButton({
			text = "Spawn at Spawnpoint",
			onClick = function()
				if self.onSpawnpointCallback then
					self.onSpawnpointCallback()
				end
			end,
			isPrimary = true,
			isDanger = false,
			disabled = function()
				return self.isPlaying()
			end,
			height = 42,
		}, paletteSource),

		createStyledButton({
			text = "Spawn at Camera",
			onClick = function()
				if self.onSpawnCameraCallback then
					self.onSpawnCameraCallback()
				end
			end,
			isPrimary = false,
			isDanger = false,
			disabled = function()
				return self.isPlaying()
			end,
			height = 42,
		}, paletteSource),

		vide.show(function()
			return self.isPlaying()
		end, function()
			return createStyledButton({
				text = "Stop Session",
				onClick = function()
					if self.onStopCallback then
						self.onStopCallback()
					end
				end,
				isPrimary = false,
				isDanger = true,
				disabled = function()
					return false
				end,
				height = 38,
			}, paletteSource)
		end),
	})
end

--[[
	@name buildPropertiesTab
	@arch client

	@desc Builds Properties tab with interactive sliders for speed, jump, slope angle, fly, noclip, and teleport options.

	@param self Self Widget instance.
	@param paletteSource vide.Source<Palette>
	@returns Instance Frame containing Properties tab.
	@raises nil
]]
local function buildPropertiesTab(self: Self, paletteSource: vide.Source<Palette>): Instance
	const create = vide.create

	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		create("UIListLayout")({
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		createSliderRow("Walk Speed", self.walkSpeed, 0, 120, 16, paletteSource),
		createSliderRow("Jump Power", self.jumpPower, 0, 200, 50, paletteSource),
		createSliderRow("Max Slope Angle (°)", self.maxSlopeAngle, 0, 89, 55, paletteSource),

		createCheckbox("Include Gravity", self.includeGravity, paletteSource),

		create("Frame")({
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
			}),

			createStyledButton({
				text = function()
					return `Fly  {if self.fly() then "On" else "Off"}`
				end,
				onClick = function()
					self.fly(not self.fly())
				end,
				isPrimary = self.fly,
				isDanger = false,
				disabled = function()
					return false
				end,
				width = UDim.new(0.5, -4),
				height = 34,
			}, paletteSource),

			createStyledButton({
				text = function()
					return `Noclip  {if self.noclip() then "On" else "Off"}`
				end,
				onClick = function()
					self.noclip(not self.noclip())
				end,
				isPrimary = self.noclip,
				isDanger = false,
				disabled = function()
					return false
				end,
				width = UDim.new(0.5, -4),
				height = 34,
			}, paletteSource),
		}),

		createCheckbox("Click to Teleport (Ctrl + Click)", self.clickToTeleport, paletteSource),
	})
end

--[[
	@name buildEmotesTab
	@arch client

	@desc Builds Emotes tab with user-equipped emotes in upper section and default emotes in lower section.

	@param self Self Widget instance.
	@param paletteSource vide.Source<Palette>
	@returns Instance Frame containing Emotes tab.
	@raises nil
]]
local function buildEmotesTab(self: Self, paletteSource: vide.Source<Palette>): Instance
	const create = vide.create

	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		create("UIListLayout")({
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		vide.show(function()
			return self.activeEmoteName() ~= nil
		end, function()
			return createStyledButton({
				text = function()
					return `Stop Emote ({self.activeEmoteName() or ""})`
				end,
				onClick = function()
					if self.onStopEmoteCallback then
						self.onStopEmoteCallback()
					end
				end,
				isPrimary = false,
				isDanger = true,
				disabled = function()
					return not self.isPlaying()
				end,
				height = 32,
			}, paletteSource)
		end),

		create("TextLabel")({
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Text = "Equipped / Owned Emotes",
			TextSize = 12,
			TextColor3 = function()
				return paletteSource().dim
			end,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		create("Frame")({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			create("UIListLayout")({
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			vide.values(self.userEmotes, function(emote: EmoteDefinition)
				return createStyledButton({
					text = emote.name,
					onClick = function()
						if self.onPlayEmoteCallback then
							self.onPlayEmoteCallback(emote)
						end
					end,
					isPrimary = false,
					isDanger = false,
					disabled = function()
						return not self.isPlaying()
					end,
					height = 30,
				}, paletteSource)
			end),
		}),

		create("TextLabel")({
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansBold,
			Text = "Default Emotes",
			TextSize = 12,
			TextColor3 = function()
				return paletteSource().dim
			end,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		create("Frame")({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			create("UIGridLayout")({
				CellPadding = UDim2.fromOffset(6, 6),
				CellSize = UDim2.new(0.5, -3, 0, 32),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			vide.values(self.defaultEmotes, function(emote: EmoteDefinition)
				return createStyledButton({
					text = emote.name,
					onClick = function()
						if self.onPlayEmoteCallback then
							self.onPlayEmoteCallback(emote)
						end
					end,
					isPrimary = false,
					isDanger = false,
					disabled = function()
						return not self.isPlaying()
					end,
					height = 32,
				}, paletteSource)
			end),
		}),
	})
end

--[[
	@name buildCreditsTab
	@arch client

	@desc Builds Credits & Attribution tab listing utilized open-source libraries and algorithms.

	@param paletteSource vide.Source<Palette>
	@returns Instance Frame containing Credits tab.
	@raises nil
]]
local function buildCreditsTab(paletteSource: vide.Source<Palette>): Instance
	const create = vide.create

	const credits = {
		{
			title = "Chickynoid (MIT)",
			desc = "Kinematic swept collision & stair step physics.",
		},
		{
			title = "Vide (MIT)",
			desc = "Reactive UI library with fine-grained spring animations.",
		},
		{
			title = "Play in Studio (Chrythm)",
			desc = "Workflow inspiration.",
		},
		{
			title = "Quick Playtest",
			desc = "Created by checcerr.",
		},
	}

	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		create("UIListLayout")({
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),

		vide.values(vide.source(credits), function(item)
			return create("Frame")({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = function()
					return paletteSource().surface
				end,
				BorderSizePixel = 0,

				create("UIPadding")({
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),
				create("UICorner")({
					CornerRadius = UDim.new(0, 6),
				}),
				create("UIStroke")({
					Thickness = 1,
					Color = function()
						return paletteSource().border
					end,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				create("UIListLayout")({
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				create("TextLabel")({
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSansBold,
					Text = item.title,
					TextSize = 13,
					TextColor3 = function()
						return paletteSource().text
					end,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				create("TextLabel")({
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSans,
					Text = item.desc,
					TextSize = 12,
					TextColor3 = function()
						return paletteSource().dim
					end,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		end),
	})
end

--[[
	@name new
	@arch client

	@desc Constructs and mounts the Quick Playtest dock widget and Vide reactive hierarchy.

	@param pluginInstance Plugin Studio plugin instance.
	@returns Self Initialized Widget instance.
	@raises nil
]]
function Widget.new(pluginInstance: Plugin): Self
	const toolbar = pluginInstance:CreateToolbar("Quick Playtest")
	const toolbarButton =
		toolbar:CreateButton("QuickPlaytest", "Toggle Quick Playtest", Constants.ICON_ID, "Quick Playtest")
	toolbarButton.ClickableWhenViewportHidden = true

	const info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 420, 260, 300)
	const gui = pluginInstance:CreateDockWidgetPluginGuiAsync("QuickPlaytestWidgetV4", info)
	gui.Name = "QuickPlaytestWidget"
	gui.Title = "Quick Playtest"

	const isPlaying = vide.source(false)
	const isR15 = vide.source(true)
	const activeTab = vide.source("Main")
	const walkSpeed = vide.source("16")
	const jumpPower = vide.source("50")
	const maxSlopeAngle = vide.source("55")
	const includeGravity = vide.source(true)
	const fly = vide.source(false)
	const noclip = vide.source(false)
	const clickToTeleport = vide.source(false)
	const activeEmoteName = vide.source(nil :: string?)
	const userEmotes = vide.source({} :: { EmoteDefinition })
	const defaultEmotes = vide.source(vide.read(function()
		local list: { EmoteDefinition } = {}
		for _, e in Constants.DEFAULT_EMOTES do
			table.insert(list, e)
		end
		table.sort(list, function(a, b)
			return a.name < b.name
		end)
		return list
	end))

	const palette = vide.source(getPalette())

	const self: Self = setmetatable({
		toolbar = toolbar,
		toolbarButton = toolbarButton,
		gui = gui,
		destroyRoot = function() end,
		isPlaying = isPlaying,
		isR15 = isR15,
		activeTab = activeTab,
		walkSpeed = walkSpeed,
		jumpPower = jumpPower,
		maxSlopeAngle = maxSlopeAngle,
		includeGravity = includeGravity,
		fly = fly,
		noclip = noclip,
		clickToTeleport = clickToTeleport,
		activeEmoteName = activeEmoteName,
		userEmotes = userEmotes,
		defaultEmotes = defaultEmotes,
		onSpawnpointCallback = nil,
		onSpawnCameraCallback = nil,
		onStopCallback = nil,
		onPlayEmoteCallback = nil,
		onStopEmoteCallback = nil,
		connections = {},
	}, Widget) :: any

	table.insert(
		self.connections,
		toolbarButton.Click:Connect(function()
			gui.Enabled = not gui.Enabled
		end)
	)

	table.insert(
		self.connections,
		settings().Studio.ThemeChanged:Connect(function()
			palette(getPalette())
		end)
	)

	const destroyRoot = vide.root(function()
		const create = vide.create

		const rootFrame = create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return palette().background
			end,

			create("UIPadding")({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			}),

			create("UIListLayout")({
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- Top bar with title and config button (strictly non-overlapping)
			create("Frame")({
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 1,

				create("TextLabel")({
					Position = UDim2.new(0, 0, 0, 0),
					Size = UDim2.new(1, -78, 1, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = Enum.Font.BuilderSansBold,
					Text = "Quick Playtest",
					TextSize = 16,
					TextColor3 = function()
						return palette().text
					end,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				createStyledButton({
					text = "Config",
					onClick = function()
						Config.openConfig(pluginInstance)
					end,
					isPrimary = false,
					isDanger = false,
					disabled = function()
						return false
					end,
					position = UDim2.new(1, -72, 0, 1),
					width = UDim.new(0, 72),
					height = 28,
				}, palette),
			}),

			-- Navigation Tabs Strip (Main = 1, Properties = 2, Emotes = 3, Credits = 4)
			create("Frame")({
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 2,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				table.unpack((function()
					local buttons = {}
					for _, tabInfo in TAB_ITEMS do
						const isSelected = function()
							return activeTab() == tabInfo.name
						end

						const targetTabColor = function(): Color3
							const pal = palette()
							return if isSelected() then pal.tabActive else pal.tabInactive
						end
						const animTabBg = vide.spring(targetTabColor, 0.18, 0.9)

						table.insert(
							buttons,
							create("TextButton")({
								Name = tabInfo.name,
								LayoutOrder = tabInfo.order,
								Size = UDim2.new(0.25, -3, 1, 0),
								BorderSizePixel = 0,
								AutoButtonColor = false,
								Font = Enum.Font.BuilderSansMedium,
								Text = tabInfo.name,
								TextSize = 12,
								TextColor3 = function()
									return if isSelected() then palette().accentText else palette().text
								end,
								BackgroundColor3 = animTabBg,

								Activated = function()
									activeTab(tabInfo.name)
								end,

								create("UICorner")({
									CornerRadius = UDim.new(0, 5),
								}),
								create("UIStroke")({
									Thickness = 1,
									Color = function()
										return if isSelected() then palette().accent else palette().border
									end,
									ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
								}),
							})
						)
					end
					return buttons
				end)()),
			}),

			-- Scrollable tab content container
			create("ScrollingFrame")({
				Size = UDim2.new(1, 0, 1, -82),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = function()
					return palette().dim
				end,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				LayoutOrder = 3,

				vide.switch(activeTab)({
					Main = function()
						return buildMainTab(self, palette)
					end,
					Properties = function()
						return buildPropertiesTab(self, palette)
					end,
					Emotes = function()
						return buildEmotesTab(self, palette)
					end,
					Credits = function()
						return buildCreditsTab(palette)
					end,
				}),
			}),
		})

		rootFrame.Parent = gui
	end)

	self.destroyRoot = destroyRoot
	return self
end

--[[
	@name GetRigType
	@arch client

	@desc Returns selected avatar rig type.

	@param self Self Widget instance.
	@returns Enum.HumanoidRigType Rig type enum.
	@raises nil
]]
function Widget.GetRigType(self: Self): Enum.HumanoidRigType
	return if self.isR15() then Enum.HumanoidRigType.R15 else Enum.HumanoidRigType.R6
end

--[[
	@name GetWalkSpeed
	@arch client

	@desc Returns parsed walk speed value.

	@param self Self Widget instance.
	@returns number Walk speed.
	@raises nil
]]
function Widget.GetWalkSpeed(self: Self): number
	return math.clamp(tonumber(self.walkSpeed()) or 16, 0, 250)
end

--[[
	@name GetJumpPower
	@arch client

	@desc Returns parsed jump power value.

	@param self Self Widget instance.
	@returns number Jump power.
	@raises nil
]]
function Widget.GetJumpPower(self: Self): number
	return math.clamp(tonumber(self.jumpPower()) or 50, 0, 300)
end

--[[
	@name GetMaxSlopeAngle
	@arch client

	@desc Returns parsed maximum slope angle.

	@param self Self Widget instance.
	@returns number Max slope angle in degrees.
	@raises nil
]]
function Widget.GetMaxSlopeAngle(self: Self): number
	return math.clamp(tonumber(self.maxSlopeAngle()) or 55, 0, 89)
end

--[[
	@name GetIncludeGravity
	@arch client

	@desc Returns whether gravity is enabled.

	@param self Self Widget instance.
	@returns boolean Gravity flag.
	@raises nil
]]
function Widget.GetIncludeGravity(self: Self): boolean
	return self.includeGravity()
end

--[[
	@name GetFly
	@arch client

	@desc Returns flight mode state.

	@param self Self Widget instance.
	@returns boolean Fly flag.
	@raises nil
]]
function Widget.GetFly(self: Self): boolean
	return self.fly()
end

--[[
	@name GetNoclip
	@arch client

	@desc Returns noclip mode state.

	@param self Self Widget instance.
	@returns boolean Noclip flag.
	@raises nil
]]
function Widget.GetNoclip(self: Self): boolean
	return self.noclip()
end

--[[
	@name GetClickToTeleport
	@arch client

	@desc Returns click-to-teleport toggle state.

	@param self Self Widget instance.
	@returns boolean Teleport toggle state.
	@raises nil
]]
function Widget.GetClickToTeleport(self: Self): boolean
	return self.clickToTeleport()
end

--[[
	@name SetPlaying
	@arch client

	@desc Updates UI playing state.

	@param self Self Widget instance.
	@param playing boolean Active playtest status.
	@returns nil
	@raises nil
]]
function Widget.SetPlaying(self: Self, playing: boolean)
	self.isPlaying(playing)
end

--[[
	@name SetActiveEmoteName
	@arch client

	@desc Updates active emote label in UI.

	@param self Self Widget instance.
	@param name string? Emote name.
	@returns nil
	@raises nil
]]
function Widget.SetActiveEmoteName(self: Self, name: string?)
	self.activeEmoteName(name)
end

--[[
	@name SetUserEmotes
	@arch client

	@desc Populates user emote list in Emotes tab.

	@param self Self Widget instance.
	@param emotes { EmoteDefinition } List of emotes.
	@returns nil
	@raises nil
]]
function Widget.SetUserEmotes(self: Self, emotes: { EmoteDefinition })
	self.userEmotes(emotes)
end

--[[
	@name OnSpawnpoint
	@arch client

	@desc Registers callback for Spawn at Spawnpoint button.

	@param self Self Widget instance.
	@param callback () -> () Callback function.
	@returns nil
	@raises nil
]]
function Widget.OnSpawnpoint(self: Self, callback: () -> ())
	self.onSpawnpointCallback = callback
end

--[[
	@name OnSpawnCamera
	@arch client

	@desc Registers callback for Spawn at Camera button.

	@param self Self Widget instance.
	@param callback () -> () Callback function.
	@returns nil
	@raises nil
]]
function Widget.OnSpawnCamera(self: Self, callback: () -> ())
	self.onSpawnCameraCallback = callback
end

--[[
	@name OnStop
	@arch client

	@desc Registers callback for Stop Session button.

	@param self Self Widget instance.
	@param callback () -> () Callback function.
	@returns nil
	@raises nil
]]
function Widget.OnStop(self: Self, callback: () -> ())
	self.onStopCallback = callback
end

--[[
	@name OnPlayEmote
	@arch client

	@desc Registers callback when user clicks an emote to play.

	@param self Self Widget instance.
	@param callback (EmoteDefinition) -> () Callback function.
	@returns nil
	@raises nil
]]
function Widget.OnPlayEmote(self: Self, callback: (EmoteDefinition) -> ())
	self.onPlayEmoteCallback = callback
end

--[[
	@name OnStopEmote
	@arch client

	@desc Registers callback when user stops active emote.

	@param self Self Widget instance.
	@param callback () -> () Callback function.
	@returns nil
	@raises nil
]]
function Widget.OnStopEmote(self: Self, callback: () -> ())
	self.onStopEmoteCallback = callback
end

--[[
	@name Destroy
	@arch client

	@desc Disconnects listeners and destroys dock widget.

	@param self Self Widget instance.
	@returns nil
	@raises nil
]]
function Widget.Destroy(self: Self)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.destroyRoot()
	self.gui:Destroy()
	self.toolbar:Destroy()
end

export type Controller = typeof(setmetatable({} :: Self, Widget))

return Widget

-- checcerr.
