--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/ViewportUtil

	What StudView and ZoneView share: a viewport's camera, its one shown
	model, framing a model of any size, the dark "not found yet" look, and
	slow spinning.

	Attributes (on the ViewportFrame, read by both components):
		ViewTurn        Vector3  degrees the model is turned (X, Y, Z)
		ViewSpin        number   degrees per second it spins about Y, 0 = still
		ViewSilhouette  boolean  draw it as a dark shape
		ViewSilhouetteColor  Color3  the shape's colour, default black
		ViewZoom        number   1 = framed snugly, 0.8 = a bit closer
]]

local RunService = game:GetService("RunService")

local ViewportUtil = {}

local SHOWN = "Shown" -- the name of the model / part a component puts in

-- The viewport's camera, made if it has none (a ViewportFrame needs one).
function ViewportUtil.camera(viewport: ViewportFrame): Camera
	local camera = viewport.CurrentCamera
	if camera and camera:IsDescendantOf(viewport) then
		return camera
	end
	local found = viewport:FindFirstChildOfClass("Camera")
	if not found then
		found = Instance.new("Camera")
		found.FieldOfView = 30
		found.CFrame = CFrame.lookAt(Vector3.new(0, 0, 3.4), Vector3.zero)
		found.Parent = viewport
	end
	viewport.CurrentCamera = found
	return found :: Camera
end

function ViewportUtil.clear(viewport: ViewportFrame)
	local old = viewport:FindFirstChild(SHOWN)
	if old then
		old:Destroy()
	end
end

-- Puts a Model in the viewport, replacing what was there, turned by
-- ViewTurn (or `turn`), and frames the camera so all of it shows.
function ViewportUtil.show(viewport: ViewportFrame, object: Instance, turn: Vector3?)
	ViewportUtil.clear(viewport)
	object.Name = SHOWN
	local angles = viewport:GetAttribute("ViewTurn")
	local degrees = if typeof(angles) == "Vector3" then angles else turn or Vector3.new(22, 38, 0)
	local rotation = CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))

	local cframe: CFrame, size: Vector3
	if object:IsA("Model") then
		cframe, size = object:GetBoundingBox()
		object:PivotTo(rotation * (cframe:Inverse() * object:GetPivot()))
	elseif object:IsA("BasePart") then
		size = object.Size
		object.CFrame = rotation
	else
		size = Vector3.one
	end
	object.Parent = viewport

	-- Framed so the whole thing fits whichever way it turns.
	local camera = ViewportUtil.camera(viewport)
	local radius = size.Magnitude / 2
	local zoom = viewport:GetAttribute("ViewZoom")
	local fit = if typeof(zoom) == "number" and zoom > 0 then zoom else 1
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * fit
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
	camera.Focus = CFrame.new()
end

function ViewportUtil.shown(viewport: ViewportFrame): Instance?
	return viewport:FindFirstChild(SHOWN)
end

-- The dark shape look (and back), keeping the designer's own image colour.
function ViewportUtil.silhouette(viewport: ViewportFrame, state: { [string]: any })
	if state.imageColor == nil then
		state.imageColor = viewport.ImageColor3
		state.imageTransparency = viewport.ImageTransparency
	end
	local on = viewport:GetAttribute("ViewSilhouette") == true
	local color = viewport:GetAttribute("ViewSilhouetteColor")
	viewport.ImageColor3 = if on then (if typeof(color) == "Color3" then color else Color3.new()) else state.imageColor
	viewport.ImageTransparency = if on then math.max(state.imageTransparency, 0.15) else state.imageTransparency
end

-- Spinning viewports: one loop for all of them. `move` turns the shown
-- object (StudView's studs are rigs moved by StudVisuals.place).
type Spin = { speed: number, move: ((object: Instance, turn: CFrame) -> ())? }
local spinning: { [ViewportFrame]: Spin } = setmetatable({}, { __mode = "k" }) :: any
local spinLoop: RBXScriptConnection? = nil

local function turnObject(object: Instance, turn: CFrame)
	if object:IsA("Model") then
		object:PivotTo(turn * object:GetPivot())
	elseif object:IsA("BasePart") then
		object.CFrame = turn * object.CFrame
	end
end

function ViewportUtil.spin(viewport: ViewportFrame, move: ((object: Instance, turn: CFrame) -> ())?)
	local speed = viewport:GetAttribute("ViewSpin")
	if typeof(speed) == "number" and speed ~= 0 then
		spinning[viewport] = { speed = speed, move = move }
	else
		spinning[viewport] = nil
		return
	end
	if spinLoop then return end
	spinLoop = RunService.RenderStepped:Connect(function(dt)
		local any = false
		for view, spin in spinning do
			any = true
			local object = view.Parent and view.Visible and ViewportUtil.shown(view)
			if object then
				local turn = CFrame.Angles(0, math.rad(spin.speed * dt), 0);
				(spin.move or turnObject)(object, turn)
			end
		end
		if not any and spinLoop then
			spinLoop:Disconnect()
			spinLoop = nil
		end
	end)
end

function ViewportUtil.stopSpin(viewport: ViewportFrame)
	spinning[viewport] = nil
end

ViewportUtil.SHOWN = SHOWN

return ViewportUtil
