-- ServerScriptService/Data/PlayerDataLoader (Script)
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService:WaitForChild("Data"):WaitForChild("PlayerDataService"))

Players.PlayerAdded:Connect(function(plr)
	PlayerDataService.Load(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	PlayerDataService.Save(plr)
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		PlayerDataService.Save(plr)
	end
end)
