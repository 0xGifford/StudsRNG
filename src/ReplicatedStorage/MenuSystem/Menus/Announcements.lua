--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/Announcements

	Shows admin announcements (AdminRemotes.Announcement) to every player: a
	banner slides down from the top, holds, and slides back up. Several in a
	row queue up.

	YOUR BANNER (optional) — a ScreenGui in StarterGui:
		Announcement (ScreenGui)   AnnouncementBanner = true
		    Duration = 6               seconds on screen       (attribute, optional)
		    Sound = "rbxassetid://…"   played on arrival        (attribute, optional)
		  Banner (Frame)           AnnouncementRole = "Banner"   what slides; its Studio
		                                                         position is where it rests
		    Title (TextLabel)      AnnouncementRole = "Title"    "ANNOUNCEMENT"
		    Text (TextLabel)       AnnouncementRole = "Text"     the message
		    Sender (TextLabel)     AnnouncementRole = "Sender"   "— Shane"
	Without one, a built-in banner is used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Announcements = {}

Announcements.DURATION = 6
Announcements.SLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
Announcements.LEAVE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local started = false
local queue = {}
local showing = false

-- ---------------------------------------------------------------- the banner

local function role(gui: Instance, name: string)
	for _, d in gui:GetDescendants() do
		if d:GetAttribute("AnnouncementRole") == name then
			return d
		end
	end
	return nil
end

local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function buildDefault(): ScreenGui
	local gui = make("ScreenGui", { Name = "Announcement", DisplayOrder = 950, IgnoreGuiInset = true, ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	gui:SetAttribute("AnnouncementBanner", true)
	gui:SetAttribute("BuiltIn", true)
	local banner = make("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(640, 96), BackgroundColor3 = Color3.fromRGB(28, 36, 44), BackgroundTransparency = 0.05 }, gui)
	banner:SetAttribute("AnnouncementRole", "Banner")
	-- Stud UI pill surface (#1C242C, #0A0C10 outline, soft blue inner line)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, banner)
	make("UIStroke", { Color = Color3.fromRGB(10, 12, 16), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, banner)
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, banner)
	local function label(name, props)
		local l = make("TextLabel", { Name = name, BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left }, banner)
		for k, v in props do
			l[k] = v
		end
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = (l.TextSize >= 16) and 2 or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
		l:SetAttribute("AnnouncementRole", name)
		return l
	end
	label("Title", { Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 196, 0),
		Text = "ANNOUNCEMENT" })
	label("Text", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 34), TextSize = 16, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	label("Sender", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(1, 0, 0, 16), TextSize = 13,
		TextColor3 = Color3.fromRGB(200, 215, 222), TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	return gui
end

local function bannerGui(): ScreenGui
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("ScreenGui") and g:GetAttribute("AnnouncementBanner") == true and not g:GetAttribute("BuiltIn") then
			return g
		end
	end
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g:GetAttribute("BuiltIn") and g:GetAttribute("AnnouncementBanner") then
			return g
		end
	end
	return buildDefault()
end

-- ---------------------------------------------------------------- showing

local function setText(el: Instance?, text: string)
	if el and (el:IsA("TextLabel") or el:IsA("TextButton")) then
		el.Text = text
	end
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local item = table.remove(queue, 1)
	local gui = bannerGui()
	gui.ResetOnSpawn = false
	local banner = role(gui, "Banner") or gui:FindFirstChildWhichIsA("GuiObject")
	if not banner then
		showing = false
		return
	end
	setText(role(gui, "Title"), item.title ~= "" and item.title or "ANNOUNCEMENT")
	setText(role(gui, "Text"), item.text)
	setText(role(gui, "Sender"), item.sender ~= "" and ("— " .. item.sender) or "")

	local home = banner:GetAttribute("AnnouncementHome")
	if typeof(home) ~= "UDim2" then
		home = banner.Position
		banner:SetAttribute("AnnouncementHome", home)
	end
	-- AbsoluteSize is real pixels; inside a ScaleScreen overlay an offset is
	-- worth fewer of them, so convert or the banner stops short of the edge.
	local factor = 1
	local ok, Scale = pcall(require, script.Parent.Scale)
	if ok and Scale.ScreenFactor then
		factor = Scale.ScreenFactor(banner)
	end
	local height = banner.AbsoluteSize.Y > 0 and banner.AbsoluteSize.Y / factor or 120
	local above = UDim2.new(home.X.Scale, home.X.Offset, 0, -height - 20)
	banner.Position = above
	gui.Enabled = true

	local sound = gui:GetAttribute("Sound")
	if type(sound) == "string" and sound ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = sound
		s.Volume = 0.6
		s.Parent = SoundService
		s:Play()
		s.Ended:Connect(function()
			s:Destroy()
		end)
	end

	TweenService:Create(banner, Announcements.SLIDE, { Position = home }):Play()
	task.delay(tonumber(gui:GetAttribute("Duration")) or Announcements.DURATION, function()
		local leave = TweenService:Create(banner, Announcements.LEAVE, { Position = above })
		leave:Play()
		leave.Completed:Wait()
		gui.Enabled = false
		banner.Position = home
		showing = false
		showNext()
	end)
end

function Announcements.Show(text: string, sender: string?, title: string?)
	table.insert(queue, { text = tostring(text), sender = tostring(sender or ""), title = tostring(title or "") })
	showNext()
end

function Announcements.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("AdminRemotes", 60)
		local event = folder and folder:WaitForChild("Announcement", 30)
		if not (event and event:IsA("RemoteEvent")) then
			warn("[Announcements] AdminRemotes.Announcement not found — is AdminServer running?")
			return
		end
		event.OnClientEvent:Connect(function(text, sender, title)
			Announcements.Show(text, sender, title)
		end)
		print("[Announcements] running")
	end)
end

return Announcements
