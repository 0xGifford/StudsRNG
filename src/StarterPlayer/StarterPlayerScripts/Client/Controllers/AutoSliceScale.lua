--!strict

--[[
AutoSliceScale v1.0.0

Description:
    Automatically scales the SliceScale of UI objects based on
    the player's viewport size.

Setup:
    1. (StudsRNG) Runs as a client controller; nothing to place.
    2. Tag each UI object with "Slice".
    3. Configure the "SliceScale" Attribute if needed.
    4. Set REFERENCE_WIDTH and REFERENCE_HEIGHT below to match
       the resolution used to design your UI.

    To find your current viewport resolution, run this in the
    Command Bar:

        print(workspace.CurrentCamera.ViewportSize)

    Use the X and Y values as your reference resolution.

Attributes:
    SliceScale (Number)    Base SliceScale. Default: 1

How it works:
    The system scales SliceScale proportionally to the viewport,
    using the reference resolution defined below.

Author: DeveloperPlaceBruno
License: MIT

Links:
    Itch.io  - https://developerplacebruno.itch.io/
    YouTube  - https://www.youtube.com/@DeveloperPlaceBruno
    Discord  - https://discord.gg/ZcJ3W7SD9u
]]

local CollectionService = game:GetService("CollectionService")

local COLLECTION_TAG = "Slice"

local REFERENCE_WIDTH = 980
local REFERENCE_HEIGHT = 570

local AutoSliceScale = {}

local function updateSliceScale(guiObject: GuiObject)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local baseScale = guiObject:GetAttribute("SliceScale") or 1

	if typeof(baseScale) ~= "number" then
		baseScale = 1
	end

	local viewportSize = camera.ViewportSize

	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return
	end

	local scaleX = viewportSize.X / REFERENCE_WIDTH
	local scaleY = viewportSize.Y / REFERENCE_HEIGHT

	local scale = math.min(scaleX, scaleY)

	-- SliceScale exists on ImageLabel / ImageButton (9-slice images).
	pcall(function()
		(guiObject :: any).SliceScale = baseScale * scale
	end)
end

local function updateAll()
	for _, object in CollectionService:GetTagged(COLLECTION_TAG) do
		if object:IsA("GuiObject") then
			updateSliceScale(object)
		end
	end
end

function AutoSliceScale.start()
	updateAll()

	CollectionService:GetInstanceAddedSignal(COLLECTION_TAG):Connect(function(instance)
		if instance:IsA("GuiObject") then
			updateSliceScale(instance)
		end
	end)

	-- The camera can be replaced (respawn, cutscenes): follow the current one.
	local watched: RBXScriptConnection? = nil
	local function watchCamera()
		if watched then
			watched:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			watched = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAll)
		end
		updateAll()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	-- A SliceScale attribute edited live re-applies.
	for _, object in CollectionService:GetTagged(COLLECTION_TAG) do
		object:GetAttributeChangedSignal("SliceScale"):Connect(function()
			if object:IsA("GuiObject") then
				updateSliceScale(object)
			end
		end)
	end
end

return AutoSliceScale
