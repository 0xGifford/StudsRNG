--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/AdminPanel

	The admin menu, built from ReplicatedStorage.Shared.AdminConfig (the server
	side is ServerScriptService Systems/Admin). Add a tab,
	category, field or action there and it appears here — nothing to wire.
	For anyone who isn't an admin (the server sets IsAdmin) every ScreenGui
	with AdminOnly = true is deleted on arrival; the server re-checks every
	request anyway.

	THE SCREENGUI  (a normal menu: MenuPanel, MenuKey = "F2", AdminOnly = true)
	  AdminRole = "Tabs"            where tab buttons go (with a UIListLayout)
	  AdminRole = "Pages"           where pages go
	  AdminRole = "PlayerList"      the player list (with a UIListLayout)
	  AdminRole = "SelectAll" / "SelectNone" / "SelectMe"   buttons
	  AdminRole = "SelectionCount"  "3 selected"
	  AdminRole = "Search"          a TextBox that filters the list
	  AdminRole = "Status"          the last result
	  AdminField = Name | DisplayName | UserId | Coins | ... | Avatar
	                                the first selected player's details

	TEMPLATES  (anywhere in the ScreenGui, AdminTemplate = <name>, hidden)
	  Tab       a button; text on it or a "Label" child; optional "Indicator"
	            (ActiveColor / IdleColor attributes tint it)
	  Page      a ScrollingFrame (with a UIListLayout) for one tab
	  Category  "Title" (TextLabel) + "Body" (Frame with a layout)
	  Number    "Label" + "Box" (TextBox)
	  Text      "Label" + "Box" (TextBox)
	  Checkbox  "Label" + "Box" (button) + "Tick" (shown when on)
	            (OnColor / OffColor attributes tint the Box)
	  Switch    "Label" + "Track" (button) + "Knob" inside it
	            (OnColor / OffColor attributes tint the Track)
	  Select    "Label" + "Value" (button showing the choice) + "List" (frame,
	            hidden) holding one "Option" button to copy per choice
	  Button    a button; text on it or a "Label" child
	            (Danger = true actions use its DangerColor attribute)
	  PlayerRow a row: "Avatar", "Name", "Info", "Check" (shown when selected)
	            (SelectedColor / IdleColor attributes tint the row)
	  LogLine   a TextLabel per log line (the Log tab)
	  Everything built gets Selected / On / Danger attributes for styling.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)

local player = Players.LocalPlayer

local AdminPanel = {}

AdminPanel.REFRESH = 2
AdminPanel.CONFIRM_TIME = 3
AdminPanel.ON = Color3.fromRGB(70, 190, 110)
AdminPanel.OFF = Color3.fromRGB(80, 80, 92)
AdminPanel.OK = Color3.fromRGB(110, 230, 120)
AdminPanel.ERROR = Color3.fromRGB(255, 100, 100)

local QUICK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local started = false

-- ================================================================ helpers

local function ask(request)
	local folder = ReplicatedStorage:FindFirstChild("AdminRemotes")
	local r = folder and folder:FindFirstChild("Admin")
	if not (r and r:IsA("RemoteFunction")) then
		return { ok = false, message = "Admin server not running" }
	end
	local ok, result = pcall(function()
		return r:InvokeServer(request)
	end)
	return (ok and type(result) == "table") and result or { ok = false, message = "No reply" }
end

local function tween(inst: Instance, info: TweenInfo, goal)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function scaleOf(inst: GuiObject): UIScale
	local s = inst:FindFirstChild("AdminScale")
	if not (s and s:IsA("UIScale")) then
		s = Instance.new("UIScale")
		s.Name = "AdminScale"
		s.Parent = inst
	end
	return s
end

--- A small "here I am" bounce.
local function pop(inst: GuiObject, from: number?)
	local s = scaleOf(inst)
	s.Scale = from or 0.85
	tween(s, POP, { Scale = 1 })
end

local function child(inst: Instance, name: string): Instance?
	return inst:FindFirstChild(name, true)
end

local function setText(inst: Instance?, text: string)
	if not inst then
		return
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = text
	end
end

--- The text a button shows: on the button, or on its "Label".
local function label(button: Instance): Instance?
	local l = button:FindFirstChild("Label", true)
	if l then
		return l
	end
	return (button:IsA("TextButton") or button:IsA("TextLabel")) and button or nil
end

local function colourAttr(inst: Instance, name: string, fallback: Color3): Color3
	local v = inst:GetAttribute(name)
	return typeof(v) == "Color3" and v or fallback
end

local function commas(n: any): string
	if type(n) ~= "number" then
		return tostring(n == nil and "—" or n)
	end
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local FORMAT = {
	AccountAge = function(v) return type(v) == "number" and (commas(v) .. " days") or "—" end,
	UserId = function(v) return tostring(v or "—") end,
	Name = function(v) return v and ("@" .. v) or "—" end,
	DisplayName = function(v) return tostring(v or "—") end,
	Role = function(v) return tostring(v or "Player") end,
	BestRoll = function(v) return type(v) == "number" and v > 0 and ("1 in " .. commas(v)) or "—" end,
}

-- ================================================================ one panel

local function bind(gui: ScreenGui)
	-- the parts and templates this ScreenGui provides
	local roles, fields, templates = {}, {}, {}
	for _, d in gui:GetDescendants() do
		local role = d:GetAttribute("AdminRole")
		if type(role) == "string" then
			roles[role] = roles[role] or d
		end
		local field = d:GetAttribute("AdminField")
		if type(field) == "string" then
			fields[field] = fields[field] or {}
			table.insert(fields[field], d)
		end
		local t = d:GetAttribute("AdminTemplate")
		if type(t) == "string" and d:IsA("GuiObject") then
			templates[t] = d
			d.Visible = false
		end
	end
	local function make(name: string): GuiObject?
		local t = templates[name]
		if not t then
			warn("[AdminPanel] no template with AdminTemplate = \"" .. name .. "\"")
			return nil
		end
		local c = t:Clone()
		c:SetAttribute("AdminTemplate", nil)
		c.Visible = true
		return c
	end

	local selected, order = {}, {}       -- [userId] = true, and selection order
	local values = {}                    -- [categoryKey] = { [fieldId] = value }
	local switches = {}                  -- { set, bind }
	local rows = {}                      -- [userId] = row
	local pages, tabButtons = {}, {}
	local logPage, current = nil, nil
	local refreshInspect, refreshLog

	-- ------------------------------------------------ status
	local function status(text: string, ok: boolean)
		local s = roles.Status
		if not s then
			return
		end
		setText(s, text)
		if s:IsA("TextLabel") then
			s.TextColor3 = ok and AdminPanel.OK or AdminPanel.ERROR
			s.TextTransparency = 1
			tween(s, QUICK, { TextTransparency = 0 })
		end
		pop(s, 0.92)
	end

	local function flash(button: GuiObject, ok: boolean)
		local base = button.BackgroundColor3
		button.BackgroundColor3 = ok and AdminPanel.OK or AdminPanel.ERROR
		tween(button, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundColor3 = base })
		pop(button, ok and 1.08 or 0.92)
	end

	-- ------------------------------------------------ selection
	local function selectionList()
		local list = {}
		for _, id in order do
			if selected[id] then
				table.insert(list, id)
			end
		end
		return list
	end

	local function paintRow(row: GuiObject, on: boolean)
		row:SetAttribute("Selected", on)
		tween(row, QUICK, { BackgroundColor3 = on and colourAttr(row, "SelectedColor", Color3.fromRGB(90, 110, 200))
			or colourAttr(row, "IdleColor", Color3.fromRGB(80, 80, 92)) })
		local check = child(row, "Check")
		if check and check:IsA("GuiObject") then
			check.Visible = on
			if on then
				pop(check, 0.4)
			end
		end
	end

	local function selectionChanged()
		local list = selectionList()
		setText(roles.SelectionCount, #list == 0 and "No one selected" or (#list == 1 and "1 selected" or (#list .. " selected")))
		for id, row in rows do
			if (row:GetAttribute("Selected") == true) ~= (selected[id] == true) then
				paintRow(row, selected[id] == true)
			end
		end
		refreshInspect()
	end

	--- In `order` at most once, and only while selected: a player ticked,
	--- unticked and ticked again was being counted (and acted on) twice.
	local function setSelected(id: number, on: boolean)
		local at = table.find(order, id)
		if on then
			if not at then
				table.insert(order, id)
			end
			selected[id] = true
		else
			if at then
				table.remove(order, at)
			end
			selected[id] = nil
		end
	end

	local function refreshList()
		local list = roles.PlayerList
		local template = templates.PlayerRow
		if not (list and template) then
			return
		end
		local result = ask({ Action = "List" })
		if not result.ok then
			return
		end
		local search = roles.Search and roles.Search:IsA("TextBox") and roles.Search.Text:lower() or ""
		local seen = {}
		for i, entry in result.data do
			seen[entry.UserId] = true
			local row = rows[entry.UserId]
			if not row then
				row = make("PlayerRow")
				if not row then
					return
				end
				row.Name = "Row_" .. entry.UserId
				local avatar = child(row, "Avatar")
				if avatar and (avatar:IsA("ImageLabel") or avatar:IsA("ImageButton")) then
					avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(entry.UserId)
				end
				setText(child(row, "Name"), ("%s (@%s)"):format(entry.DisplayName, entry.Name))
				setText(child(row, "Info"), tostring(entry.UserId) .. (entry.IsAdmin and " · ADMIN" or ""))
				local button = row:IsA("GuiButton") and row or nil
				if not button then
					button = Instance.new("TextButton")
					button.Name = "Hit"
					button.Size = UDim2.fromScale(1, 1)
					button.BackgroundTransparency = 1
					button.Text = ""
					button.ZIndex = 50
					button.Parent = row
				end
				local id = entry.UserId
				button.Activated:Connect(function()
					setSelected(id, not selected[id])
					selectionChanged()
				end)
				row.Parent = list
				rows[id] = row
				paintRow(row, selected[id] == true)
				pop(row, 0.9)
			end
			row.LayoutOrder = i
			local match = search == "" or entry.Name:lower():find(search, 1, true) or entry.DisplayName:lower():find(search, 1, true)
				or tostring(entry.UserId):find(search, 1, true)
			row.Visible = match and true or false
		end
		local changed = false
		for id, row in rows do
			if not seen[id] then
				row:Destroy()
				rows[id] = nil
				if selected[id] then
					setSelected(id, false)
					changed = true
				end
			end
		end
		if changed then
			selectionChanged()
		end
	end

	-- ------------------------------------------------ the inspected player
	local lastData, lastId = nil, nil
	refreshInspect = function()
		local first = selectionList()[1]
		local data = nil
		if first then
			local result = ask({ Action = "Inspect", Target = first })
			if result.ok then
				data = result.data
				lastData, lastId = data, first
			elseif lastId == first then
				data = lastData -- a failed lookup keeps what we had, rather than blanking it
			end
		else
			lastData, lastId = nil, nil
		end
		for field, list in fields do
			for _, el in list do
				if field == "Avatar" then
					if el:IsA("ImageLabel") or el:IsA("ImageButton") then
						el.Image = data and ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(data.UserId) or ""
					end
				else
					local fmt = FORMAT[field]
					setText(el, data and (fmt and fmt(data[field]) or commas(data[field])) or "—")
				end
			end
		end
		for _, s in switches do
			if s.bind then
				s.set(data ~= nil and data[s.bind] == true, true)
			end
		end
	end

	-- ------------------------------------------------ fields
	local FIELD = {}

	FIELD.Number = function(f, store)
		local el = make("Number")
		if not el then return end
		setText(child(el, "Label"), f.Text or f.Id)
		local box = child(el, "Box")
		if box and box:IsA("TextBox") then
			box.Text = f.Default and tostring(f.Default) or ""
			box.PlaceholderText = f.Placeholder or (f.Optional and "optional" or ("%s – %s"):format(commas(f.Min or 0), commas(f.Max or 0)))
			store[f.Id] = f.Default
			box.FocusLost:Connect(function()
				local n = tonumber(box.Text)
				if box.Text == "" and f.Optional then
					store[f.Id] = nil
					return
				end
				if not n or (f.Min and n < f.Min) or (f.Max and n > f.Max) then
					box.Text = store[f.Id] and tostring(store[f.Id]) or ""
					flash(box, false)
					return
				end
				store[f.Id] = math.floor(n)
				box.Text = tostring(store[f.Id])
			end)
		end
		return el
	end

	FIELD.Text = function(f, store)
		local el = make("Text")
		if not el then return end
		setText(child(el, "Label"), f.Text or f.Id)
		local box = child(el, "Box")
		if box and box:IsA("TextBox") then
			box.Text = f.Default or ""
			box.PlaceholderText = f.Placeholder or ""
			box.MultiLine = f.Multiline == true
			box.TextWrapped = f.Multiline == true
			box.ClearTextOnFocus = false
			store[f.Id] = box.Text
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if #box.Text > (f.MaxLength or 200) then
					box.Text = box.Text:sub(1, f.MaxLength or 200)
				end
				store[f.Id] = box.Text
			end)
		end
		return el
	end

	FIELD.Checkbox = function(f, store)
		local el = make("Checkbox")
		if not el then return end
		setText(child(el, "Label"), f.Text or f.Id)
		local box, tick = child(el, "Box"), child(el, "Tick")
		local function set(on: boolean, quiet: boolean?)
			store[f.Id] = on
			el:SetAttribute("On", on)
			if tick and tick:IsA("GuiObject") then
				tick.Visible = on
				if on and not quiet then
					pop(tick, 0.3)
				end
			end
			if box and box:IsA("GuiObject") then
				tween(box, QUICK, { BackgroundColor3 = on and colourAttr(el, "OnColor", AdminPanel.ON) or colourAttr(el, "OffColor", AdminPanel.OFF) })
			end
		end
		set(f.Default == true, true)
		local hit = (box and box:IsA("GuiButton")) and box or (el:IsA("GuiButton") and el or nil)
		if hit then
			hit.Activated:Connect(function()
				set(not store[f.Id])
			end)
		end
		return el
	end

	FIELD.Select = function(f, store)
		local el = make("Select")
		if not el then return end
		setText(child(el, "Label"), f.Text or f.Id)
		local valueBtn, list = child(el, "Value"), child(el, "List")
		local optionT = list and list:FindFirstChild("Option")
		if optionT and optionT:IsA("GuiObject") then
			optionT.Visible = false
		end
		local function choose(v: string)
			store[f.Id] = v
			setText(label(valueBtn) or valueBtn, v)
		end
		choose(f.Default or (f.Options and f.Options[1]) or "")
		local open = false
		local function setOpen(on: boolean)
			open = on
			if not (list and list:IsA("GuiObject")) then
				return
			end
			if on then
				list.Visible = true
				pop(list, 0.85)
			else
				local s = scaleOf(list)
				local t = tween(s, QUICK, { Scale = 0.85 })
				t.Completed:Once(function()
					if not open then
						list.Visible = false
						s.Scale = 1
					end
				end)
			end
		end
		if list and optionT then
			for i, option in f.Options or {} do
				local o = optionT:Clone()
				o.Name = "Opt_" .. i
				o.LayoutOrder = i
				o.Visible = true
				setText(label(o) or o, option)
				if o:IsA("GuiButton") then
					o.Activated:Connect(function()
						choose(option)
						setOpen(false)
					end)
				end
				o.Parent = list
			end
			list.Visible = false
		end
		if valueBtn and valueBtn:IsA("GuiButton") then
			valueBtn.Activated:Connect(function()
				setOpen(not open)
			end)
		end
		return el
	end

	-- ------------------------------------------------ actions
	local function run(action, store, button: GuiObject?, extra)
		local args = table.clone(store)
		for k, v in extra or {} do
			args[k] = v
		end
		local result = ask({ Action = action.Id, Targets = selectionList(), Args = args })
		status(result.message or (result.ok and "Done" or "Failed"), result.ok == true)
		if button then
			flash(button, result.ok == true)
		end
		task.spawn(refreshInspect)
		task.spawn(refreshLog)
		return result.ok == true
	end

	local function actionButton(action, store)
		local el = make("Button")
		if not el then return end
		local text = label(el)
		setText(text, action.Text or action.Id)
		el:SetAttribute("Danger", action.Danger == true)
		if action.Danger then
			el.BackgroundColor3 = colourAttr(el, "DangerColor", Color3.fromRGB(190, 55, 55))
		end
		el:AddTag("Bounce")
		local armedAt = 0
		local button = el:IsA("GuiButton") and el or nil
		if button then
			button.Activated:Connect(function()
				if action.Confirm and os.clock() - armedAt > AdminPanel.CONFIRM_TIME then
					armedAt = os.clock()
					setText(text, "Sure?")
					pop(el, 1.1)
					task.delay(AdminPanel.CONFIRM_TIME, function()
						if os.clock() - armedAt >= AdminPanel.CONFIRM_TIME - 0.05 then
							setText(text, action.Text or action.Id)
						end
					end)
					return
				end
				armedAt = 0
				setText(text, action.Text or action.Id)
				run(action, store, el)
			end)
		end
		return el
	end

	local function actionSwitch(action, store)
		local el = make("Switch")
		if not el then return end
		setText(child(el, "Label"), action.Text or action.Id)
		local track, knob = child(el, "Track"), child(el, "Knob")
		local state = false
		local function set(on: boolean, quiet: boolean?)
			state = on
			el:SetAttribute("On", on)
			local info = quiet and TweenInfo.new(0) or TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if knob and knob:IsA("GuiObject") then
				knob.AnchorPoint = Vector2.new(0.5, 0.5)
				tween(knob, info, { Position = UDim2.fromScale(on and 0.75 or 0.25, 0.5) })
			end
			if track and track:IsA("GuiObject") then
				tween(track, QUICK, { BackgroundColor3 = on and colourAttr(el, "OnColor", AdminPanel.ON) or colourAttr(el, "OffColor", AdminPanel.OFF) })
			end
		end
		set(false, true)
		table.insert(switches, { set = set, bind = action.Bind })
		local hit = (track and track:IsA("GuiButton")) and track or (el:IsA("GuiButton") and el or nil)
		if hit then
			hit.Activated:Connect(function()
				local want = not state
				set(want)
				if not run(action, store, nil, { Value = want }) then
					set(not want) -- the server said no: put it back
				end
			end)
		end
		return el
	end

	-- ------------------------------------------------ pages and tabs
	local function cascade(page: GuiObject)
		local blocks = {}
		for _, c in page:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				table.insert(blocks, c)
			end
		end
		table.sort(blocks, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i, c in blocks do
			local s = scaleOf(c)
			s.Scale = 0.9
			task.delay((i - 1) * 0.045, function()
				tween(s, POP, { Scale = 1 })
			end)
		end
	end

	local function show(tabId: string)
		if current == tabId then
			return
		end
		current = tabId
		for id, page in pages do
			if id == tabId then
				page.Visible = true
				local home = page:GetAttribute("AdminHome")
				if typeof(home) ~= "UDim2" then
					home = page.Position
					page:SetAttribute("AdminHome", home)
				end
				page.Position = home + UDim2.fromOffset(24, 0)
				tween(page, SLIDE, { Position = home })
				cascade(page)
			else
				page.Visible = false
			end
		end
		for id, b in tabButtons do
			local on = id == tabId
			b:SetAttribute("Selected", on)
			tween(b, QUICK, { BackgroundColor3 = on and colourAttr(b, "ActiveColor", Color3.fromRGB(90, 110, 200))
				or colourAttr(b, "IdleColor", Color3.fromRGB(58, 58, 68)) })
			local indicator = child(b, "Indicator")
			if indicator and indicator:IsA("GuiObject") then
				indicator.Visible = on
				if on then
					pop(indicator, 0.3)
				end
			end
		end
		if pages[tabId] == logPage then
			task.spawn(refreshLog)
		end
	end

	refreshLog = function()
		if not (logPage and logPage.Visible and templates.LogLine) then
			return
		end
		local result = ask({ Action = "Log" })
		if not result.ok then
			return
		end
		for _, c in logPage:GetChildren() do
			if c:GetAttribute("AdminLogLine") then
				c:Destroy()
			end
		end
		for i, line in result.data do
			local l = make("LogLine")
			if not l then
				return
			end
			l.LayoutOrder = i
			l:SetAttribute("AdminLogLine", true)
			setText(l, line)
			l.Parent = logPage
		end
	end

	local tabsHolder, pagesHolder = roles.Tabs, roles.Pages
	if not (tabsHolder and pagesHolder) then
		warn("[AdminPanel] needs AdminRole = \"Tabs\" and AdminRole = \"Pages\"")
		return
	end
	for ti, tab in AdminConfig.TABS do
		local button = make("Tab")
		local page = make("Page")
		if not (button and page) then
			return
		end
		button.Name = "Tab_" .. tab.Id
		button.LayoutOrder = ti
		setText(label(button), tab.Text or tab.Id)
		button:AddTag("Bounce")
		button.Parent = tabsHolder
		tabButtons[tab.Id] = button
		if button:IsA("GuiButton") then
			button.Activated:Connect(function()
				show(tab.Id)
			end)
		end
		page.Name = "Page_" .. tab.Id
		page.Visible = false
		page.Parent = pagesHolder
		pages[tab.Id] = page
		if tab.Log then
			logPage = page
		end
		for ci, category in tab.Categories or {} do
			local block = make("Category")
			if not block then
				break
			end
			block.Name = "Cat_" .. ci
			block.LayoutOrder = ci
			setText(child(block, "Title"), category.Text or "")
			local body = child(block, "Body") or block
			local store = {}
			values[tab.Id .. "/" .. ci] = store
			local n = 0
			for _, f in category.Fields or {} do
				local builder = FIELD[f.Type]
				local el = builder and builder(f, store)
				if el then
					n += 1
					el.Name = "Field_" .. f.Id
					el.LayoutOrder = n
					el.Parent = body
				elseif not builder then
					warn("[AdminPanel] unknown field type: " .. tostring(f.Type))
				end
			end
			for _, action in category.Actions or {} do
				local el = action.Type == "Switch" and actionSwitch(action, store) or actionButton(action, store)
				if el then
					n += 1
					el.Name = "Action_" .. action.Id
					el.LayoutOrder = n
					el.Parent = body
				end
			end
			block.Parent = page
		end
	end

	-- selection buttons
	local function onClick(role: string, fn)
		local b = roles[role]
		if b and b:IsA("GuiButton") then
			b:AddTag("Bounce")
			b.Activated:Connect(fn)
		end
	end
	onClick("SelectAll", function()
		for id, row in rows do
			if row.Visible then
				setSelected(id, true)
			end
		end
		selectionChanged()
	end)
	onClick("SelectNone", function()
		table.clear(selected)
		table.clear(order)
		selectionChanged()
	end)
	onClick("SelectMe", function()
		table.clear(selected)
		table.clear(order)
		setSelected(player.UserId, true)
		selectionChanged()
	end)
	if roles.Search and roles.Search:IsA("TextBox") then
		roles.Search:GetPropertyChangedSignal("Text"):Connect(function()
			task.spawn(refreshList)
		end)
	end

	show(AdminConfig.TABS[1] and AdminConfig.TABS[1].Id or "")
	selectionChanged()

	-- refresh while open; re-run the open animation each time the menu opens
	local wasOpen = false
	task.spawn(function()
		while gui.Parent do
			local open = gui.Enabled
			if open then
				if not wasOpen and current and pages[current] then
					cascade(pages[current])
				end
				pcall(refreshList)
				pcall(refreshInspect)
				pcall(refreshLog)
			end
			wasOpen = open
			task.wait(AdminPanel.REFRESH)
		end
	end)
end

-- ================================================================ start

function AdminPanel.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local deadline = os.clock() + 15
		while player:GetAttribute("IsAdmin") ~= true and os.clock() < deadline do
			task.wait(0.25)
		end
		local admin = player:GetAttribute("IsAdmin") == true
		local bound = {}
		local function consider(g: Instance)
			if g:IsA("ScreenGui") and g:GetAttribute("AdminOnly") == true then
				if not admin then
					g:Destroy()
				elseif not bound[g] then
					bound[g] = true
					local ok, err = pcall(bind, g)
					if not ok then
						warn("[AdminPanel] " .. tostring(err))
					end
				end
			end
		end
		for _, g in playerGui:GetChildren() do
			consider(g)
		end
		playerGui.ChildAdded:Connect(function(g)
			task.defer(function()
				if g.Parent then
					consider(g)
				end
			end)
		end)
		if admin then
			print("[AdminPanel] running — built from AdminConfig")
		end
	end)
end

return AdminPanel
