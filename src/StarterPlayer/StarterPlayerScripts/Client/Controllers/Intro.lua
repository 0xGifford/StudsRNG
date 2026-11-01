--[[

Intro
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Intro

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- First-join cinematic: letterbox, title, a camera flight over every zone
-- (farthest first, so new players see what they're working towards) and a
-- swoop down to their character. Plays once per account
-- (PlayerData.SeenIntro), skippable at any time. Intro.Finished fires when
-- it ends or is skipped (or straight away for returning players).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Zones = require(Shared.Zones)
local Signal = require(Shared.Util.Signal)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local ZoneAmbience = require(Controllers.ZoneAmbience)
local Interface = require(UI.Interface)
local Juice = require(UI.Juice)
local Roles = require(UI.Roles)

local Intro = {}

Intro.Finished = Signal.new() :: Signal.Signal<>

local SHOT_TIME = 3.2
local MAX_SHOTS = 5

local player = Players.LocalPlayer
local playing = false
local finished = false
local skipped = false

function Intro.isPlaying(): boolean
	return playing
end

function Intro.hasFinished(): boolean
	return finished
end

local function zoneCenter(def: Zones.ZoneDef): Vector3?
	local zone = Tags.forZone(Tags.Zone, def.Id)[1]
	if not zone then return nil end -- not streamed in yet
	local center = zone:GetAttribute(Tags.Attr.Center)
	if typeof(center) == "Vector3" then return center end
	local cframe = Tags.zoneBox(zone)
	return if cframe then cframe.Position else nil
end

local function finish()
	if finished then return end
	finished = true
	playing = false
	Intro.Finished:Fire()
end

local function play()
	playing = true
	local camera = workspace.CurrentCamera
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)

	-- Overlay: StarterGui.Intro (tools/ui/screens/Intro.luau), by IntroRole.
	local gui = Roles.gui("Intro")
	local bars: { GuiObject } = {}
	for _, d in gui:GetDescendants() do
		if d:GetAttribute("IntroRole") == "Bar" and d:IsA("GuiObject") then
			table.insert(bars, d)
			-- In from the edge it rests against.
			local top = d:GetAttribute("IntroBar") ~= "Bottom"
			local home = d.AnchorPoint
			d.AnchorPoint = Vector2.new(home.X, if top then 1 else 0)
			TweenService:Create(d, TweenInfo.new(0.8, Enum.EasingStyle.Quart), { AnchorPoint = home }):Play()
		end
	end
	local title = Roles.get(gui, "IntroRole", "Title") :: TextLabel
	local subtitle = Roles.get(gui, "IntroRole", "Subtitle") :: TextLabel
	local caption = Roles.get(gui, "IntroRole", "Caption") :: TextLabel
	caption.TextTransparency = 1
	gui.Enabled = true

	local skip = Roles.find(gui, "IntroRole", "Skip")
	if skip and skip:IsA("GuiButton") then
		skip.Activated:Connect(function()
			skipped = true
		end)
	end

	-- Hide the game UI while the camera flies.
	local hudWasEnabled = Interface.HUD.Enabled
	Interface.HUD.Enabled = false
	ZoneAmbience.Quiet = true
	camera.CameraType = Enum.CameraType.Scriptable

	local function pause(seconds: number)
		local deadline = os.clock() + seconds
		while os.clock() < deadline and not skipped do
			task.wait()
		end
	end

	-- A teaser: the last zone, a few spread between, then the first.
	local shots: { Zones.ZoneDef } = {}
	local count = math.min(MAX_SHOTS, #Zones.List)
	for k = count, 1, -1 do
		local i = if count == 1 then 1 else 1 + math.floor((k - 1) * (#Zones.List - 1) / (count - 1) + 0.5)
		table.insert(shots, Zones.List[i])
	end

	for index, def in shots do
		if skipped then break end
		local center = zoneCenter(def)
		if center then
			pcall(player.RequestStreamAroundAsync, player, center, 2)
			local side = if index % 2 == 0 then 1 else -1
			-- Inside the valley walls (and under the Cave's roof).
			local from = center + Vector3.new(side * 55, 34, -62)
			local to = center + Vector3.new(side * 22, 16, -34)
			camera.CFrame = CFrame.lookAt(from, center)
			TweenService:Create(camera, TweenInfo.new(SHOT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				CFrame = CFrame.lookAt(to, center + Vector3.new(0, 2, 0)),
			}):Play()
			ZoneAmbience.apply(def.Id, true)

			if index == 1 then
				-- Fade the title out over the first shot.
				task.delay(1.6, function()
					TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
					TweenService:Create(subtitle, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
				end)
			end
			local zoneModel = Tags.forZone(Tags.Zone, def.Id)[1]
			local zoneSubtitle = if zoneModel then Tags.string(zoneModel, "Subtitle") else nil
			caption.Text = if zoneSubtitle then `{string.upper(def.Name)} · {zoneSubtitle}` else string.upper(def.Name)
			caption.TextColor3 = def.Color
			caption.TextTransparency = 1
			TweenService:Create(caption, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
			pause(SHOT_TIME - 0.4)
			TweenService:Create(caption, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			pause(0.4)
		end
	end

	-- Swoop down behind the player.
	if not skipped and root and root:IsA("BasePart") then
		local behind = root.CFrame * CFrame.new(0, 6, 14)
		TweenService:Create(camera, TweenInfo.new(1.6, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), {
			CFrame = CFrame.lookAt(behind.Position, root.Position + Vector3.new(0, 2, 0)),
		}):Play()
		pause(1.6)
	end

	for _, bar in bars do
		TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quart), { BackgroundTransparency = 1 }):Play()
	end
	camera.CameraType = Enum.CameraType.Custom
	Interface.HUD.Enabled = hudWasEnabled
	ZoneAmbience.Quiet = false
	local currentZone = ZoneAmbience.current()
	ZoneAmbience.apply(currentZone or Zones.Default, true)
	task.delay(0.6, function()
		-- Played once a session: the overlay's tweened state never needs resetting.
		gui.Enabled = false
	end)

	Net.invoke("MarkIntroSeen")
	Juice.banner("WELCOME!", "Walk on the keys to start earning", Color3.fromRGB(255, 220, 90), 2)
	Juice.confetti(60)
	finish()
end

function Intro.start()
	Interface.setup()
	local function decide()
		if State.get("SeenIntro") == true then
			finish()
			return
		end
		-- After the loading screen, and give the map a moment to stream in
		-- around the camera's path.
		Interface.waitForLoadingScreen()
		task.wait(1.5)
		local ok, err = pcall(play)
		if not ok then
			warn("[Intro]", err)
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			Interface.HUD.Enabled = true
			ZoneAmbience.Quiet = false
			finish()
		end
	end
	if State.isReady() then
		decide()
	else
		State.Ready:Wait()
		decide()
	end
end

return Intro
