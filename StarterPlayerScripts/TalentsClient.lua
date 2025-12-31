-- StarterPlayerScripts/TalentsClient (LocalScript)
-- ✅ FULL DROP-IN OVERWRITE (WITH PITY + LUCKY SPIN)
-- Features:
-- 1) Resizable UI (drag bottom-right corner) + UIScale (fits any device)
-- 2) Fake spinner (ONE pass) + cinematic Epic/Legendary/Secret (Secret = shake+glitch)
-- 3) Spin FORCE-EQUIPS (also fires Equip as backup)
-- 4) Preferred Talent selection (highlight + star) and sends preferredId to server on spin:
--    +10% if Epic or below, +5% if Legendary, +1% if Secret (server should apply odds)
-- 5) Sounds:
--    Spin start: 117570443671176
--    Tick per fake step: 4621722813
--    Pop-up UI sound: 114423989561011
--    Secret glitch/shake sound: 123444136272094
--    Finish sounds: Common/Rare 104876050679091, Epic 100931270018375, Legendary 114654897262684
-- 6) Flash/cinematic ONLY for Epic+ (Epic/Legendary/Secret). Common/Rare: no flash.
-- 7) Pity tracking UI + "Lucky Spin" animation when NEXT spin is pity.
--    - Expects server to send pity/pityMax in State and Spin results (recommended).
--    - Has a safe client fallback pity counter if server doesn't send.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local TalentDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))

local remotes = ReplicatedStorage:WaitForChild("TalentsRemotes")
local SpinTalent = remotes:WaitForChild("SpinTalent") -- RemoteFunction
local TalentEvent = remotes:WaitForChild("TalentEvent") -- RemoteEvent

-- =========================
-- Helpers
-- =========================
local function clamp(x,a,b) return math.max(a, math.min(b, x)) end

local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function tween(obj, ti, props)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

local function mkSound(id, looped, volume)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Looped = looped or false
	s.Volume = volume or 0.7
	s.Parent = SoundService
	return s
end

local function playSfx(s)
	if not s then return end
	pcall(function() s.TimePosition = 0 end)
	s:Play()
end

local function rarityColor(r)
	if r == "Common" then return Color3.fromRGB(180, 255, 200) end
	if r == "Rare" then return Color3.fromRGB(140, 210, 255) end
	if r == "Epic" then return Color3.fromRGB(205, 140, 255) end
	if r == "Legendary" then return Color3.fromRGB(255, 235, 120) end
	if r == "Secret" then return Color3.fromRGB(255, 110, 200) end
	return Color3.fromRGB(255,255,255)
end

local function isEpicPlus(r)
	return (r == "Epic" or r == "Legendary" or r == "Secret")
end

local function bonusForRarity(r)
	-- requested: +10% if Epic or below, +5% if Legendary, +1% if Secret
	if r == "Secret" then return 0.01 end
	if r == "Legendary" then return 0.05 end
	return 0.10
end

local function fmtPct(x)
	return ("%d%%"):format(math.floor(x * 100 + 0.5))
end

local function getStyleRegen(style)
	local regen = tonumber(style and style.StaminaRegen)
	if regen then return regen end
	local maxStam = tonumber(style and style.StaminaMax) or 180
	return math.clamp(maxStam / 60, 2.0, 5.0)
end

-- =========================
-- Sounds
-- =========================
local sCommonRare = mkSound(104876050679091, false, 0.85)
local sEpic       = mkSound(100931270018375, false, 0.95)
local sLegendary  = mkSound(114654897262684, false, 1.00)

local sSpinStart  = mkSound(117570443671176, false, 0.90)
local sTick       = mkSound(4621722813, false, 0.65)
local sPopup      = mkSound(114423989561011, false, 0.90)
local sSecret     = mkSound(123444136272094, false, 1.00)

local function playFinish(rarity)
	if rarity == "Secret" then
		playSfx(sSecret)
	elseif rarity == "Legendary" then
		playSfx(sLegendary)
	elseif rarity == "Epic" then
		playSfx(sEpic)
	else
		playSfx(sCommonRare)
	end
end

local function tickPlay()
	playSfx(sTick)
end

-- =========================
-- UI ROOT
-- =========================
local gui = Instance.new("ScreenGui")
gui.Name = "TalentsUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
root.BorderSizePixel = 0
root.Parent = gui

local rCorner = Instance.new("UICorner"); rCorner.CornerRadius = UDim.new(0, 16); rCorner.Parent = root
local rStroke = Instance.new("UIStroke"); rStroke.Thickness = 2; rStroke.Transparency = 0.25; rStroke.Parent = root

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

-- =========================
-- RESIZABLE UI (UIScale + drag corner)
-- =========================
local BASE_W, BASE_H = 860, 420
root.Size = UDim2.fromOffset(BASE_W, BASE_H)

local scaleValue = gui:FindFirstChild("TalentUiScale")
if not scaleValue then
	scaleValue = Instance.new("NumberValue")
	scaleValue.Name = "TalentUiScale"
	scaleValue.Value = 1
	scaleValue.Parent = gui
end

local uiScale = root:FindFirstChildOfClass("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Parent = root
end

local function computeMaxFitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920,1080)
	local maxW = vp.X * 0.94
	local maxH = vp.Y * 0.86
	local fit = math.min(maxW / BASE_W, maxH / BASE_H)
	return clamp(fit, 0.65, 1.60)
end

local function applyScale(newScale)
	local maxFit = computeMaxFitScale()
	newScale = clamp(newScale, 0.65, maxFit)
	uiScale.Scale = newScale
	scaleValue.Value = newScale
end

applyScale(scaleValue.Value > 0 and scaleValue.Value or computeMaxFitScale())

task.spawn(function()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			applyScale(uiScale.Scale)
		end)
	end
end)

-- =========================
-- Top controls
-- =========================
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(34, 34)
closeBtn.Position = UDim2.new(1, -34, 0, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 120, 120)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(18,18,24)
closeBtn.Parent = root
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = closeBtn

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1,0,0,30)
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(245,245,255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "TALENTS"
title.Parent = root

local tokensLbl = Instance.new("TextLabel")
tokensLbl.BackgroundTransparency = 1
tokensLbl.Position = UDim2.new(0,0,0,34)
tokensLbl.Size = UDim2.new(1,0,0,18)
tokensLbl.Font = Enum.Font.GothamMedium
tokensLbl.TextSize = 14
tokensLbl.TextColor3 = Color3.fromRGB(200, 235, 255)
tokensLbl.TextXAlignment = Enum.TextXAlignment.Left
tokensLbl.Text = "Tokens: --"
tokensLbl.Parent = root

local equippedTop = Instance.new("TextLabel")
equippedTop.BackgroundTransparency = 1
equippedTop.Position = UDim2.new(0,0,0,56)
equippedTop.Size = UDim2.new(1,0,0,18)
equippedTop.Font = Enum.Font.GothamBold
equippedTop.TextSize = 14
equippedTop.TextXAlignment = Enum.TextXAlignment.Left
equippedTop.TextColor3 = Color3.fromRGB(180, 255, 200)
equippedTop.Text = "Equipped: --"
equippedTop.Parent = root

-- Pity label
local pityLbl = Instance.new("TextLabel")
pityLbl.BackgroundTransparency = 1
pityLbl.Position = UDim2.new(0,0,0,74)
pityLbl.Size = UDim2.new(1,0,0,16)
pityLbl.Font = Enum.Font.GothamBold
pityLbl.TextSize = 12
pityLbl.TextColor3 = Color3.fromRGB(190,200,220)
pityLbl.TextXAlignment = Enum.TextXAlignment.Left
pityLbl.Text = "Pity: --/--"
pityLbl.Parent = root

-- Scale label
local scaleLbl = Instance.new("TextLabel")
scaleLbl.BackgroundTransparency = 1
scaleLbl.AnchorPoint = Vector2.new(1,0)
scaleLbl.Position = UDim2.new(1, -54, 0, 6)
scaleLbl.Size = UDim2.fromOffset(90, 20)
scaleLbl.Font = Enum.Font.GothamBold
scaleLbl.TextSize = 12
scaleLbl.TextColor3 = Color3.fromRGB(190,200,220)
scaleLbl.TextXAlignment = Enum.TextXAlignment.Right
scaleLbl.Text = ""
scaleLbl.Parent = root

local function updateScaleLabel()
	scaleLbl.Text = ("UI %d%%"):format(math.floor(uiScale.Scale * 100 + 0.5))
end
updateScaleLabel()

-- Resize handle
local resizeHandle = Instance.new("Frame")
resizeHandle.AnchorPoint = Vector2.new(1,1)
resizeHandle.Position = UDim2.new(1, -8, 1, -8)
resizeHandle.Size = UDim2.fromOffset(28, 28)
resizeHandle.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
resizeHandle.BackgroundTransparency = 0.05
resizeHandle.BorderSizePixel = 0
resizeHandle.Parent = root
resizeHandle.ZIndex = 50
local rhc = Instance.new("UICorner"); rhc.CornerRadius = UDim.new(0, 10); rhc.Parent = resizeHandle
local rhs = Instance.new("UIStroke"); rhs.Thickness = 2; rhs.Transparency = 0.65; rhs.Parent = resizeHandle

local rhText = Instance.new("TextLabel")
rhText.BackgroundTransparency = 1
rhText.Size = UDim2.fromScale(1,1)
rhText.Font = Enum.Font.GothamBlack
rhText.TextSize = 16
rhText.TextColor3 = Color3.fromRGB(245,245,255)
rhText.Text = "↘"
rhText.Parent = resizeHandle
rhText.ZIndex = 51

local resizing = false
local startMouse = nil
local startScale = 1

local function getMousePos()
	return UserInputService:GetMouseLocation()
end

resizeHandle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		resizing = true
		startMouse = getMousePos()
		startScale = uiScale.Scale
	end
end)

resizeHandle.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		resizing = false
		startMouse = nil
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not resizing then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end

	local nowPos = getMousePos()
	if not startMouse then return end

	local dx = (nowPos.X - startMouse.X)
	local dy = (nowPos.Y - startMouse.Y)

	local fx = dx / BASE_W
	local fy = dy / BASE_H
	local factor = 1 + ((fx + fy) * 0.75)

	applyScale(startScale * factor)
	updateScaleLabel()
end)

-- =========================
-- Left card
-- =========================
local card = Instance.new("Frame")
card.Position = UDim2.new(0,0,0,94)
card.Size = UDim2.new(0.62, -10, 1, -108)
card.BackgroundColor3 = Color3.fromRGB(12,12,18)
card.BorderSizePixel = 0
card.Parent = root
local cardCorner = Instance.new("UICorner"); cardCorner.CornerRadius = UDim.new(0, 14); cardCorner.Parent = card
local cardStroke = Instance.new("UIStroke"); cardStroke.Thickness = 2; cardStroke.Transparency = 0.55; cardStroke.Parent = card

local rarityLbl = Instance.new("TextLabel")
rarityLbl.BackgroundTransparency = 1
rarityLbl.Position = UDim2.new(0,12,0,10)
rarityLbl.Size = UDim2.new(1,-24,0,18)
rarityLbl.Font = Enum.Font.GothamBlack
rarityLbl.TextSize = 14
rarityLbl.TextXAlignment = Enum.TextXAlignment.Left
rarityLbl.Text = "—"
rarityLbl.TextColor3 = Color3.fromRGB(255,255,255)
rarityLbl.Parent = card

local nameLbl = Instance.new("TextLabel")
nameLbl.BackgroundTransparency = 1
nameLbl.Position = UDim2.new(0,12,0,34)
nameLbl.Size = UDim2.new(1,-24,0,28)
nameLbl.Font = Enum.Font.GothamBlack
nameLbl.TextSize = 22
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.Text = "Spin to get a Talent"
nameLbl.TextColor3 = Color3.fromRGB(245,245,255)
nameLbl.Parent = card

local detailsBtn = Instance.new("TextButton")
detailsBtn.BackgroundTransparency = 1
detailsBtn.Position = UDim2.new(0,12,0,70)
detailsBtn.Size = UDim2.new(1,-24,0,18)
detailsBtn.Font = Enum.Font.GothamMedium
detailsBtn.TextSize = 13
detailsBtn.TextXAlignment = Enum.TextXAlignment.Left
detailsBtn.TextColor3 = Color3.fromRGB(170, 210, 255)
detailsBtn.Text = "View details"
detailsBtn.AutoButtonColor = false
detailsBtn.Parent = card

local hintLbl = Instance.new("TextLabel")
hintLbl.BackgroundTransparency = 1
hintLbl.Position = UDim2.new(0,12,0,92)
hintLbl.Size = UDim2.new(1,-24,0,18)
hintLbl.Font = Enum.Font.Gotham
hintLbl.TextSize = 12
hintLbl.TextXAlignment = Enum.TextXAlignment.Left
hintLbl.TextColor3 = Color3.fromRGB(190,200,220)
hintLbl.Text = "Talents are passives/styles you can equip."
hintLbl.Parent = card

local errorLbl = Instance.new("TextLabel")
errorLbl.BackgroundTransparency = 1
errorLbl.Position = UDim2.new(0,12,1,-70)
errorLbl.Size = UDim2.new(1,-24,0,18)
errorLbl.Font = Enum.Font.GothamMedium
errorLbl.TextSize = 12
errorLbl.TextXAlignment = Enum.TextXAlignment.Left
errorLbl.TextColor3 = Color3.fromRGB(255,160,160)
errorLbl.Text = ""
errorLbl.Parent = card

local equipBtn = Instance.new("TextButton")
equipBtn.Position = UDim2.new(0,12,1,-44)
equipBtn.Size = UDim2.new(1,-24,0,34)
equipBtn.BackgroundColor3 = Color3.fromRGB(200,220,255)
equipBtn.BorderSizePixel = 0
equipBtn.Text = "EQUIP (ROLL FIRST)"
equipBtn.Font = Enum.Font.GothamBlack
equipBtn.TextSize = 14
equipBtn.TextColor3 = Color3.fromRGB(18,18,24)
equipBtn.Parent = card
local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(0, 12); ec.Parent = equipBtn

local spinBtn = Instance.new("TextButton")
spinBtn.Position = UDim2.new(0,0,1,-56)
spinBtn.Size = UDim2.new(0.62, -10, 0, 44)
spinBtn.BackgroundColor3 = Color3.fromRGB(255, 235, 120)
spinBtn.BorderSizePixel = 0
spinBtn.Text = isTouch() and "SPIN (TAP)" or "SPIN"
spinBtn.Font = Enum.Font.GothamBlack
spinBtn.TextSize = 18
spinBtn.TextColor3 = Color3.fromRGB(18,18,24)
spinBtn.Parent = root
local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 14); sc.Parent = spinBtn

-- =========================
-- Right list (possible talents + preferred)
-- =========================
local right = Instance.new("Frame")
right.Position = UDim2.new(0.62, 10, 0, 94)
right.Size = UDim2.new(0.38, -10, 1, -108)
right.BackgroundColor3 = Color3.fromRGB(12,12,18)
right.BackgroundTransparency = 0.10
right.BorderSizePixel = 0
right.Parent = root
local rc2 = Instance.new("UICorner"); rc2.CornerRadius = UDim.new(0, 14); rc2.Parent = right
local rs2 = Instance.new("UIStroke"); rs2.Thickness = 2; rs2.Transparency = 0.55; rs2.Parent = right

local rtitle = Instance.new("TextLabel")
rtitle.BackgroundTransparency = 1
rtitle.Position = UDim2.new(0,10,0,10)
rtitle.Size = UDim2.new(1,-20,0,18)
rtitle.Font = Enum.Font.GothamBlack
rtitle.TextSize = 14
rtitle.TextXAlignment = Enum.TextXAlignment.Left
rtitle.TextColor3 = Color3.fromRGB(245,245,255)
rtitle.Text = "POSSIBLE TALENTS"
rtitle.Parent = right

local preferredLbl = Instance.new("TextLabel")
preferredLbl.BackgroundTransparency = 1
preferredLbl.Position = UDim2.new(0,10,0,28)
preferredLbl.Size = UDim2.new(1,-90,0,16)
preferredLbl.Font = Enum.Font.GothamBold
preferredLbl.TextSize = 12
preferredLbl.TextXAlignment = Enum.TextXAlignment.Left
preferredLbl.TextColor3 = Color3.fromRGB(180,255,200)
preferredLbl.Text = "Preferred: None"
preferredLbl.Parent = right

local clearPrefBtn = Instance.new("TextButton")
clearPrefBtn.Position = UDim2.new(1,-70,0,26)
clearPrefBtn.Size = UDim2.fromOffset(60,18)
clearPrefBtn.BackgroundColor3 = Color3.fromRGB(18,20,28)
clearPrefBtn.BackgroundTransparency = 0.15
clearPrefBtn.BorderSizePixel = 0
clearPrefBtn.Text = "Clear"
clearPrefBtn.Font = Enum.Font.GothamBlack
clearPrefBtn.TextSize = 11
clearPrefBtn.TextColor3 = Color3.fromRGB(245,245,255)
clearPrefBtn.Parent = right
local cpC = Instance.new("UICorner"); cpC.CornerRadius = UDim.new(0,8); cpC.Parent = clearPrefBtn

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0,10,0,48)
scroll.Size = UDim2.new(1,-20,1,-58)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scroll.CanvasSize = UDim2.new(0,0,0,0)
scroll.Parent = right

-- Put content in a child frame (more reliable sizing)
local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Size = UDim2.new(1, 0, 0, 0)
content.Parent = scroll

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0,6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = content

-- ✅ Best case: Roblox auto canvas sizing
pcall(function()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.AutomaticSize = Enum.AutomaticSize.Y
end)

-- ✅ Fallback: manual canvas sizing that updates whenever content changes
local function updateCanvas()
	task.defer(function()
		local h = list.AbsoluteContentSize.Y + 12
		scroll.CanvasSize = UDim2.new(0, 0, 0, h)
	end)
end
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

local itemById = {}
local preferredId = ""

local function setPreferred(id)
	preferredId = tostring(id or "")
	if preferredId == "" then
		preferredLbl.Text = "Preferred: None"
		preferredLbl.TextColor3 = Color3.fromRGB(190,200,220)
		for _, ui in pairs(itemById) do
			ui.star.Text = "☆"
			ui.star.TextColor3 = Color3.fromRGB(140,140,160)
			ui.bg.BackgroundTransparency = 0.05
			ui.stroke.Transparency = 0.65
		end
		return
	end

	local t = TalentDefinitions.Get(preferredId)
	if t then
		local b = bonusForRarity(t.Rarity)
		preferredLbl.Text = ("Preferred: %s (+%s chance)"):format(t.Name, fmtPct(b))
		preferredLbl.TextColor3 = rarityColor(t.Rarity)
	else
		preferredLbl.Text = "Preferred: None"
		preferredLbl.TextColor3 = Color3.fromRGB(190,200,220)
		preferredId = ""
	end

	for tid, ui in pairs(itemById) do
		local active = (tid == preferredId)
		ui.star.Text = active and "★" or "☆"
		ui.star.TextColor3 = active and Color3.fromRGB(255,235,120) or Color3.fromRGB(140,140,160)
		ui.bg.BackgroundTransparency = active and 0.02 or 0.05
		ui.stroke.Transparency = active and 0.35 or 0.65
	end
end

clearPrefBtn.MouseButton1Click:Connect(function()
	setPreferred("")
end)

local function addPossibleItem(talentDef)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Color3.fromRGB(18,20,28)
	row.BackgroundTransparency = 0.05
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1,0,0,34)
	row.Parent = content
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = row
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Transparency = 0.65; st.Parent = row

	local name = Instance.new("TextButton")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1,-40,1,0)
	name.Position = UDim2.new(0,0,0,0)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = rarityColor(talentDef.Rarity)
	name.Text = "  " .. talentDef.Name
	name.Parent = row
	name.AutoButtonColor = false

	local star = Instance.new("TextButton")
	star.BackgroundTransparency = 1
	star.Size = UDim2.fromOffset(34,34)
	star.Position = UDim2.new(1,-34,0,0)
	star.Font = Enum.Font.GothamBlack
	star.TextSize = 16
	star.Text = "☆"
	star.TextColor3 = Color3.fromRGB(140,140,160)
	star.Parent = row
	star.AutoButtonColor = false

	local id = talentDef.Id
	itemById[id] = { bg = row, stroke = st, star = star }

	local function pick()
		playSfx(sPopup)
		setPreferred(id)
	end

	name.MouseButton1Click:Connect(pick)
	star.MouseButton1Click:Connect(pick)
end

-- ✅ Populate list but DO NOT show Secrets
for _, t in ipairs(TalentDefinitions.List) do
	if tostring(t.Rarity) ~= "Secret" then
		addPossibleItem(t)
	end
end

updateCanvas()
setPreferred("")

-- =========================
-- DETAILS MODAL
-- =========================
local detailsGui = Instance.new("Frame")
detailsGui.Visible = false
detailsGui.BackgroundColor3 = Color3.fromRGB(10,10,14)
detailsGui.BackgroundTransparency = 0.15
detailsGui.BorderSizePixel = 0
detailsGui.Size = UDim2.new(1,0,1,0)
detailsGui.Parent = gui

local modal = Instance.new("Frame")
modal.AnchorPoint = Vector2.new(0.5,0.5)
modal.Position = UDim2.fromScale(0.5,0.5)
modal.Size = UDim2.fromOffset(640, 360)
modal.BackgroundColor3 = Color3.fromRGB(14,14,20)
modal.BorderSizePixel = 0
modal.Parent = detailsGui
local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0,16); mc.Parent = modal
local ms = Instance.new("UIStroke"); ms.Thickness = 2; ms.Transparency = 0.35; ms.Parent = modal
local mp = Instance.new("UIPadding"); mp.PaddingTop=UDim.new(0,14); mp.PaddingLeft=UDim.new(0,14); mp.PaddingRight=UDim.new(0,14); mp.PaddingBottom=UDim.new(0,14); mp.Parent=modal

local modalX = Instance.new("TextButton")
modalX.Size = UDim2.fromOffset(34,34)
modalX.Position = UDim2.new(1,-34,0,0)
modalX.BackgroundColor3 = Color3.fromRGB(255,120,120)
modalX.BorderSizePixel = 0
modalX.Text = "X"
modalX.Font = Enum.Font.GothamBlack
modalX.TextSize = 16
modalX.TextColor3 = Color3.fromRGB(18,18,24)
modalX.Parent = modal
local mxc = Instance.new("UICorner"); mxc.CornerRadius = UDim.new(0,10); mxc.Parent = modalX

local modalTitle = Instance.new("TextLabel")
modalTitle.BackgroundTransparency = 1
modalTitle.Size = UDim2.new(1,-50,0,26)
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.TextSize = 18
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextColor3 = Color3.fromRGB(245,245,255)
modalTitle.Text = "Talent Details"
modalTitle.Parent = modal

local modalBody = Instance.new("ScrollingFrame")
modalBody.Position = UDim2.new(0,0,0,34)
modalBody.Size = UDim2.new(1,0,1,-34)
modalBody.BackgroundTransparency = 1
modalBody.BorderSizePixel = 0
modalBody.ScrollBarThickness = 6
modalBody.CanvasSize = UDim2.new(0,0,0,0)
modalBody.Parent = modal

local bodyList = Instance.new("UIListLayout")
bodyList.Padding = UDim.new(0,10)
bodyList.Parent = modalBody

local function bodyText(txt, bold, size, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size or 13
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1,0,0,0)
	l.Text = txt
	l.TextColor3 = color or Color3.fromRGB(210,220,240)
	l.Parent = modalBody
	return l
end

local function clearModalBody()
	for _, ch in ipairs(modalBody:GetChildren()) do
		if ch:IsA("TextLabel") or ch:IsA("Frame") then
			ch:Destroy()
		end
	end
end

local function openDetails(talentId)
	local t = TalentDefinitions.Get(talentId)
	if not t then return end

	clearModalBody()
	bodyText(t.Rarity .. " • " .. t.Name, true, 16, rarityColor(t.Rarity))
	bodyText(t.Desc or "", false, 13)

	local style = t.Style or {}
	local regen = getStyleRegen(style)

	bodyText("STYLE STATS", true, 13, Color3.fromRGB(245,245,255))
	bodyText(
		("BaseScore: %s\nStaminaMax: %s\nStaminaRegen: %s/sec\nWindowMult: %s\nSliderSpeedMult: %s\nMomentumGainMult: %s")
			:format(
				string.format("%.2f", tonumber(style.BaseScore or 0) or 0),
				tostring(style.StaminaMax or 0),
				string.format("%.2f", regen),
				string.format("%.2f", tonumber(style.WindowMult or 1) or 1),
				string.format("%.2f", tonumber(style.SliderSpeedMult or 1) or 1),
				string.format("%.2f", tonumber(style.MomentumGainMult or 1) or 1)
			),
		false,
		13
	)

	local skills = t.Skills or {}
	bodyText("SKILLS", true, 13, Color3.fromRGB(245,245,255))
	if #skills == 0 then
		bodyText("No skills.", false, 13, Color3.fromRGB(190,200,220))
	else
		for i, sk in ipairs(skills) do
			local line = ("[%d] %s  (CD %ss%s)\n%s")
				:format(
					i,
					sk.Name or sk.Id or ("Skill"..i),
					tostring(sk.Cooldown or 0),
					(sk.Duration and sk.Duration > 0) and (", Dur "..tostring(sk.Duration).."s") or "",
					sk.Desc or ""
				)
			bodyText(line, false, 13, Color3.fromRGB(210,220,240))
		end
	end

	task.defer(function()
		modalBody.CanvasSize = UDim2.new(0,0,0,bodyList.AbsoluteContentSize.Y + 12)
	end)

	detailsGui.Visible = true
end

modalX.MouseButton1Click:Connect(function()
	detailsGui.Visible = false
end)

-- =========================
-- CINEMATIC OVERLAY (Epic+)
-- =========================
local cine = Instance.new("Frame")
cine.Visible = false
cine.BackgroundColor3 = Color3.fromRGB(0,0,0)
cine.BackgroundTransparency = 1
cine.Size = UDim2.fromScale(1,1)
cine.Parent = gui

local cineGlow = Instance.new("Frame")
cineGlow.AnchorPoint = Vector2.new(0.5,0.5)
cineGlow.Position = UDim2.fromScale(0.5,0.5)
cineGlow.Size = UDim2.fromScale(1,1)
cineGlow.BackgroundColor3 = Color3.fromRGB(255,255,255)
cineGlow.BackgroundTransparency = 1
cineGlow.BorderSizePixel = 0
cineGlow.Parent = cine

local cg = Instance.new("UIGradient")
cg.Color = ColorSequence.new(Color3.fromRGB(255,110,200), Color3.fromRGB(140,210,255))
cg.Rotation = 25
cg.Parent = cineGlow

local cineText = Instance.new("TextLabel")
cineText.BackgroundTransparency = 1
cineText.AnchorPoint = Vector2.new(0.5,0.5)
cineText.Position = UDim2.fromScale(0.5,0.42)
cineText.Size = UDim2.fromOffset(900, 200)
cineText.Font = Enum.Font.GothamBlack
cineText.TextSize = 64
cineText.TextStrokeTransparency = 0.75
cineText.TextColor3 = Color3.fromRGB(255,235,120)
cineText.Text = ""
cineText.Parent = cine

local glitchBars = Instance.new("Frame")
glitchBars.BackgroundTransparency = 1
glitchBars.Size = UDim2.fromScale(1,1)
glitchBars.Visible = false
glitchBars.Parent = cine

local bars = {}
for _=1,14 do
	local b = Instance.new("Frame")
	b.BackgroundColor3 = Color3.fromRGB(255,110,200)
	b.BackgroundTransparency = 0.65
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1, 0, 0, math.random(6, 16))
	b.Position = UDim2.new(0, 0, 0, math.random(0, 720))
	b.Parent = glitchBars
	table.insert(bars, b)
end

local shakeOn = false
local shakeUntil = 0
local glitchOn = false
local glitchUntil = 0
local baseCamCF = nil

RunService.RenderStepped:Connect(function()
	if not cine.Visible then return end

	local now = tick()
	local cam = workspace.CurrentCamera

	if shakeOn and now <= shakeUntil and cam then
		if not baseCamCF then baseCamCF = cam.CFrame end
		local mag = 0.25
		local dx = (math.random() - 0.5) * mag
		local dy = (math.random() - 0.5) * mag
		cam.CFrame = baseCamCF * CFrame.new(dx, dy, 0)
	elseif shakeOn and now > shakeUntil then
		shakeOn = false
		if cam and baseCamCF then cam.CFrame = baseCamCF end
		baseCamCF = nil
	end

	if glitchOn and now <= glitchUntil then
		glitchBars.Visible = true
		local h = math.max(0, gui.AbsoluteSize.Y - 20)
		for _, b in ipairs(bars) do
			b.Position = UDim2.new(0, 0, 0, math.random(0, h))
			b.Size = UDim2.new(1, 0, 0, math.random(6, 18))
			b.BackgroundTransparency = 0.55 + math.random() * 0.35
		end
	else
		glitchBars.Visible = false
	end
end)

local function playCinematic(rarity)
	if not isEpicPlus(rarity) then return end

	cine.Visible = true
	cine.BackgroundTransparency = 1
	cineGlow.BackgroundTransparency = 1
	cineText.Text = string.upper(rarity) .. "!"
	cineText.TextColor3 = rarityColor(rarity)
	cineText.TextTransparency = 1

	playSfx(sPopup)
	tween(cine, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.35})
	tween(cineGlow, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.85})
	tween(cineText, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})

	if rarity == "Secret" then
		playSfx(sSecret)
		shakeOn = true
		shakeUntil = tick() + 1.2
		glitchOn = true
		glitchUntil = tick() + 1.25
		cineText.Text = "SECRET!!!"
	end

	task.delay(1.1, function()
		tween(cineText, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
		tween(cineGlow, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
		tween(cine, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
		task.delay(0.32, function()
			cine.Visible = false
			glitchOn = false
			glitchBars.Visible = false
		end)
	end)
end

-- =========================
-- LUCKY SPIN OVERLAY (Pity Spin)
-- =========================
local DEFAULT_PITY_MAX = 60
if player:GetAttribute("TalentPityMax") == nil then
	player:SetAttribute("TalentPityMax", DEFAULT_PITY_MAX)
end
if player:GetAttribute("TalentPity") == nil then
	player:SetAttribute("TalentPity", 0)
end

local lucky = Instance.new("Frame")
lucky.Visible = false
lucky.BackgroundColor3 = Color3.new(0,0,0)
lucky.BackgroundTransparency = 1
lucky.Size = UDim2.fromScale(1,1)
lucky.Parent = gui

local luckyGlow = Instance.new("Frame")
luckyGlow.AnchorPoint = Vector2.new(0.5,0.5)
luckyGlow.Position = UDim2.fromScale(0.5,0.5)
luckyGlow.Size = UDim2.fromScale(1,1)
luckyGlow.BackgroundColor3 = Color3.new(1,1,1)
luckyGlow.BackgroundTransparency = 1
luckyGlow.BorderSizePixel = 0
luckyGlow.Parent = lucky

local luckyGrad = Instance.new("UIGradient")
luckyGrad.Rotation = 25
luckyGrad.Color = ColorSequence.new(
	Color3.fromRGB(255,235,120),
	Color3.fromRGB(205,140,255)
)
luckyGrad.Parent = luckyGlow

local luckyText = Instance.new("TextLabel")
luckyText.BackgroundTransparency = 1
luckyText.AnchorPoint = Vector2.new(0.5,0.5)
luckyText.Position = UDim2.fromScale(0.5,0.42)
luckyText.Size = UDim2.fromOffset(900, 180)
luckyText.Font = Enum.Font.GothamBlack
luckyText.TextSize = 58
luckyText.TextStrokeTransparency = 0.75
luckyText.TextColor3 = Color3.fromRGB(255,235,120)
luckyText.Text = "LUCKY SPIN!"
luckyText.TextTransparency = 1
luckyText.Parent = lucky

local luckyScale = Instance.new("UIScale")
luckyScale.Scale = 1
luckyScale.Parent = luckyText

local luckyBusy = false
local function playLuckySpin()
	if luckyBusy then return end
	luckyBusy = true

	lucky.Visible = true
	lucky.BackgroundTransparency = 1
	luckyGlow.BackgroundTransparency = 1
	luckyText.TextTransparency = 1
	luckyScale.Scale = 0.92
	luckyText.Rotation = -2

	playSfx(sPopup)

	tween(lucky, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.40})
	tween(luckyGlow, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.80})
	tween(luckyText, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {TextTransparency = 0})
	tween(luckyScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.03})

	task.delay(0.18, function()
		tween(luckyScale, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.08})
		tween(luckyText, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Rotation = 2})
	end)

	task.delay(0.65, function()
		tween(luckyText, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
		tween(lucky, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
	tween(luckyGlow, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
		task.delay(0.30, function()
			lucky.Visible = false
			luckyBusy = false
		end)
	end)
end

-- =========================
-- STATE / SYNC
-- =========================
local lastTalentId = ""
local lastTalentRarity = "Common"

local function setEquippedFromId(eqId)
	eqId = tostring(eqId or "")
	if eqId == "" then
		equippedTop.Text = "Equipped: --"
		equippedTop.TextColor3 = Color3.fromRGB(180,255,200)
		return
	end
	local t = TalentDefinitions.Get(eqId)
	if t then
		equippedTop.Text = "Equipped: " .. t.Name
		equippedTop.TextColor3 = rarityColor(t.Rarity)
	else
		equippedTop.Text = "Equipped: --"
	end
end

local function updateTokens()
	tokensLbl.Text = "Tokens: " .. tostring(player:GetAttribute("TalentTokens") or 0)
end

local function updatePityUI()
	local pity = tonumber(player:GetAttribute("TalentPity")) or 0
	local maxV = tonumber(player:GetAttribute("TalentPityMax")) or DEFAULT_PITY_MAX

	local nextLucky = (pity >= (maxV - 1))
	if nextLucky then
		pityLbl.Text = ("Pity: %d/%d  •  NEXT SPIN: LUCKY"):format(pity, maxV)
		pityLbl.TextColor3 = Color3.fromRGB(255,235,120)
	else
		pityLbl.Text = ("Pity: %d/%d"):format(pity, maxV)
		pityLbl.TextColor3 = Color3.fromRGB(190,200,220)
	end
end

player:GetAttributeChangedSignal("TalentTokens"):Connect(updateTokens)
player:GetAttributeChangedSignal("EquippedTalent"):Connect(function()
	setEquippedFromId(player:GetAttribute("EquippedTalent"))
end)
player:GetAttributeChangedSignal("TalentPity"):Connect(updatePityUI)
player:GetAttributeChangedSignal("TalentPityMax"):Connect(updatePityUI)

updateTokens()
setEquippedFromId(player:GetAttribute("EquippedTalent"))
updatePityUI()

local function setCard(talent)
	lastTalentId = talent.id or ""
	lastTalentRarity = talent.rarity or "Common"

	rarityLbl.Text = (talent.rarity or "—")
	rarityLbl.TextColor3 = rarityColor(talent.rarity)
	nameLbl.Text = talent.name or "—"

	hintLbl.Text = "Click 'View details' to see full info + skills."
	equipBtn.Text = (lastTalentId ~= "" and ("EQUIP: " .. (talent.name or ""))) or "EQUIP (ROLL FIRST)"
end

-- =========================
-- Open / Close UI (T)
-- =========================
local function openUI()
	gui.Enabled = true
	playSfx(sPopup)

	applyScale(uiScale.Scale)
	updateScaleLabel()

	root.Position = UDim2.fromScale(0.5, 0.55)
	tween(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=UDim2.fromScale(0.5,0.5)})

	TalentEvent:FireServer("RequestState", {})
end

local function closeUI()
	tween(root, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position=UDim2.fromScale(0.5,0.55)})
	task.delay(0.17, function() gui.Enabled = false end)
	detailsGui.Visible = false
end

closeBtn.MouseButton1Click:Connect(closeUI)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.T then
		if gui.Enabled then closeUI() else openUI() end
	end
end)

-- View details (single connection)
detailsBtn.MouseButton1Click:Connect(function()
	if lastTalentId ~= "" then openDetails(lastTalentId) end
end)

-- =========================
-- Fake spinner (ONE PASS)
-- =========================
local pool = TalentDefinitions.List

local function rarityExtraTime(r)
	if r == "Secret" then return 1.25 end
	if r == "Legendary" then return 0.85 end
	if r == "Epic" then return 0.55 end
	return 0.10 end

local function slowBoost(r)
	if r == "Secret" then return 2.4 end
	if r == "Legendary" then return 1.9 end
	if r == "Epic" then return 1.4 end
	return 1.0
end

local function runSingleSpinToResult(invokeFn)
	local startT = tick()
	local minRun = 1.55

	local result = nil
	local got = false

	task.spawn(function()
		local ok, res = pcall(invokeFn)
		if ok then
			result = res
		else
			result = { ok = false, err = tostring(res) }
		end
		got = true
	end)

	local endT = startT + minRun
	local extended = false

	while true do
		local now = tick()

		if got and not extended and result and result.ok == true and result.talent then
			local rar = tostring(result.talent.rarity or "Common")
			endT = math.max(endT, now + rarityExtraTime(rar))
			extended = true
		end

		if now >= endT and got then break end

		if not got then
			local pick = pool[math.random(1, #pool)]
			setCard({ id = pick.Id, name = pick.Name, rarity = pick.Rarity })
			tickPlay()
			task.wait(0.045)
		else
			local rolled = (result and result.ok == true) and result.talent or nil
			local rar = rolled and tostring(rolled.rarity or "Common") or "Common"

			local t01 = clamp((now - startT) / math.max(0.001, (endT - startT)), 0, 1)
			local delayTime = 0.03 + (t01 * t01) * (0.24 * slowBoost(rar))

			if rolled and (endT - now) < 0.35 then
				setCard(rolled)
			else
				local pick = pool[math.random(1, #pool)]
				setCard({ id = pick.Id, name = pick.Name, rarity = pick.Rarity })
			end

			tickPlay()
			task.wait(delayTime)
		end
	end

	return result
end

-- =========================
-- SPIN (force equip + preferred + pity lucky animation)
-- =========================
local spinning = false

local function isNextSpinLucky()
	local pity = tonumber(player:GetAttribute("TalentPity")) or 0
	local maxV = tonumber(player:GetAttribute("TalentPityMax")) or DEFAULT_PITY_MAX
	return pity >= (maxV - 1)
end

local function clientFallbackUpdatePityAfterRoll(rolledRarity)
	local pity = tonumber(player:GetAttribute("TalentPity")) or 0
	local maxV = tonumber(player:GetAttribute("TalentPityMax")) or DEFAULT_PITY_MAX

	if isEpicPlus(rolledRarity) then
		pity = 0
	else
		pity = clamp(pity + 1, 0, maxV)
	end

	player:SetAttribute("TalentPity", pity)
	updatePityUI()
end

spinBtn.MouseButton1Click:Connect(function()
	if spinning then return end
	errorLbl.Text = ""

	spinning = true
	spinBtn.Active = false
	spinBtn.Text = "SPINNING..."
	equipBtn.Text = "EQUIP (ROLL FIRST)"
	equipBtn.AutoButtonColor = true

	if isNextSpinLucky() then
		playLuckySpin()
	end

	playSfx(sSpinStart)

	local res = runSingleSpinToResult(function()
		return SpinTalent:InvokeServer({ preferredId = preferredId })
	end)

	spinning = false
	spinBtn.Active = true
	spinBtn.Text = isTouch() and "SPIN (TAP)" or "SPIN"

	if not res or res.ok ~= true then
		errorLbl.Text = "Spin failed: " .. tostring(res and res.err or "No response")
		return
	end

	local rolled = res.talent
	if not rolled then
		errorLbl.Text = "Spin failed: Missing talent."
		return
	end

	setCard(rolled)
	updateTokens()

	local gotServerPity = false
	if res.pity ~= nil then
		player:SetAttribute("TalentPity", tonumber(res.pity) or player:GetAttribute("TalentPity"))
		gotServerPity = true
	end
	if res.pityMax ~= nil then
		player:SetAttribute("TalentPityMax", tonumber(res.pityMax) or player:GetAttribute("TalentPityMax"))
		gotServerPity = true
	end
	if not gotServerPity then
		clientFallbackUpdatePityAfterRoll(tostring(rolled.rarity or "Common"))
	else
		updatePityUI()
	end

	local equipId = (res.equipped and res.equipped.id) or rolled.id
	if equipId then
		player:SetAttribute("EquippedTalent", equipId)
		setEquippedFromId(equipId)
		TalentEvent:FireServer("Equip", { id = equipId })
	end

	local rar = tostring(rolled.rarity or "Common")
	playFinish(rar)

	if isEpicPlus(rar) then
		playCinematic(rar)
	end

	equipBtn.Text = "EQUIPPED ✅"
	equipBtn.AutoButtonColor = false
end)

-- manual equip still supported
equipBtn.MouseButton1Click:Connect(function()
	if lastTalentId == "" then
		errorLbl.Text = "Roll a talent first."
		return
	end
	TalentEvent:FireServer("Equip", { id = lastTalentId })
end)

-- =========================
-- Server sync
-- =========================
TalentEvent.OnClientEvent:Connect(function(action, payload)
	payload = (typeof(payload) == "table") and payload or {}

	if action == "State" then
		if payload.tokens ~= nil then
			player:SetAttribute("TalentTokens", payload.tokens)
		end
		if payload.pity ~= nil then
			player:SetAttribute("TalentPity", payload.pity)
		end
		if payload.pityMax ~= nil then
			player:SetAttribute("TalentPityMax", payload.pityMax)
		end
		if payload.equipped and payload.equipped.id then
			player:SetAttribute("EquippedTalent", payload.equipped.id)
			setEquippedFromId(payload.equipped.id)
		end
		updateTokens()
		updatePityUI()
		return
	end

	if action == "Equipped" then
		local id = tostring(payload.id or "")
		player:SetAttribute("EquippedTalent", id)
		setEquippedFromId(id)
		return
	end
end)

print("[TalentsClient] Loaded ✅ (Resizable + Preferred + Cinematic Spinner + Pity + Lucky Spin)")
