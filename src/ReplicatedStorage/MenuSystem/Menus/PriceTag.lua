--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/PriceTag

	Attribute-driven price display with discount support.

		~~R$ 1,995~~  -60%
		R$ 799

	A host becomes a price tag the moment it has a `Price` attribute — same rule as
	`Menu` on a button. No tag, no naming convention on the host itself.

	Roles are found on the children, by attribute:

		Frame  (Price = 799, ListPrice = 1995)
		 ├ TextLabel   PriceRole = "Original"
		 ├ TextLabel   PriceRole = "Discount"
		 └ TextLabel   PriceRole = "Current"

	Children named Original / Discount / Current are picked up as a fallback, so an
	existing panel works without re-authoring.

	The percentage is derived from the two numbers, never authored. You cannot ship
	a -60% badge sitting next to a price that is actually 40% off.

	HOST ATTRIBUTES
		Price           number   what the player pays now (required — this is the marker)
		ListPrice       number   pre-discount price; 0 or <= Price means no sale
		Owned           boolean  shows OwnedText instead of a price

	CONFIG ATTRIBUTES — resolved up the ancestor chain, like ButtonBounce sounds.
	Set them once on the ShopMenu and every price inside inherits.
		PriceSymbol      string   default "R$"
		PriceSymbolAfter boolean  put the symbol after the digits
		PriceGap         string   between symbol and digits, default " "
		PriceSeparator   string   thousands separator, default ","
		PriceDecimals    number   default 0
		DiscountFormat   string   default "-%d%%"
		DiscountRounding string   "Round" | "Floor" | "Ceil", default "Round"
		MinDiscount      number   hide the badge below this, default 1
		StrikeMode       string   "Rich" | "Line" | "None", default "Rich"
		StrikeColor3     Color3   Line mode only
		StrikeThickness  number   Line mode only, default 2
		SaleColor3       Color3   Current label colour while discounted
		NormalColor3     Color3   Current label colour at full price
		OwnedColor3      Color3
		FreeText         string   default "FREE"
		OwnedText        string   default "OWNED"

	API
		PriceTag.Start()
		PriceTag.Set(host, 799, 1995)
		PriceTag.SetOwned(host, true)
		PriceTag.Discount(host) -> number
		PriceTag.Format(1995) -> "1,995"
		PriceTag.Refresh(host)
		PriceTag.Count() -> number
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PriceTag = {}

type Entry = {
	host: Instance,
	original: Instance?,
	discount: Instance?,
	current: Instance?,
	connections: { RBXScriptConnection },
}

local entries: { [Instance]: Entry } = {}
local started = false

-- ---------------------------------------------------------------- helpers

--- Walks up the ancestor chain for a config attribute, so panel-level authoring
--- covers every descendant price without per-tag repetition.
local function inherit(instance: Instance, attribute: string, default: any): any
	local node: Instance? = instance
	while node do
		local value = node:GetAttribute(attribute)
		if value ~= nil then
			return value
		end
		node = node.Parent
	end
	return default
end

local function setText(instance: Instance?, text: string)
	if not instance then
		return
	end
	if instance:IsA("TextLabel") then
		instance.Text = text
	elseif instance:IsA("TextButton") then
		instance.Text = text
	elseif instance:IsA("TextBox") then
		instance.Text = text
	end
end

local function setRichText(instance: Instance?, enabled: boolean)
	if not instance then
		return
	end
	if instance:IsA("TextLabel") then
		instance.RichText = enabled
	elseif instance:IsA("TextButton") then
		instance.RichText = enabled
	end
end

local function setTextColor(instance: Instance?, colour: Color3)
	if not instance then
		return
	end
	if instance:IsA("TextLabel") then
		instance.TextColor3 = colour
	elseif instance:IsA("TextButton") then
		instance.TextColor3 = colour
	end
end

local function getBounds(instance: Instance?): Vector2
	if not instance then
		return Vector2.zero
	end
	if instance:IsA("TextLabel") then
		return instance.TextBounds
	elseif instance:IsA("TextButton") then
		return instance.TextBounds
	end
	return Vector2.zero
end

local function getAlignment(instance: Instance?): Enum.TextXAlignment
	if instance then
		if instance:IsA("TextLabel") then
			return instance.TextXAlignment
		elseif instance:IsA("TextButton") then
			return instance.TextXAlignment
		end
	end
	return Enum.TextXAlignment.Center
end

local function setVisible(instance: Instance?, visible: boolean)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

--- Escapes characters that RichText would otherwise parse as markup.
local function escapeRich(text: string): string
	local out = text:gsub("&", "&amp;")
	out = out:gsub("<", "&lt;")
	out = out:gsub(">", "&gt;")
	return out
end

-- ---------------------------------------------------------------- formatting

--- 1995 -> "1,995"
function PriceTag.Format(amount: number, separator: string?, decimals: number?): string
	local sep: string = separator or ","
	local places: number = decimals or 0

	local negative = amount < 0
	local absolute = math.abs(amount)
	local whole = math.floor(absolute)
	local fraction = ""

	if places > 0 then
		fraction = string.format("%." .. places .. "f", absolute - whole):sub(2)
	end

	local digits = tostring(whole)
	if sep ~= "" then
		local grouped = digits:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
		-- A separator can land at the very front on exact multiples of three digits.
		grouped = grouped:gsub("^" .. sep:gsub("%p", "%%%0"), "")
		digits = grouped
	end

	return (negative and "-" or "") .. digits .. fraction
end

local function money(host: Instance, amount: number): string
	local digits = PriceTag.Format(
		amount,
		inherit(host, "PriceSeparator", ","),
		inherit(host, "PriceDecimals", 0)
	)
	local symbol: string = inherit(host, "PriceSymbol", "R$")
	if symbol == "" then
		return digits
	end
	local gap: string = inherit(host, "PriceGap", " ")
	if inherit(host, "PriceSymbolAfter", false) == true then
		return digits .. gap .. symbol
	end
	return symbol .. gap .. digits
end

-- ---------------------------------------------------------------- maths

local function prices(host: Instance): (number, number)
	local now = tonumber(host:GetAttribute("Price")) or 0
	local list = tonumber(host:GetAttribute("ListPrice")) or 0
	return now, list
end

local function isDiscounted(host: Instance): boolean
	local now, list = prices(host)
	return list > 0 and list > now
end

--- Percentage off, rounded per DiscountRounding. 0 when not on sale.
function PriceTag.Discount(host: Instance): number
	if not isDiscounted(host) then
		return 0
	end
	local now, list = prices(host)
	local raw = (list - now) / list * 100

	local mode: string = inherit(host, "DiscountRounding", "Round")
	if mode == "Floor" then
		return math.floor(raw)
	elseif mode == "Ceil" then
		return math.ceil(raw)
	end
	return math.round(raw)
end

--- Absolute saving in currency units.
function PriceTag.Saving(host: Instance): number
	if not isDiscounted(host) then
		return 0
	end
	local now, list = prices(host)
	return list - now
end

-- ---------------------------------------------------------------- strike

local function clearStrike(label: Instance?)
	if not label then
		return
	end
	local line = label:FindFirstChild("PriceStrike")
	if line then
		line:Destroy()
	end
end

local function drawStrike(host: Instance, label: Instance)
	if not label:IsA("GuiObject") then
		return
	end

	local existing = label:FindFirstChild("PriceStrike")
	local line: Frame
	if existing and existing:IsA("Frame") then
		line = existing
	else
		line = Instance.new("Frame")
		line.Name = "PriceStrike"
		line.BorderSizePixel = 0
		line.Parent = label
	end

	line.ZIndex = label.ZIndex + 1
	line.BackgroundColor3 = inherit(host, "StrikeColor3", Color3.fromRGB(160, 166, 180))

	local thickness: number = inherit(host, "StrikeThickness", 2)
	local bounds = getBounds(label)
	local alignment = getAlignment(label)

	if alignment == Enum.TextXAlignment.Left then
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0, 0, 0.5, 0)
	elseif alignment == Enum.TextXAlignment.Right then
		line.AnchorPoint = Vector2.new(1, 0.5)
		line.Position = UDim2.new(1, 0, 0.5, 0)
	else
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
	end

	line.Size = UDim2.fromOffset(bounds.X, thickness)
end

-- ---------------------------------------------------------------- rendering

--- Redraws a single price tag from its current attributes.
function PriceTag.Refresh(host: Instance)
	local entry = entries[host]
	if not entry then
		return
	end

	local now, _list = prices(host)
	local discounted = isDiscounted(host)
	local percent = PriceTag.Discount(host)
	local minimum: number = inherit(host, "MinDiscount", 1)
	local showBadge = discounted and percent >= minimum
	local owned = host:GetAttribute("Owned") == true

	-- Original, struck through
	setVisible(entry.original, discounted and not owned)
	if entry.original and discounted and not owned then
		local _, list = prices(host)
		local text = money(host, list)
		local mode: string = inherit(host, "StrikeMode", "Rich")

		if mode == "Rich" then
			setRichText(entry.original, true)
			setText(entry.original, "<s>" .. escapeRich(text) .. "</s>")
			clearStrike(entry.original)
		elseif mode == "Line" then
			setRichText(entry.original, false)
			setText(entry.original, text)
			drawStrike(host, entry.original)
		else
			setRichText(entry.original, false)
			setText(entry.original, text)
			clearStrike(entry.original)
		end
	else
		clearStrike(entry.original)
	end

	-- Discount badge
	setVisible(entry.discount, showBadge and not owned)
	if entry.discount and showBadge and not owned then
		local pattern: string = inherit(host, "DiscountFormat", "-%d%%")
		local ok, text = pcall(string.format, pattern, percent)
		local rendered: string = ok and text or ("-" .. tostring(percent) .. "%")

		if entry.discount:IsA("TextLabel") or entry.discount:IsA("TextButton") then
			setText(entry.discount, rendered)
		else
			-- Badge is a frame wrapping its own label.
			local inner = entry.discount:FindFirstChildWhichIsA("TextLabel", true)
			setText(inner, rendered)
		end
	end

	-- Current price
	if entry.current then
		local text: string
		local colour: Color3

		if owned then
			text = inherit(host, "OwnedText", "OWNED")
			colour = inherit(host, "OwnedColor3", Color3.fromRGB(150, 156, 172))
		elseif now <= 0 then
			text = inherit(host, "FreeText", "FREE")
			colour = inherit(host, "SaleColor3", Color3.fromRGB(112, 198, 132))
		else
			text = money(host, now)
			if discounted then
				colour = inherit(host, "SaleColor3", Color3.fromRGB(112, 198, 132))
			else
				colour = inherit(host, "NormalColor3", Color3.fromRGB(238, 241, 248))
			end
		end

		setText(entry.current, text)
		setTextColor(entry.current, colour)
	end
end

-- ---------------------------------------------------------------- binding

local function findRole(host: Instance, role: string): Instance?
	-- Attribute first: fully convention-free.
	for _, descendant in host:GetDescendants() do
		if descendant:GetAttribute("PriceRole") == role then
			return descendant
		end
	end
	-- Fall back to the plain name so existing panels work untouched.
	local named = host:FindFirstChild(role, true)
	if named and (named:IsA("TextLabel") or named:IsA("TextButton") or named:IsA("GuiObject")) then
		return named
	end
	return nil
end

local function unbind(host: Instance)
	local entry = entries[host]
	if not entry then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	clearStrike(entry.original)
	entries[host] = nil
end

local function bind(host: Instance)
	if entries[host] then
		return
	end
	if host:GetAttribute("Price") == nil then
		return
	end

	local entry: Entry = {
		host = host,
		original = findRole(host, "Original"),
		discount = findRole(host, "Discount"),
		current = findRole(host, "Current"),
		connections = {},
	}

	if not entry.current then
		warn(("[PriceTag] %s has a Price attribute but no Current label")
			:format(host:GetFullName()))
	end

	entries[host] = entry

	table.insert(
		entry.connections,
		host.AttributeChanged:Connect(function(attribute: string)
			if attribute == "Price" and host:GetAttribute("Price") == nil then
				unbind(host)
				return
			end
			PriceTag.Refresh(host)
		end)
	)

	-- TextBounds settles a frame after the text is assigned, so a Line strike sized
	-- on assignment comes out at the wrong width. Follow the bounds instead.
	if entry.original and entry.original:IsA("GuiObject") then
		local label = entry.original
		table.insert(
			entry.connections,
			label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if inherit(host, "StrikeMode", "Rich") == "Line" then
					drawStrike(host, label)
				end
			end)
		)
		if label:IsA("TextLabel") or label:IsA("TextButton") then
			table.insert(
				entry.connections,
				label:GetPropertyChangedSignal("TextBounds"):Connect(function()
					if inherit(host, "StrikeMode", "Rich") == "Line" then
						drawStrike(host, label)
					end
				end)
			)
		end
	end

	PriceTag.Refresh(host)
end

-- ---------------------------------------------------------------- API

--- The main entry point. Pass the post-discount price, and optionally the original.
--- Passing nil (or 0) for `list` clears the sale.
function PriceTag.Set(host: Instance, price: number, list: number?)
	host:SetAttribute("ListPrice", list or 0)
	host:SetAttribute("Price", price)
	if not entries[host] then
		bind(host)
	else
		PriceTag.Refresh(host)
	end
end

function PriceTag.SetOwned(host: Instance, owned: boolean)
	host:SetAttribute("Owned", owned)
end

function PriceTag.Count(): number
	local count = 0
	for _ in entries do
		count += 1
	end
	return count
end

--- Rebinds everything. Useful after cloning shop rows from a template.
function PriceTag.Rescan(root: Instance?)
	local scope: Instance = root or Players.LocalPlayer:WaitForChild("PlayerGui")
	if scope:GetAttribute("Price") ~= nil then
		bind(scope)
	end
	for _, descendant in scope:GetDescendants() do
		if descendant:GetAttribute("Price") ~= nil then
			bind(descendant)
		end
	end
end

function PriceTag.Start()
	if started then
		return
	end
	started = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	PriceTag.Rescan(playerGui)

	playerGui.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:GetAttribute("Price") ~= nil then
			-- Defer so cloned rows have their children parented before roles resolve.
			task.defer(bind, descendant)
		end
	end)

	playerGui.DescendantRemoving:Connect(function(descendant: Instance)
		unbind(descendant)
	end)

	-- An attribute can be added after the instance exists, e.g. by a shop controller
	-- populating a cloned row.
	playerGui.AttributeChanged:Connect(function()
		if playerGui:GetAttribute("Price") ~= nil then
			bind(playerGui)
		end
	end)
end

return PriceTag
