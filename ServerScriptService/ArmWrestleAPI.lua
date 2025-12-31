-- ServerScriptService/ArmWrestleAPI (ModuleScript)
-- Bridge that calls into ArmWrestleService via BindableFunction.

local ServerScriptService = game:GetService("ServerScriptService")

local binder = ServerScriptService:WaitForChild("ArmWrestleAIBind") :: BindableFunction

local API = {}

function API.StartAIMatch(plr, difficulty, callback)
	-- callback is called by service via RemoteEvent later; for now, we just start.
	binder:Invoke(plr, difficulty)
	-- ArmWrestleService will call callback via another bindable or directly; easiest is RemoteEvent -> client -> server.
	-- We'll implement a second bindable below for completion.
	local doneBind = ServerScriptService:WaitForChild("ArmWrestleAIDone") :: BindableEvent
	local conn
	conn = doneBind.Event:Connect(function(p, success)
		if p ~= plr then return end
		conn:Disconnect()
		callback(success == true)
	end)
end

return API
