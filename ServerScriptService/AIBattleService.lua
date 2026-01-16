-- ServerScriptService/AIBattleService (ModuleScript)
-- Provides: AIBattleService.Start(player, difficulty, callback(success))
-- This module assumes your ArmWrestleService exposes an API to start AI matches.
-- We'll provide the ArmWrestleService patch right after.

local AIBattleService = {}

-- Require your ArmWrestleService module/API wrapper here if you have one.
-- If ArmWrestleService is a Script only, you can add a BindableFunction/Module export.
local ArmWrestleAPI = require(script.Parent:WaitForChild("ArmWrestleAPI")) -- you will add this small module below

function AIBattleService.Start(plr, difficulty, onDone)
	difficulty = tostring(difficulty or "Rookie")
	onDone = onDone or function() end

	ArmWrestleAPI.StartAIMatch(plr, difficulty, function(result)
		onDone(result == true)
	end)
end

return AIBattleService
