-- StarterPlayerScripts/AdminPanelClient (LocalScript)
-- DROP-IN: Admin panel UI (toggle on/off)
-- Only visible/usable by "TheLumiGool"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if player.Name ~= "TheLumiGool" then
	return
end

local GiveTokens = ReplicatedStorage:WaitForChild("AdminRemotes"):WaitForChild("GiveTalentTokens")

local gui = Instance.new("ScreenGui")
gui.Name = "AdminTokensUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(420, 220)
root.BackgroundColor3 = Color3.fromRGB(16,16,22)
root.BorderSizePixel = 0
root.Parent = gui
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 14); rc.Parent = root
local rs = Instance.new("UIStroke"); rs.Thickness = 2; rs.Transparency = 0.35; rs.Parent = root

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1,0,0,22)
title.Font = Enum.Font.GothamBlack
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(245,245,255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "ADMIN: GIVE TALENT TOKENS"
title.Parent = root

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -30, 0, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 120, 120)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(18,18,24)
closeBtn.Parent = root
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = closeBtn

local function mkBox(y, placeholder)
	local box = Instance.new("TextBox")
	box.Position = UDim2.new(0,0,0,y)
	box.Size = UDim2.new(1,0,0,38)
	box.BackgroundColor3 = Color3.fromRGB(10,10,16)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(245,245,255)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(160,170,190)
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = root
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = box
	local bs = Instance.new("UIStroke"); bs.Thickness = 1; bs.Transparency = 0.6; bs.Parent = box
	return box
end

local targetBox = mkBox(34, "Target player name (partial ok)")
local amountBox = mkBox(82, "Amount (ex: 10, -5)")

local sendBtn = Instance.new("TextButton")
sendBtn.Position = UDim2.new(0,0,0,130)
sendBtn.Size = UDim2.new(1,0,0,40)
sendBtn.BackgroundColor3 = Color3.fromRGB(255,235,120)
sendBtn.BorderSizePixel = 0
sendBtn.Text = "GIVE TOKENS"
sendBtn.Font = Enum.Font.GothamBlack
sendBtn.TextSize = 16
sendBtn.TextColor3 = Color3.fromRGB(18,18,24)
sendBtn.Parent = root
local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 14); sc.Parent = sendBtn

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0,0,0,176)
status.Size = UDim2.new(1,0,0,24)
status.Font = Enum.Font.GothamMedium
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(200,235,255)
status.Text = "Toggle with F6"
status.Parent = root

closeBtn.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

sendBtn.MouseButton1Click:Connect(function()
	local target = targetBox.Text
	local amt = tonumber(amountBox.Text)
	if not target or target == "" then
		status.TextColor3 = Color3.fromRGB(255,160,160)
		status.Text = "Enter a target player name."
		return
	end
	if not amt then
		status.TextColor3 = Color3.fromRGB(255,160,160)
		status.Text = "Enter a valid amount."
		return
	end
	status.TextColor3 = Color3.fromRGB(200,235,255)
	status.Text = "Sending..."
	GiveTokens:FireServer(target, amt)
end)

GiveTokens.OnClientEvent:Connect(function(kind, msg)
	if kind == "OK" then
		status.TextColor3 = Color3.fromRGB(140,255,200)
	else
		status.TextColor3 = Color3.fromRGB(255,160,160)
	end
	status.Text = tostring(msg)
end)

-- Toggle: F6
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F6 then
		gui.Enabled = not gui.Enabled
	end
end)

print("[AdminPanelClient] Loaded (F6 toggle)")
