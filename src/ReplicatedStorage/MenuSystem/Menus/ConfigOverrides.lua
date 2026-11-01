--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/ConfigOverrides

	Makes MenuSystem.Config the single place to tune every menu module.
	Config.Modules = { <ModuleName> = { FIELD = value, ... }, ... } — each entry
	is copied onto that module's table (tables are merged key by key) before any
	module starts. Boot this FIRST in MenuBootstrap.

	A field only takes effect if the module reads it while running (all of the
	values the generator wrote into Config are public fields of their module).
]]

local ConfigOverrides = {}

local started = false

local function merge(target: { [any]: any }, values: { [any]: any })
	for k, v in values do
		if type(v) == "table" and type(target[k]) == "table" and #v == 0 and next(v) ~= nil then
			merge(target[k], v)
		else
			target[k] = v
		end
	end
end

function ConfigOverrides.Start()
	if started then
		return
	end
	started = true
	local ok, Config = pcall(require, script.Parent.Parent:WaitForChild("Config"))
	if not ok or type(Config) ~= "table" or type(Config.Modules) ~= "table" then
		warn("[ConfigOverrides] Config.Modules not found — nothing applied")
		return
	end
	local applied, missing = 0, {}
	for name, values in Config.Modules do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") and type(values) == "table" then
			local loaded, target = pcall(require, module)
			if loaded and type(target) == "table" then
				local merged = pcall(merge, target, values)
				if merged then
					applied += 1
				end
			else
				table.insert(missing, name)
			end
		else
			table.insert(missing, name)
		end
	end
	print(("[ConfigOverrides] applied Config.Modules to %d module(s)%s"):format(applied,
		#missing > 0 and (" — not found: " .. table.concat(missing, ", ")) or ""))
end

return ConfigOverrides
