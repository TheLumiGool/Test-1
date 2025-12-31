-- StarterPlayerScripts/CodesClient (LocalScript)
-- DROP-IN Codes UI (NO OpenBrowserWindow)
-- ✅ Shows Like/Favorite/Group recommendation panel
-- ✅ Redeem box + button
-- ✅ Group ID instructions
-- ✅ Uses CodesRemotes.RedeemCode RemoteFunction

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("CodesRemotes")
local RedeemCode = remotes:WaitForChild("RedeemCode")
local CodesEvent = remotes:WaitForChild("CodesEvent")

-- =========================
-- UI Helpers
-- =========================
local function tween(obj, ti, props)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

-- =========================
-- Config received from server
-- =========================
local GROUP_ID = 0

CodesEvent.OnClientEvent:Connect(function(action, data)
	if action == "Init" and typeof(data) == "table" then
		GROUP_ID = tonumber(data.groupId) or 0
	end
end)

-- =========================
-- Build UI
-- =========================
local gui = Instance.new("ScreenGui")
gui.Name = "CodesUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.52)
root.Size = UDim2.fromOffset(620, 340)
root.BackgroundColor3 = Color3.fromRGB(18,18,26)
root.BorderSizePixel = 0
root.Parent = gui
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 16); rc.Parent = root
local rs = Instance.new("UIStroke"); rs.Thickness = 2; rs.Transparency = 0.25; rs.Parent = root

local grad = Instance.new("UIGradient")
grad.Rotation = 20
grad.Color = ColorSequence.new(Color3.fromRGB(45, 30, 85), Color3.fromRGB(10, 70, 80))
grad.Parent = root

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 14)
pad.PaddingBottom = UDim.new(0, 14)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 26)
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(245,245,255)
title.Text = "CODES"
title.Parent = root

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.Size = UDim2.fromOffset(34, 34)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 120, 120)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(18,18,24)
closeBtn.Parent = root
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 10); cbc.Parent = closeBtn

local info = Instance.new("TextLabel")
info.BackgroundTransparency = 1
info.Position = UDim2.new(0, 0, 0, 32)
info.Size = UDim2.new(1, 0, 0, 44)
info.Font = Enum.Font.GothamMedium
info.TextSize = 13
info.TextWrapped = true
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextColor3 = Color3.fromRGB(200, 235, 255)
info.Text = "To redeem codes: Join the group.\n(Like/Favorite are recommended but not required.)"
info.Parent = root

local groupHint = Instance.new("TextLabel")
groupHint.BackgroundTransparency = 1
groupHint.Position = UDim2.new(0, 0, 0, 78)
groupHint.Size = UDim2.new(1, 0, 0, 18)
groupHint.Font = Enum.Font.GothamBold
groupHint.TextSize = 12
groupHint.TextXAlignment = Enum.TextXAlignment.Left
groupHint.TextColor3 = Color3.fromRGB(255,235,120)
groupHint.Text = "Group: (loading...)"
groupHint.Parent = root

-- Recommendation panel
local rec = Instance.new("Frame")
rec.Position = UDim2.new(0, 0, 0, 104)
rec.Size = UDim2.new(1, 0, 0, 88)
rec.BackgroundColor3 = Color3.fromRGB(12,12,18)
rec.BorderSizePixel = 0
rec.Parent = root
local recc = Instance.new("UICorner"); recc.CornerRadius = UDim.new(0, 14); recc.Parent = rec
local recs = Instance.new("UIStroke"); recs.Thickness = 2; recs.Transparency = 0.6; recs.Parent = rec

local recTitle = Instance.new("TextLabel")
recTitle.BackgroundTransparency = 1
recTitle.Position = UDim2.new(0, 12, 0, 10)
recTitle.Size = UDim2.new(1, -24, 0, 18)
recTitle.Font = Enum.Font.GothamBlack
recTitle.TextSize = 14
recTitle.TextXAlignment = Enum.TextXAlignment.Left
recTitle.TextColor3 = Color3.fromRGB(245,245,255)
recTitle.Text = "RECOMMENDED"
recTitle.Parent = rec

local recBody = Instance.new("TextLabel")
recBody.BackgroundTransparency = 1
recBody.Position = UDim2.new(0, 12, 0, 32)
recBody.Size = UDim2.new(1, -24, 1, -40)
recBody.Font = Enum.Font.Gotham
recBody.TextSize = 13
recBody.TextWrapped = true
recBody.TextXAlignment = Enum.TextXAlignment.Left
recBody.TextYAlignment = Enum.TextYAlignment.Top
recBody.TextColor3 = Color3.fromRGB(190,200,220)
recBody.Text =
	"• Favorite the game ⭐\n" ..
	"• Like the game 👍\n" ..
	"• Join the group (required for codes)\n"
recBody.Parent = rec

-- Code entry
local box = Instance.new("TextBox")
box.Position = UDim2.new(0, 0, 0, 204)
box.Size = UDim2.new(1, 0, 0, 42)
box.BackgroundColor3 = Color3.fromRGB(10,10,14)
box.BorderSizePixel = 0
box.Font = Enum.Font.GothamBold
box.TextSize = 14
box.TextColor3 = Color3.fromRGB(245,245,255)
box.PlaceholderText = "Enter code here (example: WELCOME)"
box.ClearTextOnFocus = false
box.Parent = root
local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 14); bc.Parent = box
local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Transparency = 0.55; bs.Parent = box
local bp = Instance.new("UIPadding"); bp.PaddingLeft = UDim.new(0, 12); bp.PaddingRight = UDim.new(0, 12); bp.Parent = box

local redeemBtn = Instance.new("TextButton")
redeemBtn.Position = UDim2.new(0, 0, 0, 252)
redeemBtn.Size = UDim2.new(1, 0, 0, 46)
redeemBtn.BackgroundColor3 = Color3.fromRGB(255,235,120)
redeemBtn.BorderSizePixel = 0
redeemBtn.Text = "REDEEM"
redeemBtn.Font = Enum.Font.GothamBlack
redeemBtn.TextSize = 18
redeemBtn.TextColor3 = Color3.fromRGB(18,18,24)
redeemBtn.Parent = root
local rbc = Instance.new("UICorner"); rbc.CornerRadius = UDim.new(0, 14); rbc.Parent = redeemBtn

local resultLbl = Instance.new("TextLabel")
resultLbl.BackgroundTransparency = 1
resultLbl.Position = UDim2.new(0, 0, 0, 304)
resultLbl.Size = UDim2.new(1, 0, 0, 20)
resultLbl.Font = Enum.Font.GothamBold
resultLbl.TextSize = 13
resultLbl.TextXAlignment = Enum.TextXAlignment.Left
resultLbl.TextColor3 = Color3.fromRGB(190,200,220)
resultLbl.Text = ""
resultLbl.Parent = root

-- =========================
-- Open/Close UI
-- =========================
local function openUI()
	gui.Enabled = true
	root.Position = UDim2.fromScale(0.5, 0.55)
	tween(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5, 0.52)})

	if GROUP_ID and GROUP_ID ~= 0 then
		groupHint.Text = ("Group: Join Group ID %d to use codes."):format(GROUP_ID)
	else
		groupHint.Text = "Group: Join the group to use codes. (Group ID not loaded yet)"
	end
end

local function closeUI()
	tween(root, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.fromScale(0.5, 0.55)})
	task.delay(0.17, function()
		gui.Enabled = false
	end)
end

closeBtn.MouseButton1Click:Connect(closeUI)

-- Toggle key (you can change this)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.C then
		if gui.Enabled then closeUI() else openUI() end
	end
end)

-- =========================
-- Redeem
-- =========================
local busy = false
local function setResult(text, good)
	resultLbl.Text = text or ""
	if good then
		resultLbl.TextColor3 = Color3.fromRGB(140, 255, 180)
	else
		resultLbl.TextColor3 = Color3.fromRGB(255, 160, 160)
	end
end

redeemBtn.MouseButton1Click:Connect(function()
	if busy then return end
	busy = true
	setResult("", false)

	local code = box.Text
	if (code or "") == "" then
		setResult("Enter a code first.", false)
		busy = false
		return
	end

	redeemBtn.Text = "CHECKING..."
	redeemBtn.Active = false

	local ok, res = pcall(function()
		return RedeemCode:InvokeServer(code)
	end)

	redeemBtn.Active = true
	redeemBtn.Text = "REDEEM"
	busy = false

	if not ok then
		setResult("Redeem failed (network). Try again.", false)
		return
	end

	if typeof(res) ~= "table" then
		setResult("Redeem failed (bad response).", false)
		return
	end

	if res.ok then
		setResult(res.msg or "Redeemed!", true)
		-- clear text on success
		box.Text = ""
	else
		setResult(res.msg or "Invalid.", false)
	end
end)

print("[CodesClient] Loaded ✅ (Press C to open)")
