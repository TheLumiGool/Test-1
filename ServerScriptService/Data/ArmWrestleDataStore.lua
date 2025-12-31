-- ServerScriptService/Data/ArmWrestleDataStore (Script)
-- Saves: TalentTokens, OwnedTalents, EquippedTalent, TalentPity, AW_TotalWins, AW_Currency
-- Simple DataStore persistence. Works with your Attribute-based systems.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "AW_PlayerData_v1"  -- change this to wipe everyone (version bump)
local Store = DataStoreService:GetDataStore(STORE_NAME)

-- Default values if player has no save
local DEFAULTS = {
	TalentTokens = 10,
	OwnedTalents = "[]",      -- JSON string
	EquippedTalent = "",
	TalentPity = 0,

	AW_TotalWins = 0,
	AW_TotalLosses = 0,
	AW_WinStreak = 0,
	AW_BestStreak = 0,
	AW_Currency = 0,
}

local SAVE_KEYS = {
	"TalentTokens",
	"OwnedTalents",
	"EquippedTalent",
	"TalentPity",
	"AW_TotalWins",
	"AW_TotalLosses",
	"AW_WinStreak",
	"AW_BestStreak",
	"AW_Currency",
}

local function applyDefaults(plr: Player)
	for k,v in pairs(DEFAULTS) do
		if plr:GetAttribute(k) == nil then
			plr:SetAttribute(k, v)
		end
	end
end

local function loadPlayer(plr: Player)
	applyDefaults(plr)

	local key = "u_" .. plr.UserId
	local ok, data = pcall(function()
		return Store:GetAsync(key)
	end)

	if ok and typeof(data) == "table" then
		for _, k in ipairs(SAVE_KEYS) do
			if data[k] ~= nil then
				plr:SetAttribute(k, data[k])
			end
		end
	else
		-- keep defaults if no data / failed
	end
end

local function packPlayer(plr: Player)
	local out = {}
	for _, k in ipairs(SAVE_KEYS) do
		out[k] = plr:GetAttribute(k)
	end
	return out
end

local function savePlayer(plr: Player)
	if not plr then return end

	local key = "u_" .. plr.UserId
	local payload = packPlayer(plr)

	local ok, err = pcall(function()
		Store:SetAsync(key, payload)
	end)

	if not ok then
		warn("[ArmWrestleDataStore] Save failed:", plr.Name, err)
	end
end

Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(savePlayer)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		savePlayer(plr)
	end
end)

print("[ArmWrestleDataStore] Loaded:", STORE_NAME)
