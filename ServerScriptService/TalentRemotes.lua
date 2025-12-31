-- ServerScriptService/TalentRemotes (Script)
-- FIX: RemoteFunction ALWAYS returns (prevents infinite spinning)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Folder in ReplicatedStorage
local folder = ReplicatedStorage:FindFirstChild("TalentsRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "TalentsRemotes"
	folder.Parent = ReplicatedStorage
end

-- RemoteFunction for spinning
local Spin = folder:FindFirstChild("SpinTalent")
if not Spin then
	Spin = Instance.new("RemoteFunction")
	Spin.Name = "SpinTalent"
	Spin.Parent = folder
end

-- RemoteEvent for equip feedback
local Event = folder:FindFirstChild("TalentEvent")
if not Event then
	Event = Instance.new("RemoteEvent")
	Event.Name = "TalentEvent"
	Event.Parent = folder
end

-- Try to load controller safely
local TalentsController = nil
do
	local ok, modOrErr = pcall(function()
		return require(game:GetService("ServerScriptService"):WaitForChild("TalentsController"))
	end)

	if ok then
		TalentsController = modOrErr
		print("[TalentRemotes] TalentsController loaded")
	else
		warn("[TalentRemotes] TalentsController FAILED to load:", modOrErr)
	end
end

-- IMPORTANT: Always return something (never hang client)
function Spin.OnServerInvoke(plr)
	-- If controller failed to load, return error immediately
	if not TalentsController then
		return { ok = false, err = "TalentsController failed to load (check Server Output for errors)." }
	end

	local ok, res = pcall(function()
		return TalentsController.Spin(plr)
	end)

	if not ok then
		warn("[TalentRemotes] Spin error:", res)
		return { ok = false, err = "Spin failed on server. Check Output." }
	end

	-- Ensure response is always a table
	if typeof(res) ~= "table" then
		return { ok = false, err = "Spin returned invalid response." }
	end

	return res
end

Event.OnServerEvent:Connect(function(plr, action, data)
	if not TalentsController then
		Event:FireClient(plr, "Equipped", { ok = false, err = "TalentsController missing." })
		return
	end

	if action == "Equip" and typeof(data) == "table" then
		local ok, result = pcall(function()
			return TalentsController.Equip(plr, tostring(data.id or ""))
		end)

		if not ok then
			warn("[TalentRemotes] Equip error:", result)
			Event:FireClient(plr, "Equipped", { ok = false, err = "Equip failed. Check Output." })
			return
		end

		Event:FireClient(plr, "Equipped", { ok = true, id = tostring(data.id or "") })
	end
end)

print("[TalentRemotes] Loaded")
