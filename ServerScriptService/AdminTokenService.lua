-- ServerScriptService/AdminTokenService (Script)
-- DROP-IN: Secure token giving
-- Only "TheLumiGool" can give TalentTokens

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ADMIN_NAME = "TheLumiGool"

local adminFolder = ReplicatedStorage:FindFirstChild("AdminRemotes") or Instance.new("Folder")
adminFolder.Name = "AdminRemotes"
adminFolder.Parent = ReplicatedStorage

local GiveTokens = adminFolder:FindFirstChild("GiveTalentTokens") or Instance.new("RemoteEvent")
GiveTokens.Name = "GiveTalentTokens"
GiveTokens.Parent = adminFolder

local function clampInt(n, a, b)
	n = tonumber(n)
	if not n then return nil end
	n = math.floor(n)
	if n < a then n = a end
	if n > b then n = b end
	return n
end

local function findPlayerByName(partial: string)
	partial = string.lower(partial or "")
	if partial == "" then return nil end
	for _, p in ipairs(Players:GetPlayers()) do
		if string.find(string.lower(p.Name), partial, 1, true) then
			return p
		end
	end
	return nil
end

GiveTokens.OnServerEvent:Connect(function(sender, targetName, amount)
	if not sender or sender.Name ~= ADMIN_NAME then
		return -- silent fail
	end

	local target = findPlayerByName(tostring(targetName or ""))
	if not target then
		GiveTokens:FireClient(sender, "ERR", "Player not found.")
		return
	end

	local amt = clampInt(amount, -100000, 100000)
	if not amt then
		GiveTokens:FireClient(sender, "ERR", "Invalid amount.")
		return
	end

	local cur = tonumber(target:GetAttribute("TalentTokens")) or 0
	target:SetAttribute("TalentTokens", cur + amt)

	GiveTokens:FireClient(sender, "OK", ("Set %s TalentTokens by %+d (now %d)"):format(target.Name, amt, cur + amt))
end)

print("[AdminTokenService] Loaded")
