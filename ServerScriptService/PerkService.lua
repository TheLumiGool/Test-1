-- ServerScriptService/PerkService
-- DROP-IN: spin perks, store inventory on attributes (easy to swap to Profile later),
-- equip up to 3 perks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PerkDefinitions"))

-- Remotes
local folder = ReplicatedStorage:FindFirstChild("PerksRemotes") or Instance.new("Folder")
folder.Name = "PerksRemotes"
folder.Parent = ReplicatedStorage

local SpinPerk = folder:FindFirstChild("SpinPerk") or Instance.new("RemoteFunction")
SpinPerk.Name = "SpinPerk"
SpinPerk.Parent = folder

local PerkEvent = folder:FindFirstChild("PerkEvent") or Instance.new("RemoteEvent")
PerkEvent.Name = "PerkEvent"
PerkEvent.Parent = folder

-- ===== helpers =====
local function encode(t) return game:GetService("HttpService"):JSONEncode(t) end
local function decode(s)
	if typeof(s) ~= "string" or s == "" then return nil end
	local ok, out = pcall(function() return game:GetService("HttpService"):JSONDecode(s) end)
	return ok and out or nil
end

local function getInv(plr)
	return decode(plr:GetAttribute("PerkInv") or "") or {}
end

local function setInv(plr, inv)
	plr:SetAttribute("PerkInv", encode(inv))
end

local function getEquipped(plr)
	local eq = decode(plr:GetAttribute("EquippedPerks") or "")
	if typeof(eq) ~= "table" then eq = {"","",""} end
	for i=1,3 do eq[i] = tostring(eq[i] or "") end
	return eq
end

local function setEquipped(plr, eq)
	for i=1,3 do eq[i] = tostring(eq[i] or "") end
	plr:SetAttribute("EquippedPerks", encode(eq))
end

local function getTokens(plr)
	return tonumber(plr:GetAttribute("PerkTokens") or 0) or 0
end

local function setTokens(plr, v)
	plr:SetAttribute("PerkTokens", math.max(0, math.floor(v)))
end

local function weightedPick()
	local total = 0
	for r, info in pairs(PerkDefinitions.Rarities) do total += info.weight end
	local roll = math.random() * total
	local acc = 0
	local rarityPicked = "Common"
	for r, info in pairs(PerkDefinitions.Rarities) do
		acc += info.weight
		if roll <= acc then rarityPicked = r break end
	end
	local pool = {}
	for _, p in ipairs(PerkDefinitions.List) do
		if p.Rarity == rarityPicked then
			table.insert(pool, p)
		end
	end
	if #pool == 0 then
		return PerkDefinitions.List[math.random(1, #PerkDefinitions.List)]
	end
	return pool[math.random(1,#pool)]
end

local function sendState(plr)
	PerkEvent:FireClient(plr, "State", {
		tokens = getTokens(plr),
		inv = getInv(plr),
		equipped = getEquipped(plr),
	})
end

Players.PlayerAdded:Connect(function(plr)
	-- default attributes if missing
	if plr:GetAttribute("PerkTokens") == nil then plr:SetAttribute("PerkTokens", 0) end
	if plr:GetAttribute("PerkInv") == nil then plr:SetAttribute("PerkInv", encode({})) end
	if plr:GetAttribute("EquippedPerks") == nil then plr:SetAttribute("EquippedPerks", encode({"","",""})) end
end)

SpinPerk.OnServerInvoke = function(plr, payload)
	payload = (typeof(payload)=="table") and payload or {}
	local tokens = getTokens(plr)
	if tokens <= 0 then
		return { ok=false, err="No Perk Tokens." }
	end

	setTokens(plr, tokens - 1)

	local perk = weightedPick()
	local inv = getInv(plr)
	inv[perk.Id] = (tonumber(inv[perk.Id]) or 0) + 1
	setInv(plr, inv)

	-- optionally auto-equip into first empty slot
	local eq = getEquipped(plr)
	for i=1,3 do
		if eq[i] == "" then
			eq[i] = perk.Id
			setEquipped(plr, eq)
			break
		end
	end

	sendState(plr)

	return {
		ok = true,
		perk = { id=perk.Id, name=perk.Name, rarity=perk.Rarity },
	}
end

PerkEvent.OnServerEvent:Connect(function(plr, action, payload)
	payload = (typeof(payload)=="table") and payload or {}

	if action == "RequestState" then
		sendState(plr)
		return
	end

	if action == "Equip" then
		local id = tostring(payload.id or "")
		local slot = tonumber(payload.slot) or 0
		if slot < 1 or slot > 3 then return end

		local inv = getInv(plr)
		if not inv[id] or inv[id] <= 0 then
			PerkEvent:FireClient(plr, "EquipAck", { ok=false, err="You don't own that perk." })
			return
		end

		local eq = getEquipped(plr)
		eq[slot] = id
		setEquipped(plr, eq)

		sendState(plr)
		PerkEvent:FireClient(plr, "EquipAck", { ok=true, slot=slot, id=id })
		return
	end

	if action == "Unequip" then
		local slot = tonumber(payload.slot) or 0
		if slot < 1 or slot > 3 then return end
		local eq = getEquipped(plr)
		eq[slot] = ""
		setEquipped(plr, eq)
		sendState(plr)
		return
	end
end)

print("[PerkService] Loaded ✅")
