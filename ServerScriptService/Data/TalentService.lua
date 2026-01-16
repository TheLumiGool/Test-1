-- ServerScriptService/TalentsService (Script)
-- FULL DROP-IN OVERWRITE
-- ✅ Preferred Talent Bonus (server-side):
--    +10% if Epic or below, +5% Legendary, +1% Secret (boosts preferred within its rarity pool)
-- ✅ Pity System:
--    pity increments on Common/Rare
--    at 60 -> forced Epic+ with: 3% Secret, 45% Legendary, else Epic
-- ✅ Spin forces equip + updates player attributes + sends State/Equipped to client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TalentDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))

-- ======================================================
-- REMOTES
-- ======================================================
local remotes = ReplicatedStorage:FindFirstChild("TalentsRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "TalentsRemotes"
	remotes.Parent = ReplicatedStorage
end

local SpinTalent = remotes:FindFirstChild("SpinTalent")
if not SpinTalent then
	SpinTalent = Instance.new("RemoteFunction")
	SpinTalent.Name = "SpinTalent"
	SpinTalent.Parent = remotes
end

local TalentEvent = remotes:FindFirstChild("TalentEvent")
if not TalentEvent then
	TalentEvent = Instance.new("RemoteEvent")
	TalentEvent.Name = "TalentEvent"
	TalentEvent.Parent = remotes
end

-- ======================================================
-- CONFIG
-- ======================================================
local PITY_MAX = 60

-- Pity rarity distribution (Epic+ guaranteed)
local PITY_SECRET_CHANCE = 0.03
local PITY_LEGENDARY_CHANCE = 0.45
-- remainder -> Epic

-- ======================================================
-- INDEX TALENTS
-- ======================================================
local TalentById = {}
local PoolByRarity = {
	Common = {},
	Rare = {},
	Epic = {},
	Legendary = {},
	Secret = {},
}

for _, t in ipairs(TalentDefinitions.List) do
	if t.Id and t.Rarity then
		TalentById[t.Id] = t
		if PoolByRarity[t.Rarity] then
			table.insert(PoolByRarity[t.Rarity], t)
		end
	end
end

local function getTokens(plr)
	return tonumber(plr:GetAttribute("TalentTokens")) or 0
end

local function setTokens(plr, v)
	plr:SetAttribute("TalentTokens", math.max(0, math.floor(v)))
end

local function getEquipped(plr)
	return tostring(plr:GetAttribute("EquippedTalent") or "")
end

local function setEquipped(plr, id)
	plr:SetAttribute("EquippedTalent", tostring(id or ""))
end

local function getPity(plr)
	return tonumber(plr:GetAttribute("TalentPity")) or 0
end

local function setPity(plr, v)
	plr:SetAttribute("TalentPity", math.max(0, math.floor(v)))
end

local function bonusForRarity(r)
	-- requested: +10% if Epic or below, +5% if Legendary, +1% if Secret
	if r == "Secret" then return 0.01 end
	if r == "Legendary" then return 0.05 end
	return 0.10
end

local function rollWeighted(map)
	-- map: { [key]=weightNumber }
	local sum = 0
	for _, w in pairs(map) do
		if w > 0 then sum += w end
	end
	if sum <= 0 then
		-- fallback: return first key
		for k, _ in pairs(map) do return k end
		return nil
	end

	local r = math.random() * sum
	local acc = 0
	for k, w in pairs(map) do
		if w > 0 then
			acc += w
			if r <= acc then return k end
		end
	end

	-- fallback
	for k, _ in pairs(map) do return k end
	return nil
end

local function rollBaseRarity()
	-- uses TalentDefinitions.Rarities weights if present
	local weights = {}
	for rarityName, info in pairs(TalentDefinitions.Rarities or {}) do
		local w = tonumber(info.weight) or 0
		if w > 0 then
			weights[rarityName] = w
		end
	end

	-- ensure rarities exist
	if not next(weights) then
		weights = { Common = 70, Rare = 22, Epic = 7, Legendary = 1, Secret = 0.05 }
	end

	local r = rollWeighted(weights)
	return r or "Common"
end

local function rollPityRarity()
	local x = math.random()
	if x <= PITY_SECRET_CHANCE then
		return "Secret"
	elseif x <= (PITY_SECRET_CHANCE + PITY_LEGENDARY_CHANCE) then
		return "Legendary"
	else
		return "Epic"
	end
end

local function pickTalentFromRarity(rarity, preferredId)
	local pool = PoolByRarity[rarity]
	if not pool or #pool == 0 then
		-- fallback
		rarity = "Common"
		pool = PoolByRarity.Common
	end
	if not pool or #pool == 0 then return nil end

	-- Build weights per talent (base = 1)
	local weights = {}
	for _, t in ipairs(pool) do
		weights[t.Id] = 1
	end

	-- Apply preferred weight boost only if preferred is in THIS rarity pool
	if preferredId and preferredId ~= "" then
		local pref = TalentById[preferredId]
		if pref and pref.Rarity == rarity and weights[preferredId] then
			local bonus = bonusForRarity(rarity) -- 0.10 / 0.05 / 0.01
			weights[preferredId] = weights[preferredId] * (1 + bonus)
		end
	end

	local chosenId = rollWeighted(weights)
	if not chosenId then
		return pool[math.random(1, #pool)]
	end
	return TalentById[chosenId]
end

local function toClientTalent(t)
	return {
		id = t.Id,
		name = t.Name,
		rarity = t.Rarity,
	}
end

local function isEpicPlus(r)
	return r ~= nil and r ~= "Common" and r ~= "Rare"
end

local function sendState(plr)
	local eq = getEquipped(plr)
	TalentEvent:FireClient(plr, "State", {
		tokens = getTokens(plr),
		equipped = (eq ~= "" and TalentById[eq]) and { id = eq } or { id = "" },
		pity = getPity(plr),
		pityMax = PITY_MAX,
	})
end

-- ======================================================
-- REQUEST / EQUIP
-- ======================================================
TalentEvent.OnServerEvent:Connect(function(plr, action, payload)
	if typeof(action) ~= "string" then return end
	payload = (typeof(payload) == "table") and payload or {}

	if action == "RequestState" then
		sendState(plr)
		return
	end

	if action == "Equip" then
		local id = tostring(payload.id or "")
		if id == "" then return end
		if not TalentById[id] then return end

		setEquipped(plr, id)
		TalentEvent:FireClient(plr, "Equipped", { id = id })
		sendState(plr)
		return
	end
end)

-- ======================================================
-- SPIN
-- ======================================================
SpinTalent.OnServerInvoke = function(plr, args)
	args = (typeof(args) == "table") and args or {}
	local preferredId = tostring(args.preferredId or "")

	-- Validate preferredId (ignore invalid)
	if preferredId ~= "" and not TalentById[preferredId] then
		preferredId = ""
	end

	local tokens = getTokens(plr)
	if tokens <= 0 then
		return { ok = false, err = "No tokens." }
	end

	-- Spend token
	setTokens(plr, tokens - 1)

	-- Pity logic
	local pity = getPity(plr)
	local wasPity = pity >= (PITY_MAX - 1)
	local rarity

	if wasPity then
		-- next roll is pity roll
		rarity = rollPityRarity()
	else
		rarity = rollBaseRarity()
	end

	-- Pick talent from that rarity (with preferred weight boost if it matches that rarity)
	local chosen = pickTalentFromRarity(rarity, preferredId)
	if not chosen then
		return { ok = false, err = "No talents in pool." }
	end

	-- Update pity:
	-- - If pity roll was consumed -> reset
	-- - Else if result is Epic+ -> reset
	-- - Else (Common/Rare) -> +1
	if wasPity or isEpicPlus(chosen.Rarity) then
		pity = 0
	else
		pity = math.min(pity + 1, PITY_MAX)
	end
	setPity(plr, pity)

	-- Force equip
	setEquipped(plr, chosen.Id)

	-- Notify client
	TalentEvent:FireClient(plr, "Equipped", { id = chosen.Id })
	sendState(plr)

	return {
		ok = true,
		talent = toClientTalent(chosen),
		equipped = toClientTalent(chosen),
		pity = pity,
		pityMax = PITY_MAX,
		wasPity = wasPity,
		preferredUsed = (preferredId ~= "" and TalentById[preferredId] and TalentById[preferredId].Rarity == chosen.Rarity) or false,
	}
end

-- ======================================================
-- INIT ATTRS
-- ======================================================
Players.PlayerAdded:Connect(function(plr)
	-- ensure attrs exist
	if plr:GetAttribute("TalentTokens") == nil then plr:SetAttribute("TalentTokens", 0) end
	if plr:GetAttribute("EquippedTalent") == nil then plr:SetAttribute("EquippedTalent", "") end
	if plr:GetAttribute("TalentPity") == nil then plr:SetAttribute("TalentPity", 0) end
end)

print("[TalentsService] Loaded ✅ (preferred bonus + pity 60)")
