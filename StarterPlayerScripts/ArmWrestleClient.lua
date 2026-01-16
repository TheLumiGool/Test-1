-- StarterPlayerScripts/ArmWrestleClient (LocalScript)
-- FULL DROP-IN OVERWRITE (MatchLog + Combo + Talent in Title + 0-stamina gate)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("ArmWrestleRemotes")
local ArmWrestleEvent = remotes:WaitForChild("ArmWrestleEvent")

local TalentDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))

-- =========================
-- Helpers
-- =========================
local function clamp(x,a,b) return math.max(a, math.min(b, x)) end

local function pingpong01(x)
	local m = x % 2
	if m <= 1 then return m else return 2 - m end
end

local function tween(obj, ti, props)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

local function mkSound(id, looped, vol)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://"..tostring(id)
	s.Looped = looped or false
	s.Volume = vol or 0.7
	s.Parent = SoundService
	return s
end

local function playSfx(s: Sound?)
	if not s then return end
	pcall(function() s.TimePosition = 0 end)
	s:Play()
end

-- =========================
-- CONFIG
-- =========================
local SPEEDUP_K = 0.010 -- matches server (acceleration; server is deterministic)

local UI_POP_SFX_ID      = 114423989561011
local SLIDER_EDGE_SFX_ID = 421058925
local HIT_SFX_ID         = 9065073444
local MISS_SFX_ID        = 134331137972640
local GO_SOUND_ID        = 84766291779256

local BGM_IDS = {
	92502031357601,
	103727059299317,
}

local function pointerAtTime(baseSpeed, tSinceStart, speedup)
	local accel = speedup or SPEEDUP_K
	local phase = baseSpeed * (tSinceStart + 0.5 * accel * (tSinceStart * tSinceStart))
	return pingpong01(phase)
end

-- =========================
-- Talent/Skills
-- =========================
local function getEquippedTalentId()
	return tostring(player:GetAttribute("EquippedTalent") or "")
end

local function getTalent()
	local id = getEquippedTalentId()
	if id == "" then return nil end
	return TalentDefinitions.Get(id)
end

local function getTalentName()
	local t = getTalent()
	return t and tostring(t.Name or t.Id or "Talent") or "No Talent"
end

local function getSkills()
	local t = getTalent()
	if t and typeof(t.Skills) == "table" then
		return t.Skills
	end
	return {}
end

local function getSkillName(sk, idx)
	if not sk then return ("Skill %d"):format(idx) end
	return tostring(sk.Name or sk.Id or ("Skill "..idx))
end

local function getSkillCost(sk)
	if not sk or typeof(sk.Effects) ~= "table" then return 0 end
	return tonumber(sk.Effects.StaminaCost) or 0
end

-- =========================
-- Sounds
-- =========================
local goSound = mkSound(GO_SOUND_ID, false, 0.9)
local bgm = mkSound(BGM_IDS[math.random(1,#BGM_IDS)], true, 0.25)

local uiPopSfx = mkSound(UI_POP_SFX_ID, false, 0.8)
local edgeSfx  = mkSound(SLIDER_EDGE_SFX_ID, false, 0.7)
local hitSfx   = mkSound(HIT_SFX_ID, false, 0.75)
local missSfx  = mkSound(MISS_SFX_ID, false, 0.75)

-- =========================
-- UI Root
-- =========================
local gui = Instance.new("ScreenGui")

gui.Name = "ArmWrestleUI"


gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.fromScale(0.5, 0.98)
panel.Size = UDim2.fromOffset(980, 320)
panel.BackgroundColor3 = Color3.fromRGB(14,14,20)
panel.BorderSizePixel = 0
panel.Parent = gui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel
local ps = Instance.new("UIStroke"); ps.Thickness = 2; ps.Transparency = 0.4; ps.Parent = panel
local grad = Instance.new("UIGradient")
grad.Rotation = 20
grad.Color = ColorSequence.new(Color3.fromRGB(45, 30, 85), Color3.fromRGB(10, 70, 80))
grad.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = panel

-- Header
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1,0,0,22)
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(245,245,255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "ARM WRESTLE — "..getTalentName()
title.Parent = panel

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.new(0,0,0,24)
sub.Size = UDim2.new(1,0,0,18)
sub.Font = Enum.Font.GothamMedium
sub.TextSize = 13
sub.TextColor3 = Color3.fromRGB(190,200,220)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Text = "Table: --  |  Opponent: --"
sub.Parent = panel

local statusRight = Instance.new("TextLabel")
statusRight.BackgroundTransparency = 1
statusRight.Position = UDim2.new(1,-180,0,0)
statusRight.Size = UDim2.fromOffset(180,22)
statusRight.Font = Enum.Font.GothamBlack
statusRight.TextSize = 14
statusRight.TextColor3 = Color3.fromRGB(255,235,120)
statusRight.TextXAlignment = Enum.TextXAlignment.Right
statusRight.Text = "WAIT"
statusRight.Parent = panel

local errorRight = Instance.new("TextLabel")
errorRight.BackgroundTransparency = 1
errorRight.Position = UDim2.new(1,-420,0,24)
errorRight.Size = UDim2.fromOffset(420,18)
errorRight.Font = Enum.Font.GothamMedium
errorRight.TextSize = 12
errorRight.TextColor3 = Color3.fromRGB(255,160,160)
errorRight.TextXAlignment = Enum.TextXAlignment.Right
errorRight.Text = ""
errorRight.Parent = panel
local ERROR_COLOR = errorRight.TextColor3

local function flashError(msg)
	errorRight.Text = tostring(msg or "")
	errorRight.TextTransparency = 0
	errorRight.TextColor3 = ERROR_COLOR
	task.delay(1.6, function()
		tween(errorRight, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency=1})
	end)
end

local function flashNotice(msg)
	errorRight.Text = tostring(msg or "")
	errorRight.TextTransparency = 0
	errorRight.TextColor3 = Color3.fromRGB(255,235,120)
	task.delay(1.2, function()
		tween(errorRight, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency=1})
		task.delay(0.3, function()
			errorRight.TextColor3 = ERROR_COLOR
		end)
	end)
end

local scoreLbl = Instance.new("TextLabel")
scoreLbl.BackgroundTransparency = 1
scoreLbl.Position = UDim2.new(0,0,0,44)
scoreLbl.Size = UDim2.new(1,0,0,18)
scoreLbl.Font = Enum.Font.GothamBold
scoreLbl.TextSize = 14
scoreLbl.TextColor3 = Color3.fromRGB(245,245,255)
scoreLbl.TextXAlignment = Enum.TextXAlignment.Left
scoreLbl.Text = "Ticks: 0 - 0   |   Wins: 0 - 0"
scoreLbl.Parent = panel

-- Tug bar
local tug = Instance.new("Frame")
tug.Position = UDim2.new(0,0,0,66)
tug.Size = UDim2.new(0.66,0,0,18)
tug.BackgroundColor3 = Color3.fromRGB(10,10,14)
tug.BorderSizePixel = 0
tug.Parent = panel
local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 10); tc.Parent = tug
local ts = Instance.new("UIStroke"); ts.Thickness = 2; ts.Transparency = 0.55; ts.Parent = tug

local centerLine = Instance.new("Frame")
centerLine.AnchorPoint = Vector2.new(0.5, 0.5)
centerLine.Position = UDim2.fromScale(0.5, 0.5)
centerLine.Size = UDim2.new(0, 4, 1, -4)
centerLine.BackgroundColor3 = Color3.fromRGB(200,200,220)
centerLine.BackgroundTransparency = 0.6
centerLine.BorderSizePixel = 0
centerLine.Parent = tug

local tugKnob = Instance.new("Frame")
tugKnob.AnchorPoint = Vector2.new(0.5, 0.5)
tugKnob.Position = UDim2.fromScale(0.5, 0.5)
tugKnob.Size = UDim2.fromOffset(14, 14)
tugKnob.BackgroundColor3 = Color3.fromRGB(255,235,120)
tugKnob.BorderSizePixel = 0
tugKnob.Parent = tug
local tkc = Instance.new("UICorner"); tkc.CornerRadius = UDim.new(1, 0); tkc.Parent = tugKnob

local tugText = Instance.new("TextLabel")
tugText.BackgroundTransparency = 1
tugText.Position = UDim2.new(0,0,1,0)
tugText.Size = UDim2.new(1,0,0,16)
tugText.Font = Enum.Font.GothamBold
tugText.TextSize = 11
tugText.TextColor3 = Color3.fromRGB(245,245,255)
tugText.TextXAlignment = Enum.TextXAlignment.Left
tugText.Text = "Neutral"
tugText.Parent = tug

-- Slider
local sliderWrap = Instance.new("Frame")
sliderWrap.Position = UDim2.new(0,0,0,90)
sliderWrap.Size = UDim2.new(0.66,0,0,44)
sliderWrap.BackgroundColor3 = Color3.fromRGB(10,10,14)
sliderWrap.BorderSizePixel = 0
sliderWrap.Parent = panel
local swc = Instance.new("UICorner"); swc.CornerRadius = UDim.new(0, 12); swc.Parent = sliderWrap
local sws = Instance.new("UIStroke"); sws.Thickness = 2; sws.Transparency = 0.55; sws.Parent = sliderWrap

local zoneOK = Instance.new("Frame")
zoneOK.AnchorPoint = Vector2.new(0.5, 0.5)
zoneOK.Position = UDim2.fromScale(0.5, 0.5)
zoneOK.Size = UDim2.fromScale(0.22, 0.70)
zoneOK.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
zoneOK.BackgroundTransparency = 0.75
zoneOK.BorderSizePixel = 0
zoneOK.Parent = sliderWrap
local zokc = Instance.new("UICorner"); zokc.CornerRadius = UDim.new(0, 10); zokc.Parent = zoneOK

local zoneGOOD = Instance.new("Frame")
zoneGOOD.AnchorPoint = Vector2.new(0.5, 0.5)
zoneGOOD.Position = UDim2.fromScale(0.5, 0.5)
zoneGOOD.Size = UDim2.fromScale(0.14, 0.78)
zoneGOOD.BackgroundColor3 = Color3.fromRGB(140, 210, 255)
zoneGOOD.BackgroundTransparency = 0.70
zoneGOOD.BorderSizePixel = 0
zoneGOOD.Parent = sliderWrap
local zgc = Instance.new("UICorner"); zgc.CornerRadius = UDim.new(0, 10); zgc.Parent = zoneGOOD

local zonePERF = Instance.new("Frame")
zonePERF.AnchorPoint = Vector2.new(0.5, 0.5)
zonePERF.Position = UDim2.fromScale(0.5, 0.5)
zonePERF.Size = UDim2.fromScale(0.07, 0.86)
zonePERF.BackgroundColor3 = Color3.fromRGB(255, 235, 120)
zonePERF.BackgroundTransparency = 0.60
zonePERF.BorderSizePixel = 0
zonePERF.Parent = sliderWrap
local zpc = Instance.new("UICorner"); zpc.CornerRadius = UDim.new(0, 10); zpc.Parent = zonePERF
local zps = Instance.new("UIStroke"); zps.Thickness = 2; zps.Transparency = 0.35; zps.Parent = zonePERF

local pointer = Instance.new("Frame")
pointer.AnchorPoint = Vector2.new(0.5, 0.5)
pointer.Position = UDim2.fromScale(0.5, 0.5)
pointer.Size = UDim2.new(0, 6, 1, -10)
pointer.BackgroundColor3 = Color3.fromRGB(245,245,255)
pointer.BorderSizePixel = 0
pointer.Parent = sliderWrap

local clickMark = Instance.new("Frame")
clickMark.AnchorPoint = Vector2.new(0.5, 0.5)
clickMark.Position = UDim2.fromScale(0.5, 0.5)
clickMark.Size = UDim2.new(0, 3, 1, -6)
clickMark.BackgroundColor3 = Color3.fromRGB(255,160,160)
clickMark.BackgroundTransparency = 1
clickMark.BorderSizePixel = 0
clickMark.Parent = sliderWrap

-- Stats
local stamLbl = Instance.new("TextLabel")
stamLbl.BackgroundTransparency = 1
stamLbl.Position = UDim2.new(0,0,0,140)
stamLbl.Size = UDim2.new(1,0,0,18)
stamLbl.Font = Enum.Font.GothamMedium
stamLbl.TextSize = 13
stamLbl.TextColor3 = Color3.fromRGB(190,200,220)
stamLbl.TextXAlignment = Enum.TextXAlignment.Left
stamLbl.Text = "Stamina: -- / --"
stamLbl.Parent = panel

local momLbl = Instance.new("TextLabel")
momLbl.BackgroundTransparency = 1
momLbl.Position = UDim2.new(0,0,0,160)
momLbl.Size = UDim2.new(1,0,0,18)
momLbl.Font = Enum.Font.GothamBold
momLbl.TextSize = 13
momLbl.TextColor3 = Color3.fromRGB(245,245,255)
momLbl.TextXAlignment = Enum.TextXAlignment.Left
momLbl.Text = "Momentum: 0%"
momLbl.Parent = panel

-- ✅ Combo counter label
local comboLbl = Instance.new("TextLabel")
comboLbl.BackgroundTransparency = 1
comboLbl.Position = UDim2.new(0,0,0,178)
comboLbl.Size = UDim2.new(1,0,0,16)
comboLbl.Font = Enum.Font.GothamBlack
comboLbl.TextSize = 12
comboLbl.TextColor3 = Color3.fromRGB(255,235,120)
comboLbl.TextXAlignment = Enum.TextXAlignment.Left
comboLbl.Text = "Combo x0"
comboLbl.Parent = panel

-- Skills area
local skillsFrame = Instance.new("Frame")
skillsFrame.Position = UDim2.new(0,0,0,196)
skillsFrame.Size = UDim2.new(0.66,0,0,58)
skillsFrame.BackgroundTransparency = 1
skillsFrame.Parent = panel

local skillsTitle = Instance.new("TextLabel")
skillsTitle.BackgroundTransparency = 1
skillsTitle.Position = UDim2.new(0,0,0,0)
skillsTitle.Size = UDim2.new(1,0,0,16)
skillsTitle.Font = Enum.Font.GothamBlack
skillsTitle.TextSize = 12
skillsTitle.TextXAlignment = Enum.TextXAlignment.Left
skillsTitle.TextColor3 = Color3.fromRGB(245,245,255)
skillsTitle.Text = "SKILLS (1/2/3 or Q/E/R)"
skillsTitle.Parent = skillsFrame

local skillButtons, skillNameLbl, skillCdLbl, skillCostLbl, skillStrokes, skillGlows = {}, {}, {}, {}, {}, {}

local function makeSkillButton(i)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = Color3.fromRGB(18,20,28)
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1/3, -8, 0, 36)
	b.Position = UDim2.new((i-1)/3, (i==1 and 0 or 4), 0, 20)
	b.Text = ""
	b.Parent = skillsFrame
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = b
	local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Transparency = 0.7; bs.Color = Color3.fromRGB(110,110,130); bs.Parent = b

	local glow = Instance.new("Frame")
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1,1)
	glow.ZIndex = 0
	glow.Parent = b
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 10); gc.Parent = glow

	local keyLbl = Instance.new("TextLabel")
	keyLbl.BackgroundTransparency = 1
	keyLbl.Position = UDim2.new(0,8,0,6)
	keyLbl.Size = UDim2.new(0,24,0,16)
	keyLbl.Font = Enum.Font.GothamBlack
	keyLbl.TextSize = 12
	keyLbl.TextXAlignment = Enum.TextXAlignment.Left
	keyLbl.TextColor3 = Color3.fromRGB(255,235,120)
	keyLbl.Text = tostring(i)
	keyLbl.Parent = b

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0,34,0,4)
	name.Size = UDim2.new(1,-42,0,16)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(245,245,255)
	name.Text = "—"
	name.Parent = b

	local cd = Instance.new("TextLabel")
	cd.BackgroundTransparency = 1
	cd.Position = UDim2.new(0,34,0,20)
	cd.Size = UDim2.new(1,-42,0,14)
	cd.Font = Enum.Font.GothamMedium
	cd.TextSize = 11
	cd.TextXAlignment = Enum.TextXAlignment.Left
	cd.TextColor3 = Color3.fromRGB(190,200,220)
	cd.Text = ""
	cd.Parent = b

	local cost = Instance.new("TextLabel")
	cost.BackgroundTransparency = 1
	cost.Position = UDim2.new(1,-70,0,20)
	cost.Size = UDim2.new(0,62,0,14)
	cost.Font = Enum.Font.GothamMedium
	cost.TextSize = 11
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.TextColor3 = Color3.fromRGB(190,200,220)
	cost.Text = ""
	cost.Parent = b

	skillButtons[i] = b
	skillNameLbl[i] = name
	skillCdLbl[i] = cd
	skillCostLbl[i] = cost
	skillStrokes[i] = bs
	skillGlows[i] = glow
end
for i=1,3 do makeSkillButton(i) end

-- Match Log (right)
local logFrame = Instance.new("Frame")
logFrame.Position = UDim2.new(0.68, 0, 0, 66)
logFrame.Size = UDim2.new(0.32, 0, 1, -78)
logFrame.BackgroundColor3 = Color3.fromRGB(10,10,14)
logFrame.BorderSizePixel = 0
logFrame.Parent = panel
local lfc = Instance.new("UICorner"); lfc.CornerRadius = UDim.new(0, 12); lfc.Parent = logFrame
local lfs = Instance.new("UIStroke"); lfs.Thickness = 2; lfs.Transparency = 0.65; lfs.Parent = logFrame
local lp = Instance.new("UIPadding"); lp.PaddingTop=UDim.new(0,8); lp.PaddingLeft=UDim.new(0,8); lp.PaddingRight=UDim.new(0,8); lp.PaddingBottom=UDim.new(0,8); lp.Parent=logFrame

local logTitle = Instance.new("TextLabel")
logTitle.BackgroundTransparency = 1
logTitle.Size = UDim2.new(1,0,0,16)
logTitle.Font = Enum.Font.GothamBlack
logTitle.TextSize = 12
logTitle.TextColor3 = Color3.fromRGB(245,245,255)
logTitle.TextXAlignment = Enum.TextXAlignment.Left
logTitle.Text = "MATCH LOG"
logTitle.Parent = logFrame

local logScroll = Instance.new("ScrollingFrame")
logScroll.Position = UDim2.new(0,0,0,20)
logScroll.Size = UDim2.new(1,0,1,-20)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 6
logScroll.CanvasSize = UDim2.new(0,0,0,0)
logScroll.Parent = logFrame

local logList = Instance.new("UIListLayout")
logList.Padding = UDim.new(0,4)
logList.Parent = logScroll

local MAX_LOG_LINES = 60

local function logColor(kind)
	if kind == "MISS" then return Color3.fromRGB(255,160,160) end
	if kind == "HIT" then return Color3.fromRGB(120,255,170) end
	if kind == "WARN" then return Color3.fromRGB(255,235,120) end
	return Color3.fromRGB(190,200,220)
end

local function trimLog()
	local labels = {}
	for _, ch in ipairs(logScroll:GetChildren()) do
		if ch:IsA("TextLabel") then table.insert(labels, ch) end
	end
	if #labels <= MAX_LOG_LINES then return end
	table.sort(labels, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
	for i=1, (#labels - MAX_LOG_LINES) do
		labels[i]:Destroy()
	end
end

local logOrder = 0
local function addLog(text, kind)
	logOrder += 1
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1,0,0,0)
	l.TextColor3 = logColor(kind)
	l.Text = tostring(text)
	l.LayoutOrder = logOrder
	l.Parent = logScroll

	trimLog()

	task.defer(function()
		logScroll.CanvasSize = UDim2.new(0,0,0,logList.AbsoluteContentSize.Y + 6)
		logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.CanvasSize.Y.Offset - logScroll.AbsoluteWindowSize.Y))
	end)
end

local function clearLogs()
	for _, ch in ipairs(logScroll:GetChildren()) do
		if ch:IsA("TextLabel") then ch:Destroy() end
	end
	logOrder = 0
	task.defer(function()
		logScroll.CanvasSize = UDim2.new(0,0,0,0)
	end)
end

-- Click button
local clickBtn = Instance.new("TextButton")
clickBtn.AnchorPoint = Vector2.new(0.5, 1)
clickBtn.Position = UDim2.new(0.33,0,1,0)
clickBtn.Size = UDim2.new(0.66,0,0,44)
clickBtn.BackgroundColor3 = Color3.fromRGB(255,235,120)
clickBtn.BorderSizePixel = 0
clickBtn.Text = "CLICK!"
clickBtn.Font = Enum.Font.GothamBlack
clickBtn.TextSize = 18
clickBtn.TextColor3 = Color3.fromRGB(18,18,24)
clickBtn.Parent = panel
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 14); cbc.Parent = clickBtn

-- READY/SET/GO overlay
local overlay = Instance.new("Frame")
overlay.BackgroundTransparency = 1
overlay.Size = UDim2.fromScale(1,1)
overlay.Parent = gui

local bigText = Instance.new("TextLabel")
bigText.BackgroundTransparency = 1
bigText.AnchorPoint = Vector2.new(0.5, 0.5)
bigText.Position = UDim2.fromScale(0.5, 0.40)
bigText.Size = UDim2.fromOffset(800, 140)
bigText.Font = Enum.Font.GothamBlack
bigText.TextSize = 72
bigText.TextColor3 = Color3.fromRGB(255,235,120)
bigText.TextStrokeTransparency = 0.7
bigText.Text = ""
bigText.Visible = false
bigText.Parent = overlay

local function showBig(text, color)
	playSfx(uiPopSfx)
	bigText.Text = text
	bigText.TextColor3 = color
	bigText.Visible = true
	bigText.TextTransparency = 1
	tween(bigText, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency=0})
	task.delay(0.85, function()
		if bigText.Text == text then
			tween(bigText, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency=1})
			task.delay(0.22, function()
				if bigText.Text == text then bigText.Visible = false end
			end)
		end
	end)
end

-- =========================
-- Runtime state
-- =========================
local showing = false
local tableId = ""
local role = ""
local opponentName = ""

local winsMe, winsOpp = 0, 0
local ticksP1, ticksP2 = 0, 0
local progress = 0

local roundActive = false
local roundStartTime = 0
local baseSpeed = 1.0
local speedupK = SPEEDUP_K
local center = 0.5
local zone = {okay=0.22, good=0.14, perfect=0.07}

local staminaCur, staminaMax = 0, 0
local momentum = 0
local combo = 0

local currentPointer01 = 0.5
local lastPointer01 = 0.5
local lastEdgeHitT = 0
local EDGE_COOLDOWN = 0.12
local EDGE_EPS = 0.006

local skills = {}
local cdEnd = { [1]=0, [2]=0, [3]=0 }

local function showUI()
	if showing then return end
	showing = true
	gui.Enabled = true
	clearLogs()
	playSfx(uiPopSfx)

	bgm.SoundId = "rbxassetid://"..tostring(BGM_IDS[math.random(1,#BGM_IDS)])
	bgm.Volume = 0
	bgm:Play()
	tween(bgm, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume=0.25})
end

local function hideUI()
	showing = false
	gui.Enabled = false
	roundActive = false
	tween(bgm, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume=0})
	task.delay(0.65, function()
		if bgm.IsPlaying then bgm:Stop() end
	end)
end

local function updateTitleTalent()
	title.Text = "ARM WRESTLE — "..getTalentName()
end

player:GetAttributeChangedSignal("EquippedTalent"):Connect(updateTitleTalent)

local function updateHeader()
	sub.Text = ("Table: %s  |  Opponent: %s"):format(tableId ~= "" and tableId or "--", opponentName ~= "" and opponentName or "--")
	scoreLbl.Text = ("Ticks: %d - %d   |   Wins: %d - %d"):format(
		(ticksP1 or 0),
		(ticksP2 or 0),
		(winsMe or 0),
		(winsOpp or 0)
	)
end

local function setWinsFromData(data)
	local w1 = tonumber(data.winsP1) or 0
	local w2 = tonumber(data.winsP2) or 0
	if role == "P1" then
		winsMe = w1
		winsOpp = w2
	elseif role == "P2" then
		winsMe = w2
		winsOpp = w1
	end
	updateHeader()
end

local function setZoneUI()
	local okW = clamp(zone.okay or 0.22, 0.05, 0.90)
	local gdW = clamp(zone.good or 0.14, 0.03, 0.90)
	local pfW = clamp(zone.perfect or 0.07, 0.02, 0.90)

	zoneOK.Size = UDim2.fromScale(okW, 0.70)
	zoneGOOD.Size = UDim2.fromScale(gdW, 0.78)
	zonePERF.Size = UDim2.fromScale(pfW, 0.86)

	local half = okW / 2
	local safeCenter = clamp(center, half, 1 - half)

	zoneOK.Position = UDim2.fromScale(safeCenter, 0.5)
	zoneGOOD.Position = UDim2.fromScale(safeCenter, 0.5)
	zonePERF.Position = UDim2.fromScale(safeCenter, 0.5)
end

local function updateClickButtonState()
	local hasStamina = (staminaCur or 0) > 0
	local canClick = roundActive and hasStamina
	clickBtn.Active = canClick
	clickBtn.AutoButtonColor = canClick
	clickBtn.BackgroundTransparency = canClick and 0 or 0.35
	clickBtn.Text = canClick and "CLICK!" or (roundActive and "NO STAMINA" or "WAIT")
	clickBtn.TextColor3 = canClick and Color3.fromRGB(18,18,24) or Color3.fromRGB(120,120,140)
end

local function updateStatsUI()
	stamLbl.Text = ("Stamina: %d / %d"):format(math.floor((staminaCur or 0)+0.5), math.floor((staminaMax or 0)+0.5))
	momLbl.Text = ("Momentum: %d%%"):format(math.floor((momentum or 0)*100 + 0.5))
	comboLbl.Text = ("Combo x%d"):format(math.floor(combo or 0))
	updateClickButtonState()
end

local function computeMyPerspectiveProgress(serverProgress)
	if role == "P1" then return -serverProgress end
	if role == "P2" then return serverProgress end
	return 0
end

local function updateTugUI()
	local winProg = clamp(computeMyPerspectiveProgress(progress), -1, 1)
	local x = 0.5 - (winProg * 0.45)
	tugKnob.Position = UDim2.fromScale(x, 0.5)

	if math.abs(winProg) < 0.08 then
		tugText.Text = "Neutral"
		tugKnob.BackgroundColor3 = Color3.fromRGB(200,200,220)
	elseif winProg > 0 then
		tugText.Text = ("Winning (%.2f)"):format(winProg)
		tugKnob.BackgroundColor3 = Color3.fromRGB(120,255,170)
	else
		tugText.Text = ("Losing (%.2f)"):format(winProg)
		tugKnob.BackgroundColor3 = Color3.fromRGB(255,160,160)
	end
end

local function applySkillReadyStyle(i)
	local stroke = skillStrokes[i]
	local glow = skillGlows[i]
	if stroke then
		stroke.Color = Color3.fromRGB(255,235,120)
		stroke.Transparency = 0.25
	end
	if glow then
		glow.BackgroundColor3 = Color3.fromRGB(255, 235, 120)
		glow.BackgroundTransparency = 0.85
	end
end

local function applySkillDisabledStyle(i)
	local stroke = skillStrokes[i]
	local glow = skillGlows[i]
	if stroke then
		stroke.Color = Color3.fromRGB(110,110,130)
		stroke.Transparency = 0.7
	end
	if glow then
		glow.BackgroundTransparency = 1
	end
end

-- Skills UI
local function refreshSkillsFromTalent()
	skills = getSkills()
	for i=1,3 do
		local sk = skills[i]
		skillNameLbl[i].Text = sk and getSkillName(sk, i) or "—"
		skillCdLbl[i].Text = sk and "" or "No skill"
		local cost = getSkillCost(sk)
		skillCostLbl[i].Text = (cost and cost > 0) and ("Cost "..tostring(cost)) or ""
		applySkillDisabledStyle(i)
	end
end

local function setSkillButtonState(i, enabled, cdText)
	local b = skillButtons[i]
	if not b then return end
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundTransparency = enabled and 0 or 0.35
	if cdText ~= nil then skillCdLbl[i].Text = cdText end
	if enabled then
		applySkillReadyStyle(i)
	else
		applySkillDisabledStyle(i)
	end
end

local function updateSkillCooldownUI()
	local now = workspace:GetServerTimeNow()
	for i=1,3 do
		local sk = skills[i]
		if not sk then
			setSkillButtonState(i, false, "No skill")
		else
			local remain = (cdEnd[i] or 0) - now
			local cost = getSkillCost(sk)
			local enoughStam = (cost <= 0) or ((staminaCur or 0) >= cost)
			if remain > 0 then
				setSkillButtonState(i, false, ("CD %.1fs"):format(remain))
			else
				if not roundActive then
					setSkillButtonState(i, false, "Not in round")
				elseif not enoughStam then
					setSkillButtonState(i, false, "No stamina")
				else
					setSkillButtonState(i, true, "Ready")
				end
			end
		end
	end
end

for i=1,3 do
	local b = skillButtons[i]
	b.MouseEnter:Connect(function()
		if not b.Active then return end
		tween(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(28,30,40)})
	end)
	b.MouseLeave:Connect(function()
		if not b.Active then return end
		tween(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(18,20,28)})
	end)
end

-- Click sending
local lastSubmit = 0
local MIN_LOCAL_INTERVAL = 0.045

local function showInstantClickMarker(p01)
	clickMark.Position = UDim2.fromScale(clamp(p01,0,1), 0.5)
	clickMark.BackgroundTransparency = 0.15
	tween(clickMark, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency=1})
end

local function submitClick()
	if not roundActive then return end
	if (staminaCur or 0) <= 0 then
		flashError("No stamina.")
		playSfx(missSfx)
		updateClickButtonState()
		return
	end

	local now = tick()
	if (now - lastSubmit) < MIN_LOCAL_INTERVAL then return end
	lastSubmit = now

	showInstantClickMarker(currentPointer01)

	ArmWrestleEvent:FireServer("Submit", {
		tableId = tableId,
		clientT = workspace:GetServerTimeNow(),
		centerSeen = center,
	})
end

local function useSkill(slot)
	if not roundActive then return end
	slot = tonumber(slot) or 0
	if slot < 1 or slot > 3 then return end
	if not skills[slot] then
		flashError("No skill in that slot.")
		return
	end
	ArmWrestleEvent:FireServer("UseSkill", { tableId = tableId, slot = slot })
end

clickBtn.MouseButton1Click:Connect(submitClick)
for i=1,3 do
	skillButtons[i].MouseButton1Click:Connect(function() useSkill(i) end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if not showing then return end

	if input.KeyCode == Enum.KeyCode.Space then submitClick(); return end
	if input.KeyCode == Enum.KeyCode.One then useSkill(1) return end
	if input.KeyCode == Enum.KeyCode.Two then useSkill(2) return end
	if input.KeyCode == Enum.KeyCode.Three then useSkill(3) return end
	if input.KeyCode == Enum.KeyCode.Q then useSkill(1) return end
	if input.KeyCode == Enum.KeyCode.E then useSkill(2) return end
	if input.KeyCode == Enum.KeyCode.R then useSkill(3) return end
end)

-- Render loop
RunService.RenderStepped:Connect(function()
	if not roundActive then
		if showing then updateSkillCooldownUI() end
		return
	end

	local srvNow = workspace:GetServerTimeNow()
	local t = math.max(0, srvNow - roundStartTime)

	local p01 = pointerAtTime(baseSpeed, t, speedupK)
	currentPointer01 = p01
	pointer.Position = UDim2.fromScale(clamp(p01, 0, 1), 0.5)

	local pulse = 0.06 + 0.06 * pingpong01(t * 2)
	pointer.BackgroundTransparency = 0.2 + pulse

	local nowT = tick()
	local hitEdge =
		(p01 <= EDGE_EPS and lastPointer01 > EDGE_EPS) or
		(p01 >= (1-EDGE_EPS) and lastPointer01 < (1-EDGE_EPS))

	if hitEdge and (nowT - lastEdgeHitT) >= EDGE_COOLDOWN then
		lastEdgeHitT = nowT
		playSfx(edgeSfx)
	end
	lastPointer01 = p01

	updateSkillCooldownUI()
end)

-- =========================
-- Server events
-- =========================
ArmWrestleEvent.OnClientEvent:Connect(function(action, data)
	if typeof(action) ~= "string" then return end
	data = (typeof(data) == "table") and data or {}

	if action == "SeatStatus" then
		tableId = tostring(data.tableId or "")
		role = tostring(data.role or "")
		opponentName = tostring(data.opponent or "")
		statusRight.Text = "WAIT"
		combo = 0
		updateStatsUI()

		updateTitleTalent()
		updateHeader()

		showUI()
		refreshSkillsFromTalent()
		updateSkillCooldownUI()
		updateClickButtonState()
		return
	end

	if action == "SeatLeft" then
		hideUI()
		tableId, role, opponentName = "", "", ""
		combo = 0
		updateStatsUI()
		return
	end

	if action == "MatchStart" then
		clearLogs()
		winsMe, winsOpp = 0, 0
		combo = 0
		updateStatsUI()
		updateHeader()
		addLog("Match started.", "INFO")
		return
	end

	if action == "Countdown" then
		local startTime = tonumber(data.startTime) or 0

		local function scheduleAt(serverT, fn)
			task.spawn(function()
				while workspace:GetServerTimeNow() < serverT do task.wait(0.01) end
				fn()
			end)
		end

		scheduleAt(startTime - 3, function()
			showBig("READY", Color3.fromRGB(255,235,120))
			statusRight.Text = "READY"
		end)
		scheduleAt(startTime - 2, function()
			showBig("SET", Color3.fromRGB(140,210,255))
			statusRight.Text = "SET"
		end)
		scheduleAt(startTime - 1, function()
			showBig("GO!", Color3.fromRGB(120,255,170))
			statusRight.Text = "GO"
			goSound:Play()
		end)
		return
	end

	if action == "TurnStart" then
		roundActive = true
		statusRight.Text = "FIGHT"
		errorRight.Text = ""

		roundStartTime = tonumber(data.startTime) or workspace:GetServerTimeNow()
		baseSpeed = tonumber(data.baseSpeed) or 1.0
		speedupK = tonumber(data.speedupK) or speedupK

		center = tonumber(data.center) or 0.5
		local z = data.zone or {}
		zone = {
			okay = tonumber(z.okay) or 0.22,
			good = tonumber(z.good) or 0.14,
			perfect = tonumber(z.perfect) or 0.07,
		}
		setZoneUI()

		local st = data.stamina or {}
		staminaCur = tonumber(st.cur) or 0
		staminaMax = tonumber(st.max) or 0
		momentum = tonumber(data.momentum) or 0
		combo = tonumber(data.combo) or 0
		updateStatsUI()

		setWinsFromData(data)
		addLog(("Round %d started."):format(tonumber(data.turn) or 0), "INFO")
		refreshSkillsFromTalent()
		updateSkillCooldownUI()
		return
	end

	if action == "Vitals" then
		if tostring(data.tableId or "") ~= tableId then return end
		if data.stamina ~= nil then staminaCur = tonumber(data.stamina) or staminaCur end
		if data.staminaMax ~= nil then staminaMax = tonumber(data.staminaMax) or staminaMax end
		if data.momentum ~= nil then momentum = tonumber(data.momentum) or momentum end
		if data.combo ~= nil then combo = tonumber(data.combo) or combo end
		if data.baseSpeed ~= nil then baseSpeed = tonumber(data.baseSpeed) or baseSpeed end

		if typeof(data.zone) == "table" then
			zone = {
				okay = tonumber(data.zone.okay) or zone.okay,
				good = tonumber(data.zone.good) or zone.good,
				perfect = tonumber(data.zone.perfect) or zone.perfect,
			}
			setZoneUI()
		end
		if data.center ~= nil then center = tonumber(data.center) or center; setZoneUI() end

		updateStatsUI()
		updateSkillCooldownUI()
		return
	end

	if action == "ClickAck" then
		local rating = tostring(data.rating or "")
		local p01 = tonumber(data.pointer) or currentPointer01

		center = tonumber(data.center) or center
		if typeof(data.zone) == "table" then
			zone = {
				okay = tonumber(data.zone.okay) or zone.okay,
				good = tonumber(data.zone.good) or zone.good,
				perfect = tonumber(data.zone.perfect) or zone.perfect,
			}
		end
		setZoneUI()

		staminaCur = tonumber(data.stamina) or staminaCur
		momentum = tonumber(data.momentum) or momentum
		combo = tonumber(data.combo) or combo
		if data.baseSpeed ~= nil then baseSpeed = tonumber(data.baseSpeed) or baseSpeed end
		updateStatsUI()
		updateSkillCooldownUI()

		if rating == "MISS" then playSfx(missSfx) else playSfx(hitSfx) end
		showInstantClickMarker(p01)
		return
	end

	if action == "SkillAck" then
		local slot = tonumber(data.slot) or 0
		local ok = (data.ok == true)

		if ok and slot >= 1 and slot <= 3 then
			cdEnd[slot] = tonumber(data.cooldownEnd) or cdEnd[slot] or 0
			if data.stamina ~= nil then staminaCur = tonumber(data.stamina) or staminaCur end
			if data.momentum ~= nil then momentum = tonumber(data.momentum) or momentum end
			updateStatsUI()
			updateSkillCooldownUI()
			addLog(("Used Skill %d: %s"):format(slot, getSkillName(skills[slot], slot)), "INFO")
		else
			local err = tostring(data.err or "Skill failed.")
			flashError(err)
			addLog(("Skill %d failed: %s"):format(slot, err), "WARN")
		end
		return
	end

	if action == "Progress" then
		progress = tonumber(data.progress) or progress
		ticksP1 = tonumber(data.ticksP1) or ticksP1
		ticksP2 = tonumber(data.ticksP2) or ticksP2
		updateHeader()
		updateTugUI()
		return
	end

	if action == "TurnEnd" then
		roundActive = false
		statusRight.Text = "WAIT"
		combo = 0
		updateStatsUI()
		setWinsFromData(data)
		addLog(("Round ended: %s"):format(tostring(data.roundWinner or "?")), "INFO")
		updateSkillCooldownUI()
		updateClickButtonState()
		return
	end

	if action == "MatchEnd" then
		roundActive = false
		local res = tostring(data.result or "END")
		statusRight.Text = res
		setWinsFromData(data)
		addLog(("MATCH END: %s"):format(res), "INFO")
		updateSkillCooldownUI()
		updateClickButtonState()
		task.delay(2.5, hideUI)
		return
	end

	if action == "EventWarn" then
		flashNotice(tostring(data.text or "Event incoming..."))
		return
	end

	if action == "Log" then
		if tostring(data.tableId or "") ~= tableId then return end
		addLog(tostring(data.text or ""), tostring(data.kind or "INFO"))
		return
	end
end)

print("[ArmWrestleClient] Loaded ✅ (Talent title + MatchLog + Combo + 0 stamina gate)")
