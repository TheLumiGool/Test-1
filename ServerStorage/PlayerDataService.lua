-- ServerScriptService/Data/PlayerDataService (ModuleScript)
-- Simple DataStore profile for Stats + Talents, applies as Attributes.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TalentDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))

local PlayerDataService = {}

local STORE_NAME = "ArmWrestle_Profile_v1"
local Store = DataStoreService:GetDataStore(STORE_NAME)

local Profiles = {} -- [player] = profileTable

local DEFAULT_PROFILE = {
	Version = 1,
	Stats = {
		Strength = 1,
		Speed = 1,
		Fortitude = 1,
		Endurance = 1,
		StaminaMax = 100,
	},
	Talents = {
		Owned = {}, -- array of Talent IDs
	},
	Spins = 0, -- if you want spin currency
}

local function deepCopy(t)
	local c = {}
	for k,v in pairs(t) do
		if type(v) == "table" then c[k] = deepCopy(v) else c[k] = v end
	end
	return c
end

local function sanitize(profile)
	if type(profile) ~= "table" then
		return deepCopy(DEFAULT_PROFILE)
	end
	profile.Version = profile.Version or 1
	profile.Stats = profile.Stats or deepCopy(DEFAULT_PROFILE.Stats)
	profile.Talents = profile.Talents or deepCopy(DEFAULT_PROFILE.Talents)
	profile.Talents.Owned = profile.Talents.Owned or {}
	profile.Spins = profile.Spins or 0

	-- ensure required stat keys exist
	for k, v in pairs(DEFAULT_PROFILE.Stats) do
		if profile.Stats[k] == nil then profile.Stats[k] = v end
	end

	return profile
end

local function applyProfileToPlayer(plr, profile)
	-- base stats
	for statName, value in pairs(profile.Stats) do
		plr:SetAttribute(statName, value)
	end

	-- stamina attribute should exist and start at max
	local maxStam = profile.Stats.StaminaMax or 100
	plr:SetAttribute("Stamina", maxStam)

	-- talents -> AW modifiers
	TalentDefinitions.ApplyAllToPlayer(plr, profile.Talents.Owned)

	-- apply stamina max add from talents
	local add = plr:GetAttribute("AW_StaminaMaxAdd") or 0
	plr:SetAttribute("StaminaMax", maxStam + add)

	-- if stamina is above new max, clamp
	local cur = plr:GetAttribute("Stamina") or (maxStam + add)
	if cur > (maxStam + add) then
		plr:SetAttribute("Stamina", maxStam + add)
	end
end

function PlayerDataService.GetProfile(plr)
	return Profiles[plr]
end

function PlayerDataService.Load(plr)
	local key = tostring(plr.UserId)
	local data
	local ok = pcall(function()
		data = Store:GetAsync(key)
	end)
	if not ok then
		data = nil
	end

	local profile = sanitize(data)
	Profiles[plr] = profile
	applyProfileToPlayer(plr, profile)
	return profile
end

function PlayerDataService.Save(plr)
	local profile = Profiles[plr]
	if not profile then return end

	-- pull current stats from Attributes back into profile before save
	profile.Stats.Strength = plr:GetAttribute("Strength") or profile.Stats.Strength
	profile.Stats.Speed = plr:GetAttribute("Speed") or profile.Stats.Speed
	profile.Stats.Fortitude = plr:GetAttribute("Fortitude") or profile.Stats.Fortitude
	profile.Stats.Endurance = plr:GetAttribute("Endurance") or profile.Stats.Endurance

	-- IMPORTANT: StaminaMax saved should be base (without talent add)
	-- so store the player attribute "StaminaMax" minus talent add:
	local add = plr:GetAttribute("AW_StaminaMaxAdd") or 0
	local stamMax = (plr:GetAttribute("StaminaMax") or 100) - add
	profile.Stats.StaminaMax = math.max(50, math.floor(stamMax))

	local key = tostring(plr.UserId)

	local ok, err = pcall(function()
		Store:UpdateAsync(key, function(_old)
			return profile
		end)
	end)
	if not ok then
		warn("[PlayerDataService] Save failed:", err)
	end
end

function PlayerDataService.AddTalent(plr, talentId)
	local profile = Profiles[plr]
	if not profile then return false end

	table.insert(profile.Talents.Owned, talentId)

	-- re-apply modifiers
	applyProfileToPlayer(plr, profile)
	return true
end

function PlayerDataService.RollTalent(plr)
	local profile = Profiles[plr]
	if not profile then return nil end

	local talent = TalentDefinitions.Roll()
	if talent then
		PlayerDataService.AddTalent(plr, talent.Id)
	end
	return talent
end

function PlayerDataService.Reapply(plr)
	local profile = Profiles[plr]
	if profile then applyProfileToPlayer(plr, profile) end
end

return PlayerDataService
