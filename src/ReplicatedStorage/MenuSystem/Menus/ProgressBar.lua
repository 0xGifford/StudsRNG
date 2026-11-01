--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/ProgressBar

	A bar's fill that sizes itself from one attribute.

		Fill (Frame)   Progress = 0.4

	ATTRIBUTES
		Progress        number   0 to 1 (clamped); the marker
		ProgressAxis    string   "X" (default) or "Y"
		ProgressTween   number   seconds to slide to a new value, default 0.25,
		                         0 = instant
	Only the axis's scale changes; the other axis and any offsets stay as
	you designed them.

	API
		ProgressBar.Start()
		ProgressBar.Set(fill, { Progress = 0.5 })
]]

local TweenService = game:GetService("TweenService")

local Component = require(script.Parent.Component)

local function render(fill: GuiObject, state: { [string]: any })
	local value = fill:GetAttribute("Progress")
	local share = math.clamp(if typeof(value) == "number" then value else 0, 0, 1)
	local size = fill.Size
	local target = if fill:GetAttribute("ProgressAxis") == "Y"
		then UDim2.new(size.X.Scale, size.X.Offset, share, size.Y.Offset)
		else UDim2.new(share, size.X.Offset, size.Y.Scale, size.Y.Offset)
	local time = fill:GetAttribute("ProgressTween")
	local seconds = if typeof(time) == "number" then time else 0.25
	if state.tween then
		state.tween:Cancel()
		state.tween = nil
	end
	-- The first draw snaps: a bar shouldn't slide in from its design size.
	if seconds <= 0 or not state.drawn then
		fill.Size = target
	else
		state.tween = TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = target })
		state.tween:Play()
	end
	state.drawn = true
end

return Component.new({
	Marker = "Progress",
	Watch = { "ProgressAxis", "ProgressTween" },
	Class = "GuiObject",
	Render = render,
	Cleanup = function(_, state)
		if state.tween then
			state.tween:Cancel()
		end
	end,
})
