--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/Component

	The plumbing every attribute component shares (StudView, ZoneView,
	ProgressBar, KitColor, IconImage): anything in PlayerGui carrying the
	component's marker attribute is bound and drawn; changing any of its
	attributes redraws it (once per frame, however many change); it's
	cleaned up when it leaves PlayerGui. Copies of a template carry the
	template's attributes, so a list's rows draw themselves as they're added.

	A component module:

		local StudView = Component.new({
			Marker = "Stud",                          -- what makes it one
			Watch = { "StudVariant", "StudSilhouette" }, -- also redraw on these
			Class = "ViewportFrame",                  -- optional IsA filter
			Render = function(host, state) ... end,   -- draw; state is per host
			Cleanup = function(host, state) ... end,  -- optional
		})

	gives:
		StudView.Start()              scan PlayerGui and keep watching
		StudView.Set(host, values)    write attributes and bind right away
		                              (for a host that didn't have the marker)
		StudView.Bind(host) / StudView.Unbind(host) / StudView.Rescan(root)
]]

local Players = game:GetService("Players")

local Component = {}

export type Spec = {
	Marker: string,
	Watch: { string }?,
	Class: string?,
	Render: (host: any, state: { [string]: any }) -> (),
	Cleanup: ((host: any, state: { [string]: any }) -> ())?,
}

export type Api = {
	Start: () -> (),
	Bind: (host: Instance) -> (),
	Unbind: (host: Instance) -> (),
	Set: (host: Instance, values: { [string]: any }) -> (),
	Rescan: (root: Instance?) -> (),
	Count: () -> number,
}

type Entry = {
	state: { [string]: any },
	connection: RBXScriptConnection,
	destroying: RBXScriptConnection,
	queued: boolean,
}

function Component.new(spec: Spec): Api
	local entries: { [Instance]: Entry } = {}
	local watched: { [string]: boolean } = { [spec.Marker] = true }
	for _, name in spec.Watch or {} do
		watched[name] = true
	end
	local started = false
	local api = {} :: Api

	local function draw(host: Instance, entry: Entry)
		entry.queued = false
		if entries[host] ~= entry then return end
		local ok, err = pcall(spec.Render, host, entry.state)
		if not ok then
			warn(`[{spec.Marker}] {host:GetFullName()}: {err}`)
		end
	end

	local function queue(host: Instance, entry: Entry)
		if entry.queued then return end
		entry.queued = true
		task.defer(draw, host, entry)
	end

	function api.Unbind(host: Instance)
		local entry = entries[host]
		if not entry then return end
		entries[host] = nil
		entry.connection:Disconnect()
		entry.destroying:Disconnect()
		if spec.Cleanup then
			pcall(spec.Cleanup, host, entry.state)
		end
	end

	function api.Bind(host: Instance)
		if entries[host] then return end
		if host:GetAttribute(spec.Marker) == nil then return end
		if spec.Class and not host:IsA(spec.Class) then return end
		local entry: Entry = { state = {}, connection = nil :: any, destroying = nil :: any, queued = false }
		entries[host] = entry
		entry.connection = host.AttributeChanged:Connect(function(attribute)
			if not watched[attribute] then return end
			if host:GetAttribute(spec.Marker) == nil then
				api.Unbind(host)
			else
				queue(host, entry)
			end
		end)
		-- Bound outside PlayerGui (Set on a fresh copy): let go when it's destroyed.
		entry.destroying = host.Destroying:Connect(function()
			api.Unbind(host)
		end)
		queue(host, entry)
	end

	function api.Set(host: Instance, values: { [string]: any })
		for name, value in values do
			host:SetAttribute(name, value)
		end
		api.Bind(host)
	end

	function api.Rescan(root: Instance?)
		local scope: Instance = root or Players.LocalPlayer:WaitForChild("PlayerGui")
		api.Bind(scope)
		for _, descendant in scope:GetDescendants() do
			if descendant:GetAttribute(spec.Marker) ~= nil then
				api.Bind(descendant)
			end
		end
	end

	function api.Count(): number
		local n = 0
		for _ in entries do
			n += 1
		end
		return n
	end

	function api.Start()
		if started then return end
		started = true
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		api.Rescan(playerGui)
		playerGui.DescendantAdded:Connect(function(descendant)
			if descendant:GetAttribute(spec.Marker) ~= nil then
				api.Bind(descendant)
			end
		end)
		playerGui.DescendantRemoving:Connect(function(descendant)
			if entries[descendant] then
				api.Unbind(descendant)
			end
		end)
	end

	return api
end

return Component
