--// Mosswake -> Studs RNG Loading Screen
--// LocalScript in ReplicatedFirst with the Loadscreen ScreenGui as a child.
--// While it's up, the LocalPlayer has the attribute LoadingScreen = true;
--// LoadingScreenDone = true when it's gone (Interface.waitForLoadingScreen),
--// so the intro, tutorial and pop-ups start after it instead of behind it.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

player:SetAttribute("LoadingScreen", true)

local loadScreen = script:WaitForChild("Loadscreen")
local canvasGroup = loadScreen:WaitForChild("CanvasGroup")
local content = canvasGroup:WaitForChild("Content")

local mosswakeLogo = content:WaitForChild("MosswakeLogo")
local studsLogo = content:WaitForChild("StudsRNGLogo")
local background = content:WaitForChild("Background")

local mosswakeGradient = content.MosswakeBackground.MosswakeGradient
local studsGradient = content.StudsBackground.StudsGradient

--// Configuration

local CONFIG = {
	MinimumLoadingTime = 2,
	LoadingTimeout = 30,

	MosswakeFadeIn = 0.9,
	MosswakeHold = 1.5,
	BrandTransition = 0.85,

	StudsSlamDuration = 0.65,
	PulseSpeed = 1.4,

	ExitDuration = 0.8,
	WipeDuration = 0.65,
}

--// Colours

local BLUE = Color3.fromRGB(35, 115, 255)
local PURPLE = Color3.fromRGB(155, 75, 255)

local RAINBOW = {
	Color3.fromRGB(35, 115, 255),
	Color3.fromRGB(0, 200, 255),
	Color3.fromRGB(50, 230, 160),
	Color3.fromRGB(255, 220, 65),
	Color3.fromRGB(255, 130, 65),
	Color3.fromRGB(255, 75, 150),
	Color3.fromRGB(155, 75, 255),
}

--// Initial state

loadScreen.Parent = playerGui

canvasGroup.GroupTransparency = 0

mosswakeLogo.ImageTransparency = 1
studsLogo.ImageTransparency = 1

background.ImageTransparency = 0.8

local mosswakeScale = mosswakeLogo:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
mosswakeScale.Parent = mosswakeLogo

local studsScale = studsLogo:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
studsScale.Parent = studsLogo

mosswakeScale.Scale = 0.95
studsScale.Scale = 0.2

--// Loading tracking

local loaded = game:IsLoaded()
local minimumTimeReached = false

local loadingStarted = os.clock()

ReplicatedFirst:RemoveDefaultLoadingScreen()

if not loaded then
	task.spawn(function()
		game.Loaded:Wait()
		loaded = true
	end)
end

task.spawn(function()
	task.wait(CONFIG.MinimumLoadingTime)
	minimumTimeReached = true
end)

--// Helpers

-- Creates and plays a tween.
local function tween(object, duration, properties, style, direction)
	local info = TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)

	local animation = TweenService:Create(object, info, properties)
	animation:Play()

	return animation
end

local function setLogoColour(logo, colour)
	logo.ImageColor3 = colour
end

local function setGradientColour(gradient, colour)
	if gradient then
		gradient.Color = ColorSequence.new(colour)
	end
end

--// Hide the CoreGui while loading, then put back exactly what was on.

local coreGuiWasEnabled = {}
for _, coreGuiType in Enum.CoreGuiType:GetEnumItems() do
	if coreGuiType ~= Enum.CoreGuiType.All then
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreGuiType)
		coreGuiWasEnabled[coreGuiType] = ok and enabled
	end
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

--// 1. Mosswake introduction

setLogoColour(mosswakeLogo, BLUE)

tween(mosswakeLogo, CONFIG.MosswakeFadeIn, {
	ImageTransparency = 0,
}).Completed:Wait()

tween(mosswakeScale, 0.8, {
	Scale = 1,
}, Enum.EasingStyle.Back).Completed:Wait()

task.wait(CONFIG.MosswakeHold)

--// 2. Rainbow transition

-- Mosswake fades away while the gradient
-- travels through the rainbow.

local colourStepDuration = CONFIG.BrandTransition / #RAINBOW

task.spawn(function()
	for _, colour in RAINBOW do
		setLogoColour(mosswakeLogo, colour)
		setLogoColour(studsLogo, colour)
		setGradientColour(mosswakeGradient, colour)
		setGradientColour(studsGradient, colour)

		task.wait(colourStepDuration)
	end
end)

tween(mosswakeLogo, CONFIG.BrandTransition, {
	ImageTransparency = 1,
}).Completed:Wait()

--// 3. Studs RNG slam

setLogoColour(studsLogo, PURPLE)

studsLogo.ImageTransparency = 0
studsScale.Scale = 0.2

-- Slam in with a strong overshoot.

tween(studsScale, CONFIG.StudsSlamDuration, {
	Scale = 1,
}, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Wait()

-- Settle on purple.

tween(studsLogo, 0.3, {
	ImageColor3 = PURPLE,
})

setGradientColour(studsGradient, PURPLE)

--// 4. Smooth loading pulse

local pulseRunning = true

task.spawn(function()
	while pulseRunning do
		tween(studsScale, CONFIG.PulseSpeed, {
			Scale = 1.045,
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()

		if not pulseRunning then
			break
		end

		tween(studsScale, CONFIG.PulseSpeed, {
			Scale = 0.98,
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
	end
end)

--// Wait for loading

while not (loaded and minimumTimeReached) do
	if os.clock() - loadingStarted >= CONFIG.LoadingTimeout then
		break
	end

	task.wait(0.1)
end

--// 5. Cinematic exit

pulseRunning = false

-- Bring the logo back to its normal size (this also cancels the pulse).

tween(studsScale, 0.15, {
	Scale = 1,
}).Completed:Wait()

-- Bounce upwards before zooming out.

tween(studsScale, 0.22, {
	Scale = 1.2,
}, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Wait()

-- Rapidly zoom away while fading.

tween(studsLogo, CONFIG.ExitDuration, {
	ImageTransparency = 1,
}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

tween(studsScale, CONFIG.ExitDuration, {
	Scale = 0.01,
}, Enum.EasingStyle.Exponential, Enum.EasingDirection.In).Completed:Wait()

--// 6. Frame wipe

-- Wipe the entire CanvasGroup upwards.

tween(canvasGroup, CONFIG.WipeDuration, {
	Position = UDim2.new(0, 0, -1.1, 0),
}, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut).Completed:Wait()

--// Cleanup

loadScreen:Destroy()

for coreGuiType, enabled in coreGuiWasEnabled do
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGuiType, enabled)
end

player:SetAttribute("LoadingScreenDone", true)
