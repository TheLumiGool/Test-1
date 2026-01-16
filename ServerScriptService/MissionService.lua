-- ServerScriptService/MissionService
-- Server-owned missions: start mission -> launch AI battle -> reward on success.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Missions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MissionDefinitions"))

-- Remotes
local folder = ReplicatedStorage:FindFirstChild("MissionRemotes") or Instance.new("Folder")
folder.Name = "MissionRemotes"
folder.Parent = ReplicatedStorage

local MissionEvent = folder:FindFirstChild("MissionEvent") or Instance.new("RemoteEvent")
MissionEvent.Name = "MissionEvent"
MissionEvent.Parent = folder

-- This is the only dependency you need to hook later:
-- AIBattleService.Start(plr, difficulty, onDone(success))
local AIBattleService = require(script.Parent:WaitForChild("AIBattleService"))

local active = {} -- active[plr] = missionId

local function findMission(id)
	for _, m in ipairs(Missions) do
		if m.Id == id then return m end
	end
	return nil
end

local function giveRewards(plr, rewards)
	rewards = rewards or {}

	local cur = tonumber(plr:GetAttribute("Currency") or 0) or 0
	plr:SetAttribute("Currency", cur + (tonumber(rewards.Currency) or 0))

	local function rollChance(ch)
		ch = tonumber(ch) or 0
		return (math.random() < ch)
	end

	if rollChance(rewards.PerkTokenChance) then
		plr:SetAttribute("PerkTokens", (tonumber(plr:GetAttribute("PerkTokens") or 0) or 0) + 1)
	end

	if rollChance(rewards.TalentTokenChance) then
		plr:SetAttribute("TalentTokens", (tonumber(plr:GetAttribute("TalentTokens") or 0) or 0) + 1)
	end
end

MissionEvent.OnServerEvent:Connect(function(plr, action, payload)
	payload = (typeof(payload)=="table") and payload or {}

	if action == "StartMission" then
		local id = tostring(payload.id or "")
		local m = findMission(id)
		if not m then
			MissionEvent:FireClient(plr, "MissionAck", { ok=false, err="Invalid mission." })
			return
		end
		if active[plr] then
			MissionEvent:FireClient(plr, "MissionAck", { ok=false, err="You already have an active mission." })
			return
		end

		active[plr] = id
		MissionEvent:FireClient(plr, "MissionAck", { ok=true, started=id })

		AIBattleService.Start(plr, m.Difficulty, function(success)
			if active[plr] ~= id then return end
			active[plr] = nil

			if success then
				giveRewards(plr, m.Rewards)
				MissionEvent:FireClient(plr, "MissionComplete", { ok=true, id=id, rewards=m.Rewards })
			else
				MissionEvent:FireClient(plr, "MissionComplete", { ok=false, id=id })
			end
		end)

		return
	end

	if action == "CancelMission" then
		active[plr] = nil
		MissionEvent:FireClient(plr, "MissionAck", { ok=true, cancelled=true })
		return
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	active[plr] = nil
end)

print("[MissionService] Loaded ✅")
