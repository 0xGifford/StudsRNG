--!strict
-- Single responsibility: own a mouse drag once it has started, until the
-- button is released — wherever the cursor wanders in the meantime.
--
-- Why this does NOT use UserInputService, having twice tried to:
-- UserInputService is deaf inside a plugin widget. It only reports input
-- while the main Studio window has focus, so the instant the cursor is over a
-- DockWidgetPluginGui its InputChanged stops firing entirely. That is exactly
-- the "click sets the value, holding does nothing" symptom: InputBegan on the
-- control started the drag (GuiObject signals DO work in a widget), and the
-- UserInputService follow-up that was supposed to continue it never arrived.
--
-- The only API that reports the cursor inside a plugin widget is
-- PluginGui:GetRelativeMousePosition(), and it is a poll, not an event — so
-- the drag is driven from a Heartbeat loop instead. It returns a position
-- relative to the widget's top-left, which is the same space as the
-- AbsolutePosition of anything inside that widget, so callers can subtract
-- one from the other directly. It keeps reporting once the cursor leaves the
-- control, which is the whole point.
--
-- Ending the drag is the part that took three tries. What works is the
-- ORIGINATING InputObject: it reports its own end through Changed, whatever
-- the cursor happens to be over by then. That signal is carried by the input
-- itself instead of being routed, which is why it survives in here when the
-- other two candidates do not:
--   * GuiObject.InputEnded is delivered by hit-testing, so it goes to
--     whatever sits under the cursor at release time, not to the control the
--     drag started on;
--   * UserInputService.InputEnded is simply never delivered over the widget,
--     for the same reason InputChanged is not.
-- Both are still connected as belt-and-braces, and IsMouseButtonPressed is
-- kept as a last-resort latch-breaker — but only believed once it has been
-- seen to report a pressed button at least once during this drag, since a
-- service that cannot see the button would otherwise cancel on frame one.
-- Relying on those three alone was the "the slider keeps following the mouse
-- until I click again" bug: nothing ever fired, and the next InputBegan was
-- what finally released the previous drag.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DragCapture = {}

local SOAK_NAME = "KeyCapperDragSoak"

local onMove: ((Vector2) -> ())? = nil
local onEnd: (() -> ())? = nil
local connections: { RBXScriptConnection } = {}
local soak: Frame? = nil
-- See the header: the button state only becomes an authority once it has
-- proven it can see the button at all.
local sawPressed = false

local function pluginGuiOf(gui: Instance): PluginGui?
	local node: Instance? = gui
	while node do
		if node:IsA("PluginGui") then return node :: PluginGui end
		node = node.Parent
	end
	return nil
end

-- One reusable full-widget frame, hidden between drags. Active is what makes
-- a fully transparent frame hit-testable at all; ZIndex puts it above the
-- popup overlay so it is what sits under the cursor for the whole drag.
local function ensureSoak(pluginGui: PluginGui): Frame
	local existing = pluginGui:FindFirstChild(SOAK_NAME)
	if existing then return existing :: Frame end

	local frame = Instance.new("Frame")
	frame.Name = SOAK_NAME
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Active = true
	frame.ZIndex = 100
	frame.Parent = pluginGui
	return frame
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
end

function DragCapture.Release()
	if not onMove and not onEnd then return end
	disconnectAll()

	if soak then
		soak.Visible = false
		soak = nil
	end
	sawPressed = false

	local finish = onEnd
	onMove, onEnd = nil, nil
	if finish then finish() end
end

function DragCapture.IsActive(): boolean
	return onMove ~= nil
end

-- anchor: any GuiObject inside the widget the drag belongs to — used only to
-- find the PluginGui to poll. input: the InputObject from the InputBegan that
-- started the drag, which is what actually reports the release. move: called
-- every frame with the cursor position relative to that widget. finish:
-- called once on release.
function DragCapture.Begin(
	anchor: GuiObject,
	input: InputObject,
	move: (Vector2) -> (),
	finish: (() -> ())?
)
	if onMove then
		DragCapture.Release()
	end

	local pluginGui = pluginGuiOf(anchor)
	if not pluginGui then return end

	onMove, onEnd = move, finish
	sawPressed = false

	local layer = ensureSoak(pluginGui)
	layer.Visible = true
	soak = layer

	table.insert(connections, RunService.Heartbeat:Connect(function()
		if not onMove then return end

		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			sawPressed = true
		elseif sawPressed then
			-- It saw the press and now sees the release: trustworthy here.
			DragCapture.Release()
			return
		end

		onMove(pluginGui:GetRelativeMousePosition())
	end))

	-- The one that actually fires in a widget. See the header.
	table.insert(connections, input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			DragCapture.Release()
		end
	end))

	table.insert(connections, layer.InputEnded:Connect(function(ended)
		if ended.UserInputType == Enum.UserInputType.MouseButton1 then
			DragCapture.Release()
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(ended)
		if ended.UserInputType == Enum.UserInputType.MouseButton1 then
			DragCapture.Release()
		end
	end))
end

return DragCapture
