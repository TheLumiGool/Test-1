-- ServerScriptService/CodesService (Script)
-- DROP-IN Codes System (NO OpenBrowserWindow)
-- ✅ Group-gated code redeem (server enforced)
-- ✅ Expiry time per code (os.time)
-- ✅ Optional global max uses per code (DataStore)
-- ✅ Per-player redeemed tracking (DataStore)
-- ✅ Rewards TalentTokens attribute (easy to swap to Profile)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- =========================
-- CONFIG
-- =========================
local GROUP_ID = 120554421 -- <<<<<< CHANGE THIS to your group id

-- Where tokens are stored (simple drop-in):
-- If you already use ProfileService, replace these 2 functions below.
local TOKEN_ATTRIBUTE = "TalentTokens"

-- DataStores
local DS_REDEEMED = DataStoreService:GetDataStore("Codes_Redeemed_V1")     -- per player
local DS_GLOBAL_USES = DataStoreService:GetDataStore("Codes_GlobalUses_V1") -- per code (optional)

-- =========================
-- CODE DEFINITIONS
-- =========================
-- expiry is a UNIX timestamp (os.time())
-- Use: https://www.epochconverter.com/ (or compute in Studio)
-- maxGlobalUses = nil means infinite global uses
local CODES = {
	-- Example codes:
	["WELCOME"] = { tokens = 10,  expiry = 2000000000, maxGlobalUses = nil },
	["TOKENS10"] = { tokens = 10, expiry = 2000000000, maxGlobalUses = 5000 },
	["TESTER"] = { tokens = 25, expiry = 2000000000, maxGlobalUses = 20000 },
	["SANDBOX"] = { tokens = 50,  expiry = 2000000000, maxGlobalUses = nil },

}

-- =========================
-- REMOTES
-- =========================
local remotesFolder = ReplicatedStorage:FindFirstChild("CodesRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "CodesRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local RedeemCode = remotesFolder:FindFirstChild("RedeemCode")
if not RedeemCode then
	RedeemCode = Instance.new("RemoteFunction")
	RedeemCode.Name = "RedeemCode"
	RedeemCode.Parent = remotesFolder
end

local CodesEvent = remotesFolder:FindFirstChild("CodesEvent")
if not CodesEvent then
	CodesEvent = Instance.new("RemoteEvent")
	CodesEvent.Name = "CodesEvent"
	CodesEvent.Parent = remotesFolder
end

-- =========================
-- HELPERS
-- =========================
local function normalizeCode(code: string)
	code = tostring(code or "")
	code = string.upper(code)
	code = code:gsub("%s+", "") -- remove spaces
	return code
end

local function getTokens(plr: Player)
	return tonumber(plr:GetAttribute(TOKEN_ATTRIBUTE)) or 0
end

local function addTokens(plr: Player, amount: number)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	plr:SetAttribute(TOKEN_ATTRIBUTE, getTokens(plr) + amount)
end

local function isInGroup(plr: Player)
	local ok, res = pcall(function()
		return plr:IsInGroup(GROUP_ID)
	end)
	return ok and res == true
end

local function loadRedeemed(plr: Player)
	local key = "u_" .. plr.UserId
	local data
	local ok = pcall(function()
		data = DS_REDEEMED:GetAsync(key)
	end)
	if not ok or typeof(data) ~= "table" then
		data = {}
	end
	-- store as set: redeemed[CODE] = true
	return data
end

local function saveRedeemed(plr: Player, redeemedTable: table)
	local key = "u_" .. plr.UserId
	pcall(function()
		DS_REDEEMED:SetAsync(key, redeemedTable)
	end)
end

local function incGlobalUses(codeKey: string, maxGlobalUses: number?)
	-- returns (ok:boolean, usesNow:number, errMsg:string?)
	if not maxGlobalUses then
		return true, 0, nil
	end

	local storeKey = "c_" .. codeKey
	local usesNow = 0
	local ok, err = pcall(function()
		usesNow = DS_GLOBAL_USES:UpdateAsync(storeKey, function(old)
			old = tonumber(old) or 0
			if old >= maxGlobalUses then
				return old
			end
			return old + 1
		end)
	end)

	if not ok then
		return false, 0, "DataStore error (global uses). Try again."
	end

	if usesNow > maxGlobalUses then
		return false, usesNow, "Code has reached max global uses."
	end

	if usesNow == maxGlobalUses then
		-- This redeem consumed the final use - still OK.
		return true, usesNow, nil
	end

	-- If UpdateAsync returned same value because max reached:
	if usesNow >= maxGlobalUses then
		return false, usesNow, "Code has reached max global uses."
	end

	return true, usesNow, nil
end

local function getCodeInfoForClient()
	-- Only send safe info (do NOT send secret codes if you dont want to)
	-- For now, just send groupId + a message.
	return {
		groupId = GROUP_ID,
	}
end

-- =========================
-- PLAYER INIT
-- =========================
Players.PlayerAdded:Connect(function(plr)
	-- ensure token attribute exists
	if plr:GetAttribute(TOKEN_ATTRIBUTE) == nil then
		plr:SetAttribute(TOKEN_ATTRIBUTE, 0)
	end

	-- optional: push basic config to client
	CodesEvent:FireClient(plr, "Init", getCodeInfoForClient())
end)

-- =========================
-- REDEEM LOGIC
-- =========================
RedeemCode.OnServerInvoke = function(plr: Player, rawCode: any)
	local codeKey = normalizeCode(rawCode)

	if codeKey == "" then
		return { ok=false, msg="Enter a code." }
	end

	-- must be in group
	if not isInGroup(plr) then
		return { ok=false, msg=("Join the group to use codes. Group ID: %d"):format(GROUP_ID) }
	end

	local def = CODES[codeKey]
	if not def then
		return { ok=false, msg="Invalid code." }
	end

	-- expiry check
	local now = os.time()
	local expiry = tonumber(def.expiry) or 0
	if expiry > 0 and now > expiry then
		return { ok=false, msg="This code has expired." }
	end

	-- per-player redeemed check
	local redeemed = loadRedeemed(plr)
	if redeemed[codeKey] then
		return { ok=false, msg="You already redeemed this code." }
	end

	-- global uses check + increment (optional)
	local okGlobal, _, errMsg = incGlobalUses(codeKey, def.maxGlobalUses)
	if not okGlobal then
		return { ok=false, msg=errMsg or "Code unavailable." }
	end

	-- reward
	local tokens = tonumber(def.tokens) or 0
	if tokens <= 0 then
		return { ok=false, msg="Code reward misconfigured." }
	end

	-- mark redeemed then save
	redeemed[codeKey] = true
	saveRedeemed(plr, redeemed)

	addTokens(plr, tokens)

	return {
		ok = true,
		msg = ("Redeemed! +%d Tokens"):format(tokens),
		tokensAdded = tokens,
		newTotal = getTokens(plr),
	}
end

print("[CodesService] Loaded ✅")
