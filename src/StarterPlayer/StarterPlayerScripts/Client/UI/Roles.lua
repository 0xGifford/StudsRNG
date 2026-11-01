--[[

Roles
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Roles

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Lives in the MenuSystem now (ReplicatedStorage.MenuSystem.Menus.Roles);
-- this keeps the game's existing requires working.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus"):WaitForChild("Roles"))
