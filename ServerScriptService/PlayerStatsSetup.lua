-- ServerScriptService/PlayerStatsSetup (Script)
local Players = game:GetService("Players")

local DEFAULTS = {
	Strength = 1,
	Speed = 1,
	Fortitude = 1,
	Endurance = 1,

	Stamina = 100,
	StaminaMax = 100,

	-- Talents currency
	TalentTokens = 3,

	-- Talent data
	OwnedTalents = "[]",
	EquippedTalent = "",
	TalentPity = 0,
}

local function init(plr: Player)
	for k,v in pairs(DEFAULTS) do
		if plr:GetAttribute(k) == nil then
			plr:SetAttribute(k, v)
		end
	end
end

Players.PlayerAdded:Connect(init)
for _,p in ipairs(Players:GetPlayers()) do init(p) end

print("[PlayerStatsSetup] Loaded")
