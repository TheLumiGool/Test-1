-- ServerScriptService/TalentPreferenceService (Script)
-- Stores PreferredTalentId on the player via RemoteEvent
-- Validates the talent exists in TalentDefinitions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TalentDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))

-- Remotes
local remotesFolder = ReplicatedStorage:FindFirstChild("TalentRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "TalentRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local TalentEvent = remotesFolder:FindFirstChild("TalentEvent")
if not TalentEvent then
	TalentEvent = Instance.new("RemoteEvent")
	TalentEvent.Name = "TalentEvent"
	TalentEvent.Parent = remotesFolder
end

local function talentExists(id: string)
	id = tostring(id or "")
	if id == "" then return false end
	if TalentDefinitions.Get then
		return TalentDefinitions.Get(id) ~= nil
	end
	-- fallback: scan list
	for _, t in ipairs(TalentDefinitions.List or {}) do
		if t and t.Id == id then
			return true
		end
	end
	return false
end

Players.PlayerAdded:Connect(function(plr)
	if plr:GetAttribute("PreferredTalentId") == nil then
		plr:SetAttribute("PreferredTalentId", "")
	end
end)

TalentEvent.OnServerEvent:Connect(function(plr, action, payload)
	if action ~= "SetPreferredTalent" then return end
	payload = (typeof(payload) == "table") and payload or {}

	local id = tostring(payload.talentId or "")
	if id == "" then
		plr:SetAttribute("PreferredTalentId", "")
		TalentEvent:FireClient(plr, "PreferredAck", { ok=true, talentId="" })
		return
	end

	if not talentExists(id) then
		TalentEvent:FireClient(plr, "PreferredAck", { ok=false, err="Invalid talent id." })
		return
	end

	plr:SetAttribute("PreferredTalentId", id)
	TalentEvent:FireClient(plr, "PreferredAck", { ok=true, talentId=id })
end)

print("[TalentPreferenceService] Loaded ✅")
