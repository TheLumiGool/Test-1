-- ServerScriptService/ArmWrestleService (Script)
-- FULL DROP-IN OVERWRITE
-- ✅ PvP + PvAI (NPC seated, ArmWrestleAI=true)
-- ✅ Click accuracy fixed (client+server use identical pointer math)
-- ✅ "Zone moved before click" fixed via centerSeen (server uses if close)
-- ✅ AI has talent + uses skills + difficulty changes AI behavior (not your bar)
-- ✅ Match log events supported
-- ✅ Mid-round events (speed boost / smaller hitbox) with cooldown cycles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- ======================================================
-- REMOTES
-- ======================================================
local remotesFolder = ReplicatedStorage:FindFirstChild("ArmWrestleRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ArmWrestleRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local ArmWrestleEvent = remotesFolder:FindFirstChild("ArmWrestleEvent")
if not ArmWrestleEvent then
	ArmWrestleEvent = Instance.new("RemoteEvent")
	ArmWrestleEvent.Name = "ArmWrestleEvent"
	ArmWrestleEvent.Parent = remotesFolder
end

local aiBind = ServerScriptService:FindFirstChild("ArmWrestleAIBind")
if not aiBind then
aiBind = Instance.new("BindableFunction")
	aiBind.Name = "ArmWrestleAIBind"
	aiBind.Parent = ServerScriptService
end

local aiDoneEvent = ServerScriptService:FindFirstChild("ArmWrestleAIDone")
if not aiDoneEvent then
aiDoneEvent = Instance.new("BindableEvent")
	aiDoneEvent.Name = "ArmWrestleAIDone"
	aiDoneEvent.Parent = ServerScriptService
end

aiBind.OnInvoke = function(plr, difficulty, talentId)
	if not plr or plr.Parent ~= Players then
		return false
	end
	local ok, err = startAIMatchForPlayer(plr, difficulty, talentId)
	if not ok then
		warn("[ArmWrestleService] AI match failed:", err)
	end
	return ok
end

-- Talent definitions (safe require)
local TalentDefinitions = nil
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentDefinitions"))
	end)
	if ok then
		TalentDefinitions = mod
	else
		warn("[ArmWrestleService] TalentDefinitions missing; using defaults.")
		TalentDefinitions = {
			List = {},
			Get = function() return nil end,
		}
	end
end

-- ======================================================
-- CONFIG
-- ======================================================
local TABLES_FOLDER = workspace:FindFirstChild("ArmWrestleTables")
if not TABLES_FOLDER then
	warn("[ArmWrestleService] Missing workspace.ArmWrestleTables; create it and add table models.")
end

local BEST_OF = 5
local WINS_NEEDED = math.floor(BEST_OF/2) + 1

local ROUND_DURATION = 120
local COUNTDOWN_READYSETGO = 3.0

-- Pointer motion (MUST MATCH CLIENT)
local POINTER_SPEED_BASE = 0.90
local SPEEDUP_K = 0.010 -- same as client (acceleration; set to 0 to disable)

-- Zones (widths are fractions of bar width)
local ZONE_BASE = { ok = 0.22, good = 0.14, perfect = 0.08 }

-- Ensures zone never spills: same margin used in client rendering too
local CENTER_MARGIN_EXTRA = 0.01

-- Click control
local MIN_CLICK_INTERVAL = 0.06
local STAMINA_DIV = 6.45
local BASE_CLICK_COST = 1

-- ticks per rating
local TICKS_OK = 1
local TICKS_GOOD = 2
local TICKS_PERFECT = 3

-- progress push per tick
local PROGRESS_STEP_PER_TICK = 0.075

-- Momentum (score multiplier ONLY)
local MOM_GAIN = { OKAY = 0.05, GOOD = 0.09, PERFECT = 0.14, MISS = -0.07 }
local MOMENTUM_SCORE_SCALE = 0.70

-- Regen / vitals
local REGEN_TICK = 0.25
local VITALS_TICK = 0.25

-- anti-cheat tolerance for client click time (server-time)
local CLIENT_TIME_TOLERANCE = 1.20

-- "I clicked when it was there" fix:
-- client sends centerSeen (what they saw). If within this delta, server grades using it.
local CENTER_SEEN_TOL = 0.05

-- Round difficulty ramp
local DIFFICULTY_RAMP_SECONDS = 55
local DIFFICULTY_SPEED_MAX = 1.35
local DIFFICULTY_ZONE_MIN = 0.72

-- Mid-round events
local EVENT_ACTIVE_MIN = 10
local EVENT_ACTIVE_MAX = 15
local EVENT_COOLDOWN_MIN = 10
local EVENT_COOLDOWN_MAX = 20

local ROUND_EVENTS = {
	{
		name = "Overdrive",
		log = "Event: Overdrive! Slider speed boosted (manageable)",
		speedMin = 1.15,
		speedMax = 1.35,
	},
	{
		name = "Precision",
		log = "Event: Precision! Hit zone tightens slightly",
		zoneMin = 0.85,
		zoneMax = 0.95,
	},
	{
		name = "Adrenaline",
		log = "Event: Adrenaline! Faster tempo with a small tighten",
		speedMin = 1.10,
		speedMax = 1.30,
		zoneMin = 0.90,
		zoneMax = 1.00,
	},
	{
		name = "Stability",
		log = "Event: Stability! Slower & wider",
		speedMin = 0.85,
		speedMax = 1.00,
		zoneMin = 1.10,
		zoneMax = 1.25,
	},
	{
		name = "Flow",
		log = "Event: Flow! Slower tempo",
		speedMin = 0.80,
		speedMax = 0.95,
	},
	{
		name = "Focus",
		log = "Event: Focus! Wider hit zone",
		zoneMin = 1.10,
		zoneMax = 1.30,
	},
}

-- ======================================================
-- HELPERS
-- ======================================================
local function clamp(x,a,b) return math.max(a, math.min(b, x)) end

local function pingpong01(x)
	local m = x % 2
	if m <= 1 then return m else return 2 - m end
end

local function randRange(min, max)
	return min + (max - min) * math.random()
end

local function eventIntensity(rt, now)
	if not rt or not now then return 0 end
	local elapsed = math.max(0, now - rt.startTime)
	return clamp(elapsed / ROUND_DURATION, 0, 1)
end

local function pointerAtTime(baseSpeed, tSinceStart)
	-- MUST MATCH CLIENT:
	-- phase = baseSpeed * (t + 0.5*k*t^2)
	local phase = baseSpeed * (tSinceStart + 0.5 * SPEEDUP_K * (tSinceStart * tSinceStart))
	return pingpong01(phase)
end

local function safeFire(plr, action, data)
	if plr and plr.Parent == Players then
		ArmWrestleEvent:FireClient(plr, action, data)
	end
end

local function safeFireBoth(p1, p2, action, data)
	safeFire(p1, action, data)
	safeFire(p2, action, data)
end

local function ensureLeaderstats(plr)
	if not plr or plr.Parent ~= Players then return nil end
	local stats = plr:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = plr
	end

	local function getInt(name)
		local v = stats:FindFirstChild(name)
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Value = 0
			v.Parent = stats
		end
		return v
	end

	return {
		wins = getInt("Wins"),
		losses = getInt("Losses"),
		streak = getInt("WinStreak"),
		best = getInt("BestStreak"),
	}
end

local function recordMatchResult(plr, didWin, didLose)
	if not plr then return end
	local stats = ensureLeaderstats(plr)
	if not stats then return end

	if didWin then
		stats.wins.Value += 1
		stats.streak.Value += 1
		if stats.streak.Value > stats.best.Value then
			stats.best.Value = stats.streak.Value
		end
	elseif didLose then
		stats.losses.Value += 1
		stats.streak.Value = 0
	end
end

local function applyMatchStats(plr, didWin, didLose)
	if not plr then return end
	local winsAttr = "AW_TotalWins"
	local lossesAttr = "AW_TotalLosses"
	local streakAttr = "AW_WinStreak"
	local bestAttr = "AW_BestStreak"

	local wins = tonumber(plr:GetAttribute(winsAttr)) or 0
	local losses = tonumber(plr:GetAttribute(lossesAttr)) or 0
	local streak = tonumber(plr:GetAttribute(streakAttr)) or 0
	local best = tonumber(plr:GetAttribute(bestAttr)) or 0

	if didWin then
		wins += 1
		streak += 1
		if streak > best then best = streak end
	elseif didLose then
		losses += 1
		streak = 0
	end

	plr:SetAttribute(winsAttr, wins)
	plr:SetAttribute(lossesAttr, losses)
	plr:SetAttribute(streakAttr, streak)
	plr:SetAttribute(bestAttr, best)
end

local function serverLog(state, kind, text)
	local payload = { tableId = state.id, kind = kind or "INFO", text = tostring(text or "") }
	safeFire(state.p1, "Log", payload)
	safeFire(state.p2, "Log", payload)
end

local function getPlayerFromSeat(seat)
	if not seat then return nil end
	local occ = seat.Occupant
	if not occ then return nil end
	local char = occ.Parent
	if not char then return nil end
	return Players:GetPlayerFromCharacter(char)
end

local function getCharacterFromSeat(seat)
	if not seat then return nil end
	local occ = seat.Occupant
	return occ and occ.Parent or nil
end

local function isAICharacter(char)
	return char and char:GetAttribute("ArmWrestleAI") == true
end

local function getAIDifficulty(char)
	return tostring(char and char:GetAttribute("AIDifficulty") or "Rookie")
end

local function findSeatIn(folder, fallbackModel)
	local scope = folder or fallbackModel
	if not scope then return nil end
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then
			return d
		end
	end
	return nil
end

local function ensureBotTemplate()
	local existing = ServerStorage:FindFirstChild("ArmWrestleBotRig")
	if existing then return existing end

	local bot = Instance.new("Model")
	bot.Name = "ArmWrestleBotRig"
	bot:SetAttribute("ArmWrestleAI", true)
	bot:SetAttribute("AIDifficulty", "Skilled")

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2,2,1)
	hrp.Anchored = false
	hrp.CanCollide = false
	hrp.Parent = bot

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2,1,1)
	head.Anchored = false
	head.CanCollide = false
	head.Parent = bot

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = head
	weld.Parent = hrp
	head.CFrame = hrp.CFrame * CFrame.new(0, 2, 0)

	local hum = Instance.new("Humanoid")
	hum.Parent = bot

	bot.PrimaryPart = hrp
	bot.Parent = ServerStorage

	return bot
end

local function seatHumanoid(seat, humanoid)
	if seat and humanoid then
		seat:Sit(humanoid)
	end
end

local function computeZones(windowMult, zoneScale)
	local scale = zoneScale or 1
	return {
		ok = clamp(ZONE_BASE.ok * windowMult * scale, 0.10, 0.40),
		good = clamp(ZONE_BASE.good * windowMult * scale, 0.06, 0.30),
		perfect = clamp(ZONE_BASE.perfect * windowMult * scale, 0.04, 0.22),
	}
end

local function pickCenterWithin(zoneOkWidth)
	-- ensures zone does NOT spill off bar (MUST MATCH CLIENT SAFE CENTER CLAMP)
	local margin = (zoneOkWidth/2) + CENTER_MARGIN_EXTRA
	return clamp(margin + math.random() * (1 - 2*margin), margin, 1 - margin)
end

local function ratingFromPointer(pointer01, center, zone)
	local dist = math.abs(pointer01 - center)
	if dist <= zone.perfect/2 then return "PERFECT"
	elseif dist <= zone.good/2 then return "GOOD"
	elseif dist <= zone.ok/2 then return "OKAY"
	else return "MISS" end
end

local function ticksForRating(r)
	if r == "PERFECT" then return TICKS_PERFECT end
	if r == "GOOD" then return TICKS_GOOD end
	if r == "OKAY" then return TICKS_OK end
	return 0
end

-- ======================================================
-- TALENT HELPERS (PLAYER OR AI CHARACTER)
-- ======================================================
local function getEquippedTalentFromActor(actor)
	local id = ""
	if typeof(actor) == "Instance" then
		id = tostring(actor:GetAttribute("EquippedTalent") or "")
	end
	if id == "" then return nil end
	return TalentDefinitions.Get(id)
end

local function getStyleFromActor(actor)
	local t = getEquippedTalentFromActor(actor)
	return (t and t.Style) or {}
end

local function getSkillsFromActor(actor)
	local t = getEquippedTalentFromActor(actor)
	local skills = t and t.Skills
	if typeof(skills) == "table" then return skills end
	return {}
end

local function deriveRegenPerSec(style)
	local explicit = tonumber(style.StaminaRegen)
	if explicit and explicit > 0 then return explicit end
	local stamMax = tonumber(style.StaminaMax) or 180
	return clamp((stamMax / 200) * 1.8, 0.9, 2.4)
end

-- ======================================================
-- RUNTIME PER SIDE
-- ======================================================
local function newRuntimeForActor(actor)
	local style = getStyleFromActor(actor)

	local baseScore = tonumber(style.BaseScore) or 0.30
	local staminaMaxRaw = tonumber(style.StaminaMax) or 180
	local windowMultBase = tonumber(style.WindowMult) or 1.0
	local sliderMultBase = tonumber(style.SliderSpeedMult) or 1.0
	local momGainMultBase = tonumber(style.MomentumGainMult) or 1.0

	local staminaMax = math.max(20, math.floor(staminaMaxRaw / STAMINA_DIV))

	return {
		baseScore = baseScore,
		windowMultBase = windowMultBase,
		sliderMultBase = sliderMultBase,
		momGainMultBase = momGainMultBase,
		regenPerSec = deriveRegenPerSec(style),

		-- effective (skills can modify)
		windowMult = windowMultBase,
		sliderMult = sliderMultBase,
		momGainMult = momGainMultBase,
		momDecayMult = 1.0,
		clickCostMult = 1.0,
		extraClickCost = 0,
		baseScoreAdd = 0,

		stamina = staminaMax,
		staminaMax = staminaMax,

		cooldownEnd = { [1]=0, [2]=0, [3]=0 },
		active = {}, -- {expires, effects}

		nextPerfectBonus = 0,
		nextPerfectBonusExpire = 0,
		nextPerfectMomentumAdd = 0,
		nextPerfectMomentumExpire = 0,

		perfectBonus = 0,
		perfectBonusHits = 0,
		perfectMomentumAdd = 0,
		perfectMomentumHits = 0,
	}
end

local function cleanupExpired(now, pr)
	local kept = {}
	for _, e in ipairs(pr.active) do
		if e.expires > now then
			table.insert(kept, e)
		end
	end
	pr.active = kept

	if pr.nextPerfectBonus ~= 0 and now > (pr.nextPerfectBonusExpire or 0) then
		pr.nextPerfectBonus = 0
	end
	if pr.nextPerfectMomentumAdd ~= 0 and now > (pr.nextPerfectMomentumExpire or 0) then
		pr.nextPerfectMomentumAdd = 0
	end
end

local function recomputeEffective(now, pr)
	cleanupExpired(now, pr)

	local windowMult = pr.windowMultBase
	local sliderMult = pr.sliderMultBase
	local momGainMult = pr.momGainMultBase
	local momDecayMult = 1.0
	local clickCostMult = 1.0
	local extraClickCost = 0
	local baseScoreAdd = 0

	for _, e in ipairs(pr.active) do
		local eff = e.effects
		if typeof(eff) == "table" then
			if eff.WindowMult then windowMult *= tonumber(eff.WindowMult) or 1 end
			if eff.SliderSpeedMult then sliderMult *= tonumber(eff.SliderSpeedMult) or 1 end
			if eff.MomentumGainMult then momGainMult *= tonumber(eff.MomentumGainMult) or 1 end
			if eff.MomentumDecayMult then momDecayMult *= tonumber(eff.MomentumDecayMult) or 1 end
			if eff.ClickCostMult then clickCostMult *= tonumber(eff.ClickCostMult) or 1 end
			if eff.ExtraClickCost then extraClickCost += tonumber(eff.ExtraClickCost) or 0 end
			if eff.BaseScoreAdd then baseScoreAdd += tonumber(eff.BaseScoreAdd) or 0 end
		end
	end

	pr.windowMult = windowMult
	pr.sliderMult = sliderMult
	pr.momGainMult = momGainMult
	pr.momDecayMult = momDecayMult
	pr.clickCostMult = clickCostMult
	pr.extraClickCost = extraClickCost
	pr.baseScoreAdd = baseScoreAdd
end

local function computeClickCost(pr)
	local raw = (BASE_CLICK_COST + (pr.extraClickCost or 0)) * (pr.clickCostMult or 1)
	return clamp(raw, 0.25, 10)
end

local function computeBaseSpeed(pr, speedScale)
	local scale = speedScale or 1
	return POINTER_SPEED_BASE * (pr.sliderMult or 1.0) * scale
end

local function computeBaseScore(pr)
	local s = (pr.baseScore or 0.30) + (pr.baseScoreAdd or 0)
	return clamp(s, 0.15, 0.60)
end

local function difficultyScales(rt, now)
	if not rt or not now then return 1, 1 end
	local elapsed = math.max(0, now - rt.startTime)
	local alpha = clamp(elapsed / DIFFICULTY_RAMP_SECONDS, 0, 1)
	local ease = 1 - math.pow(1 - alpha, 2)
	local speedScale = 1 + (DIFFICULTY_SPEED_MAX - 1) * ease
	local zoneScale = 1 - (1 - DIFFICULTY_ZONE_MIN) * ease
	return speedScale, zoneScale
end

-- ======================================================
-- AI TALENT + DIFFICULTY + SKILL USAGE
-- ======================================================
local function chooseAITalentId(diff)
	if not TalentDefinitions or typeof(TalentDefinitions.List) ~= "table" or #TalentDefinitions.List == 0 then
		return ""
	end

	local allow = {}
	if diff == "Rookie" then
		allow = { Common=true, Rare=true }
	elseif diff == "Skilled" then
		allow = { Common=true, Rare=true, Epic=true }
	elseif diff == "Pro" then
		allow = { Rare=true, Epic=true, Legendary=true }
	else -- Elite
		allow = { Rare=true, Epic=true, Legendary=true, Secret=true, Common=true }
	end

	local poolWithSkills = {}
	local poolAny = {}

	for _, t in ipairs(TalentDefinitions.List) do
		local rarity = tostring(t.Rarity or "Common")
		if allow[rarity] then
			table.insert(poolAny, t)
			if typeof(t.Skills) == "table" and t.Skills[1] then
				table.insert(poolWithSkills, t)
			end
		end
	end

	local pickFrom = (#poolWithSkills > 0) and poolWithSkills or ((#poolAny > 0) and poolAny or TalentDefinitions.List)
	local pick = pickFrom[math.random(1, #pickFrom)]
	return tostring(pick.Id or "")
end

local function ensureAITalent(aiChar, diff)
	if not aiChar then return "" end
	local id = tostring(aiChar:GetAttribute("EquippedTalent") or "")
	if id ~= "" then return id end
	id = chooseAITalentId(diff)
	if id ~= "" then
		aiChar:SetAttribute("EquippedTalent", id)
	end
	return id
end

local AI = {}
AI.Difficulties = {
	Rookie = {
		think=0.03, minClick=0.26, noise=0.080, want="OKAY",
		skillChance=0.08, minSkill=2.8, lockTime=0.10, react=0.06, reactJitter=0.06,
		preferSkillSlots = {1,2,3},
	},
	Skilled= {
		think=0.03, minClick=0.20, noise=0.050, want="GOOD",
		skillChance=0.14, minSkill=2.2, lockTime=0.09, react=0.05, reactJitter=0.05,
		preferSkillSlots = {1,2,3},
	},
	Pro    = {
		think=0.03, minClick=0.16, noise=0.035, want="GOOD",
		skillChance=0.20, minSkill=1.8, lockTime=0.08, react=0.04, reactJitter=0.04,
		preferSkillSlots = {1,2,3},
	},
	Elite  = {
		think=0.03, minClick=0.12, noise=0.025, want="PERFECT",
		skillChance=0.28, minSkill=1.4, lockTime=0.06, react=0.03, reactJitter=0.03,
		preferSkillSlots = {1,2,3},
	},
}
local function getAICfg(diff) return AI.Difficulties[diff] or AI.Difficulties.Rookie end

-- Shared skill applier (players + AI)
local function applySkill(state, rt, side, actor, slot)
	slot = tonumber(slot) or 0
	if slot < 1 or slot > 3 then return false, "Bad slot" end

	local now = workspace:GetServerTimeNow()
	local pr = (side == "P1") and rt.prP1 or rt.prP2
	if not pr then return false, "No runtime" end

	local skills = getSkillsFromActor(actor)
	local skill = skills[slot]
	if not skill then return false, "No skill" end

	local cdEnd = pr.cooldownEnd[slot] or 0
	if now < cdEnd then return false, "On cooldown" end

	local effects = (typeof(skill.Effects)=="table") and skill.Effects or {}
	local cost = tonumber(effects.StaminaCost) or 0
	if cost > 0 and pr.stamina < cost then return false, "Not enough stamina" end
	if cost > 0 then pr.stamina = clamp(pr.stamina - cost, 0, pr.staminaMax) end

	local cd = tonumber(skill.Cooldown) or 0
	pr.cooldownEnd[slot] = now + math.max(0, cd)

	-- instant effects
	if effects.StaminaRestore then
		pr.stamina = clamp(pr.stamina + (tonumber(effects.StaminaRestore) or 0), 0, pr.staminaMax)
	end
	if effects.MomentumAdd then
		local add = (tonumber(effects.MomentumAdd) or 0) / 100
		if side == "P1" then rt.momentumP1 = clamp(rt.momentumP1 + add, 0, 1)
		else rt.momentumP2 = clamp(rt.momentumP2 + add, 0, 1) end
	end

	-- perfect modifiers
	if effects.NextPerfectBonus then
		pr.nextPerfectBonus = tonumber(effects.NextPerfectBonus) or 0
		pr.nextPerfectBonusExpire = now + (tonumber(skill.Duration) or 0)
	end
	if effects.NextPerfectMomentumAdd then
		pr.nextPerfectMomentumAdd = tonumber(effects.NextPerfectMomentumAdd) or 0
		pr.nextPerfectMomentumExpire = now + (tonumber(skill.Duration) or 0)
	end
	if effects.PerfectBonus then
		pr.perfectBonus = tonumber(effects.PerfectBonus) or 0
		pr.perfectBonusHits = tonumber(effects.PerfectBonusHits) or pr.perfectBonusHits or 0
	end
	if effects.PerfectMomentumAdd then
		pr.perfectMomentumAdd = tonumber(effects.PerfectMomentumAdd) or 0
		pr.perfectMomentumHits = tonumber(effects.PerfectMomentumHits) or pr.perfectMomentumHits or 0
	end

	-- timed effects
	local dur = tonumber(skill.Duration) or 0
	if dur > 0 then
		table.insert(pr.active, { expires = now + dur, effects = effects })
	end

	recomputeEffective(now, pr)

	local name = (actor and actor.Name) or "AI"
	local skName = tostring(skill.Name or skill.Id or ("Skill "..slot))
	serverLog(state, "INFO", ("%s used %s"):format(name, skName))

	-- ack only to real players
	local plr = actor
	if typeof(plr) == "Instance" and plr:IsA("Player") then
		safeFire(plr, "SkillAck", {
			tableId = state.id,
			slot = slot,
			ok = true,
			cooldownEnd = pr.cooldownEnd[slot],
			stamina = pr.stamina,
			momentum = (side=="P1") and rt.momentumP1 or rt.momentumP2,
		})
	end

	return true
end

-- ======================================================
-- TABLE STATE
-- ======================================================
local Tables = {}

local function findTableStateByName(name)
	local state = Tables[name]
	if state then return state end
	for _, st in pairs(Tables) do
		if st and st.id == name then return st end
	end
	return nil
end

local function findAvailableTable()
	local preferred = findTableStateByName("TrainingTable")
	if preferred then return preferred end
	for _, st in pairs(Tables) do
		return st
	end
	return nil
end

local function startAIMatchForPlayer(plr, difficulty, talentId)
	local state = findAvailableTable()
	if not state then return false, "No table available." end
	if state.running then return false, "Table already running." end

	local seatP1 = state.seatP1
	local seatP2 = state.seatP2
	if not seatP1 or not seatP2 then return false, "Table missing seats." end

	local playerSeat = seatP1
	local aiSeat = seatP2
	if seatP1.Occupant and not seatP2.Occupant then
		playerSeat = seatP2
		aiSeat = seatP1
	end

	local char = plr.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and playerSeat then
		seatHumanoid(playerSeat, humanoid)
	end

	local botTemplate = ensureBotTemplate()
	local existingBot = state.model:FindFirstChild("TrainingBot")
	if existingBot then existingBot:Destroy() end

	local bot = botTemplate:Clone()
	bot.Name = "TrainingBot"
	bot:SetAttribute("ArmWrestleAI", true)
	bot:SetAttribute("AIDifficulty", tostring(difficulty or "Rookie"))
	if talentId and talentId ~= "" then
		bot:SetAttribute("EquippedTalent", tostring(talentId))
	end
	bot.Parent = state.model
	if bot.PrimaryPart and aiSeat then
		bot:PivotTo(aiSeat.CFrame * CFrame.new(0, 0, -1.2))
	end

	local botHum = bot:FindFirstChildOfClass("Humanoid")
	if botHum and aiSeat then
		task.wait(0.1)
		seatHumanoid(aiSeat, botHum)
	end

	state.aiMatchOwner = plr
	return true
end

local function cancelTable(state, reason)
	state.cancelToken += 1
	state.running = false
	state.round = nil

	if state.p1 then safeFire(state.p1, "MatchEnd", { tableId = state.id, result = "CANCELLED", reason = reason }) end
	if state.p2 then safeFire(state.p2, "MatchEnd", { tableId = state.id, result = "CANCELLED", reason = reason }) end
end

-- ======================================================
-- MATCH LOOP
-- ======================================================
local function startMatch(state)
	if state.running then return end
	if not state.hasRealPlayer then return end
	if not state.hasOpponent1 or not state.hasOpponent2 then return end

	state.running = true
	state.cancelToken += 1
	local myToken = state.cancelToken

	state.winsP1, state.winsP2 = 0, 0
	state.turn = 0

	safeFireBoth(state.p1, state.p2, "MatchStart", {
		tableId = state.id,
		bestOf = BEST_OF,
		winsP1 = 0,
		winsP2 = 0,
	})

	serverLog(state, "INFO", "Match started.")

	while state.running and state.cancelToken == myToken do
		state.turn += 1

		local now = workspace:GetServerTimeNow()
		local roundStart = now + COUNTDOWN_READYSETGO

		safeFireBoth(state.p1, state.p2, "Countdown", {
			tableId = state.id,
			startTime = roundStart,
		})

		local rt = {
			active = true,
			startTime = roundStart,
			endTime = roundStart + ROUND_DURATION,
			progress = 0,
			ticksP1 = 0,
			ticksP2 = 0,
			comboP1 = 0,
			comboP2 = 0,

			centerP1 = 0.5,
			centerP2 = 0.5,

			momentumP1 = 0,
			momentumP2 = 0,

			lastClickTS = {},

			prP1 = nil,
			prP2 = nil,
		}
		state.round = rt

		local actorP1 = state.p1 or state.aiChar1
		local actorP2 = state.p2 or state.aiChar2

		rt.prP1 = newRuntimeForActor(actorP1)
		rt.prP2 = newRuntimeForActor(actorP2)

		recomputeEffective(roundStart, rt.prP1)
		recomputeEffective(roundStart, rt.prP2)

		local speedScaleStart, zoneScaleStart = difficultyScales(rt, rt.startTime)
		local z1 = computeZones(rt.prP1.windowMult, zoneScaleStart)
		local z2 = computeZones(rt.prP2.windowMult, zoneScaleStart)

		rt.centerP1 = pickCenterWithin(z1.ok)
		rt.centerP2 = pickCenterWithin(z2.ok)

		if state.p1 then
			safeFire(state.p1, "TurnStart", {
				tableId = state.id,
				turn = state.turn,
				startTime = rt.startTime,
				duration = ROUND_DURATION,
				baseSpeed = computeBaseSpeed(rt.prP1, speedScaleStart),
				center = rt.centerP1,
				zone = { okay = z1.ok, good = z1.good, perfect = z1.perfect },
				stamina = { cur = rt.prP1.stamina, max = rt.prP1.staminaMax },
				momentum = rt.momentumP1,
				combo = rt.comboP1,
				winsP1 = state.winsP1,
				winsP2 = state.winsP2,
				bestOf = BEST_OF,
				speedupK = SPEEDUP_K,
			})
		end

		if state.p2 then
			safeFire(state.p2, "TurnStart", {
				tableId = state.id,
				turn = state.turn,
				startTime = rt.startTime,
				duration = ROUND_DURATION,
				baseSpeed = computeBaseSpeed(rt.prP2, speedScaleStart),
				center = rt.centerP2,
				zone = { okay = z2.ok, good = z2.good, perfect = z2.perfect },
				stamina = { cur = rt.prP2.stamina, max = rt.prP2.staminaMax },
				momentum = rt.momentumP2,
				combo = rt.comboP2,
				winsP1 = state.winsP1,
				winsP2 = state.winsP2,
				bestOf = BEST_OF,
				speedupK = SPEEDUP_K,
			})
		end

		-- wait for GO
		while state.running and state.cancelToken == myToken do
			if workspace:GetServerTimeNow() >= rt.startTime then break end
			task.wait(0.03)
		end

		local function fireProgress()
			safeFireBoth(state.p1, state.p2, "Progress", {
				tableId = state.id,
				turn = state.turn,
				progress = rt.progress,
				ticksP1 = rt.ticksP1,
				ticksP2 = rt.ticksP2,
			})
		end

		local function processSubmit(side, clickT, sourceKey, centerSeen)
			local pr = (side == "P1") and rt.prP1 or rt.prP2
			if not pr then return end

			local key = sourceKey or side
			local nowServer = workspace:GetServerTimeNow()

			local last = rt.lastClickTS[key] or 0
			if (nowServer - last) < MIN_CLICK_INTERVAL then return end
			rt.lastClickTS[key] = nowServer

			if pr.stamina <= 0 then
				return
			end

			recomputeEffective(nowServer, pr)

			local cost = computeClickCost(pr)
			pr.stamina = clamp(pr.stamina - cost, 0, pr.staminaMax)

			local speedScale, zoneScale = difficultyScales(rt, clickT)
			local baseSpeed = computeBaseSpeed(pr, speedScale)
			local t = math.max(0, clickT - rt.startTime)
			local pointer01 = pointerAtTime(baseSpeed, t)

			local centerServer = (side == "P1") and rt.centerP1 or rt.centerP2
			local zone = computeZones(pr.windowMult, zoneScale)

			-- "I clicked when it was there" fix:
			local centerUsed = centerServer
			if typeof(centerSeen) == "number" and math.abs(centerSeen - centerServer) <= CENTER_SEEN_TOL then
				centerUsed = centerSeen
			end

			local rating = ratingFromPointer(pointer01, centerUsed, zone)

			if rating == "MISS" then
				if side == "P1" then rt.comboP1 = 0 else rt.comboP2 = 0 end
			else
				if side == "P1" then rt.comboP1 += 1 else rt.comboP2 += 1 end
			end

			local mg = (MOM_GAIN[rating] or 0) * (pr.momGainMult or 1.0)
			if side == "P1" then
				rt.momentumP1 = clamp(rt.momentumP1 + mg, 0, 1)
			else
				rt.momentumP2 = clamp(rt.momentumP2 + mg, 0, 1)
			end

			local gained = ticksForRating(rating)
			if gained > 0 then
				if side == "P1" then rt.ticksP1 += gained else rt.ticksP2 += gained end

				local baseScore = computeBaseScore(pr)
				local curMom = (side == "P1") and rt.momentumP1 or rt.momentumP2
				local momMult = 1 + (curMom * MOMENTUM_SCORE_SCALE)

				local pushScore = gained * PROGRESS_STEP_PER_TICK * baseScore * momMult

				if rating == "PERFECT" then
					if pr.nextPerfectBonus and pr.nextPerfectBonus ~= 0 then
						pushScore += pr.nextPerfectBonus
						pr.nextPerfectBonus = 0
					end
					if pr.perfectBonus and pr.perfectBonus ~= 0 and (pr.perfectBonusHits or 0) > 0 then
						pushScore += pr.perfectBonus
						pr.perfectBonusHits -= 1
					end

					local momBonus = 0
					if pr.nextPerfectMomentumAdd and pr.nextPerfectMomentumAdd ~= 0 then
						momBonus += (pr.nextPerfectMomentumAdd / 100)
						pr.nextPerfectMomentumAdd = 0
					end
					if pr.perfectMomentumAdd and pr.perfectMomentumAdd ~= 0 and (pr.perfectMomentumHits or 0) > 0 then
						momBonus += (pr.perfectMomentumAdd / 100)
						pr.perfectMomentumHits -= 1
					end
					if momBonus ~= 0 then
						if side == "P1" then rt.momentumP1 = clamp(rt.momentumP1 + momBonus, 0, 1)
						else rt.momentumP2 = clamp(rt.momentumP2 + momBonus, 0, 1) end
					end
				end

				if side == "P1" then
					rt.progress = clamp(rt.progress - pushScore, -1, 1)
				else
					rt.progress = clamp(rt.progress + pushScore, -1, 1)
				end
			end

			-- new center (only after THIS click)
			local newCenter = pickCenterWithin(zone.ok)
			if side == "P1" then rt.centerP1 = newCenter else rt.centerP2 = newCenter end

			local plr = (side == "P1") and state.p1 or state.p2
			if plr then
				safeFire(plr, "ClickAck", {
					tableId = state.id,
					turn = state.turn,
					rating = rating,
					pointer = pointer01,
					center = newCenter,
					stamina = pr.stamina,
					momentum = (side == "P1") and rt.momentumP1 or rt.momentumP2,
					combo = (side == "P1") and rt.comboP1 or rt.comboP2,
					baseSpeed = baseSpeed,
					zone = { okay = zone.ok, good = zone.good, perfect = zone.perfect },
				})
			end

			local who = (side == "P1") and (state.p1 and state.p1.Name or "AI") or (state.p2 and state.p2.Name or "AI")
			serverLog(state, (rating == "MISS") and "MISS" or "HIT", ("%s %s"):format(who, rating))

			fireProgress()
		end

		-- regen/vitals loop
		task.spawn(function()
			local lastVitals = 0
			while state.running and state.cancelToken == myToken and state.round == rt and rt.active do
				local t = workspace:GetServerTimeNow()
				if t >= rt.endTime then break end

				recomputeEffective(t, rt.prP1)
				recomputeEffective(t, rt.prP2)

				rt.prP1.stamina = clamp(rt.prP1.stamina + (rt.prP1.regenPerSec * REGEN_TICK), 0, rt.prP1.staminaMax)
				rt.prP2.stamina = clamp(rt.prP2.stamina + (rt.prP2.regenPerSec * REGEN_TICK), 0, rt.prP2.staminaMax)

				local decayBase = 0.030
				rt.momentumP1 = clamp(rt.momentumP1 - decayBase * (rt.prP1.momDecayMult or 1) * REGEN_TICK, 0, 1)
				rt.momentumP2 = clamp(rt.momentumP2 - decayBase * (rt.prP2.momDecayMult or 1) * REGEN_TICK, 0, 1)

				if (t - lastVitals) >= VITALS_TICK then
					lastVitals = t
					local speedScale, zoneScale = difficultyScales(rt, t)
					if state.p1 then
						local z = computeZones(rt.prP1.windowMult, zoneScale)
						safeFire(state.p1, "Vitals", {
							tableId = state.id,
							stamina = rt.prP1.stamina,
							staminaMax = rt.prP1.staminaMax,
							momentum = rt.momentumP1,
							combo = rt.comboP1,
							baseSpeed = computeBaseSpeed(rt.prP1, speedScale),
							zone = { okay = z.ok, good = z.good, perfect = z.perfect },
							center = rt.centerP1,
						})
					end
					if state.p2 then
						local z = computeZones(rt.prP2.windowMult, zoneScale)
						safeFire(state.p2, "Vitals", {
							tableId = state.id,
							stamina = rt.prP2.stamina,
							staminaMax = rt.prP2.staminaMax,
							momentum = rt.momentumP2,
							combo = rt.comboP2,
							baseSpeed = computeBaseSpeed(rt.prP2, speedScale),
							zone = { okay = z.ok, good = z.good, perfect = z.perfect },
							center = rt.centerP2,
						})
					end
				end

				task.wait(REGEN_TICK)
			end
		end)

		-- mid-round event loop
		task.spawn(function()
			while state.running and state.cancelToken == myToken and state.round == rt and rt.active do
				local nowT = workspace:GetServerTimeNow()
				if nowT >= rt.endTime then break end

				local intensity = eventIntensity(rt, nowT)
				local cooldownScale = 1 - (0.6 * intensity)
				local activeScale = 1 + (0.35 * intensity)

				local cooldown = randRange(EVENT_COOLDOWN_MIN, EVENT_COOLDOWN_MAX) * cooldownScale
				local activeDuration = randRange(EVENT_ACTIVE_MIN, EVENT_ACTIVE_MAX) * activeScale

				local warnDelay = math.max(0, cooldown - 3)
				if warnDelay > 0 then
					task.wait(warnDelay)
					if not (state.running and state.cancelToken == myToken and state.round == rt and rt.active) then break end
					serverLog(state, "WARN", "Event incoming...")
					safeFireBoth(state.p1, state.p2, "EventWarn", { tableId = state.id, text = "Event incoming..." })
					task.wait(3)
				else
					task.wait(cooldown)
				end
				if not (state.running and state.cancelToken == myToken and state.round == rt and rt.active) then break end

				local event = ROUND_EVENTS[math.random(1, #ROUND_EVENTS)]
				local expiresAt = workspace:GetServerTimeNow() + activeDuration

				local effects = {}
				if event.speedMin then
					effects.SliderSpeedMult = randRange(event.speedMin, event.speedMax or event.speedMin)
				end
				if event.zoneMin then
					effects.WindowMult = randRange(event.zoneMin, event.zoneMax or event.zoneMin)
				end

				local targetRoll = math.random()
				local bothChance = clamp(0.5 + (0.45 * intensity), 0, 0.95)
				local target = "both"
				if targetRoll < (1 - bothChance) * 0.5 then
					target = "P1"
				elseif targetRoll < (1 - bothChance) then
					target = "P2"
				end

				if target == "P1" then
					table.insert(rt.prP1.active, { expires = expiresAt, effects = effects })
					recomputeEffective(workspace:GetServerTimeNow(), rt.prP1)
				elseif target == "P2" then
					table.insert(rt.prP2.active, { expires = expiresAt, effects = effects })
					recomputeEffective(workspace:GetServerTimeNow(), rt.prP2)
				else
					table.insert(rt.prP1.active, { expires = expiresAt, effects = effects })
					table.insert(rt.prP2.active, { expires = expiresAt, effects = effects })
					recomputeEffective(workspace:GetServerTimeNow(), rt.prP1)
					recomputeEffective(workspace:GetServerTimeNow(), rt.prP2)
				end

				local targetLabel = (target == "both") and "Both" or target
				serverLog(state, "WARN", ("%s (%s)"):format(event.log, targetLabel))

				task.wait(activeDuration)
			end
		end)

		-- AI loop
		local function startAILoop(side)
			local aiChar = (side == "P1") and state.aiChar1 or state.aiChar2
			if not aiChar then return end

			local diff = (side == "P1") and state.aiDifficulty1 or state.aiDifficulty2
			local cfg = getAICfg(diff)

			ensureAITalent(aiChar, diff)

			local lastClick = 0
			local lastSkill = 0
			local key = (side == "P1") and "AI_P1" or "AI_P2"
			local focusHold = 0
			local pendingClickAt = 0

			task.spawn(function()
				while state.running and state.cancelToken == myToken and state.round == rt and rt.active do
					local nowT = workspace:GetServerTimeNow()
					if nowT >= rt.endTime then break end
					if nowT < rt.startTime then task.wait(cfg.think) continue end

					-- try skill
					if (nowT - lastSkill) >= (cfg.minSkill or 2.0) and math.random() < (cfg.skillChance or 0.1) then
						-- pick a usable slot
						local pr = (side == "P1") and rt.prP1 or rt.prP2
						recomputeEffective(nowT, pr)
						local skills = getSkillsFromActor(aiChar)

						local slotPick = nil
						local slotOrder = cfg.preferSkillSlots or {1,2,3}
						for _, s in ipairs(slotOrder) do
							if skills[s] and nowT >= (pr.cooldownEnd[s] or 0) then
								local eff = (typeof(skills[s].Effects)=="table") and skills[s].Effects or {}
								local cost = tonumber(eff.StaminaCost) or 0
								if cost <= 0 or pr.stamina >= cost then
									slotPick = s
									break
								end
							end
						end

						if slotPick then
							local ok = applySkill(state, rt, side, aiChar, slotPick)
							if ok then lastSkill = nowT end
						end
					end

					if (nowT - lastClick) < cfg.minClick then
						focusHold = clamp(focusHold - cfg.think, 0, cfg.lockTime)
						pendingClickAt = 0
						task.wait(cfg.think)
						continue
					end

					local pr = (side == "P1") and rt.prP1 or rt.prP2
					recomputeEffective(nowT, pr)

					if pr.stamina <= 0 then
						focusHold = 0
						pendingClickAt = 0
						task.wait(cfg.think)
						continue
					end

					local speedScale, zoneScale = difficultyScales(rt, nowT)
					local baseSpeed = computeBaseSpeed(pr, speedScale)
					local t = math.max(0, nowT - rt.startTime)
					local pointer01 = pointerAtTime(baseSpeed, t)

					local perceived = clamp(pointer01 + ((math.random() - 0.5) * 2 * cfg.noise), 0, 1)

					local center = (side == "P1") and rt.centerP1 or rt.centerP2
					local zone = computeZones(pr.windowMult, zoneScale)
					local r = ratingFromPointer(perceived, center, zone)

					local okToClick = false
					if cfg.want == "OKAY" then okToClick = (r ~= "MISS")
					elseif cfg.want == "GOOD" then okToClick = (r == "GOOD" or r == "PERFECT")
					elseif cfg.want == "PERFECT" then okToClick = (r == "PERFECT") end

					if okToClick then
						focusHold = clamp(focusHold + cfg.think, 0, cfg.lockTime)
						if focusHold >= cfg.lockTime and pendingClickAt == 0 then
							local jitter = (cfg.reactJitter or 0)
							pendingClickAt = nowT + (cfg.react or 0.04) + (math.random() * jitter)
						end
					else
						focusHold = clamp(focusHold - cfg.think * 1.4, 0, cfg.lockTime)
						pendingClickAt = 0
					end

					if pendingClickAt > 0 and nowT >= pendingClickAt then
						lastClick = nowT
						pendingClickAt = 0
						processSubmit(side, nowT, key, center)
					end

					task.wait(cfg.think)
				end
			end)
		end

		if state.ai1 then startAILoop("P1") end
		if state.ai2 then startAILoop("P2") end

		-- round end
		local roundWinner = nil
		while state.running and state.cancelToken == myToken do
			local t = workspace:GetServerTimeNow()
			if t >= rt.endTime then break end
			if rt.progress <= -1 then roundWinner = "P1"; break end
			if rt.progress >=  1 then roundWinner = "P2"; break end
			task.wait(0.05)
		end

		rt.active = false

		if not roundWinner then
			if rt.progress < 0 then roundWinner = "P1"
			elseif rt.progress > 0 then roundWinner = "P2"
			else
				if rt.ticksP1 > rt.ticksP2 then roundWinner = "P1"
				elseif rt.ticksP2 > rt.ticksP1 then roundWinner = "P2"
				else roundWinner = "TIE" end
			end
		end

		if roundWinner == "P1" then state.winsP1 += 1 end
		if roundWinner == "P2" then state.winsP2 += 1 end

		safeFireBoth(state.p1, state.p2, "TurnEnd", {
			tableId = state.id,
			turn = state.turn,
			winsP1 = state.winsP1,
			winsP2 = state.winsP2,
			bestOf = BEST_OF,
			ticksP1 = rt.ticksP1,
			ticksP2 = rt.ticksP2,
			progress = rt.progress,
			roundWinner = roundWinner,
		})

		serverLog(state, "INFO", ("Round %d ended: %s"):format(state.turn, roundWinner))

		if state.winsP1 >= WINS_NEEDED or state.winsP2 >= WINS_NEEDED then
			local resultP1 = (state.winsP1 > state.winsP2) and "WIN" or "LOSE"
			local resultP2 = (resultP1 == "WIN") and "LOSE" or "WIN"
			if state.p1 then safeFire(state.p1, "MatchEnd", { tableId = state.id, result = resultP1, winsP1 = state.winsP1, winsP2 = state.winsP2 }) end
			if state.p2 then safeFire(state.p2, "MatchEnd", { tableId = state.id, result = resultP2, winsP1 = state.winsP1, winsP2 = state.winsP2 }) end
			if state.p1 then
				recordMatchResult(state.p1, resultP1 == "WIN", resultP1 == "LOSE")
				applyMatchStats(state.p1, resultP1 == "WIN", resultP1 == "LOSE")
			end
			if state.p2 then
				recordMatchResult(state.p2, resultP2 == "WIN", resultP2 == "LOSE")
				applyMatchStats(state.p2, resultP2 == "WIN", resultP2 == "LOSE")
			end
			if state.aiMatchOwner then
				local owner = state.aiMatchOwner
				local ownerResult = (owner == state.p1) and resultP1 or resultP2
				aiDoneEvent:Fire(owner, ownerResult == "WIN")
				state.aiMatchOwner = nil
			end
			serverLog(state, "INFO", ("MATCH END: %s-%s"):format(state.winsP1, state.winsP2))
			break
		end

		task.wait(1.0)
	end

	state.round = nil
	state.running = false
end

-- ======================================================
-- CLICK + SKILLS (Players only)
-- ======================================================
local function getRole(state, plr)
	if state.p1 == plr then return "P1" end
	if state.p2 == plr then return "P2" end
	return nil
end

ArmWrestleEvent.OnServerEvent:Connect(function(plr, action, data)
	if typeof(action) ~= "string" then return end
	data = (typeof(data) == "table") and data or {}

	if action ~= "Submit" and action ~= "UseSkill" then return end

	local tableId = tostring(data.tableId or "")
	local state = Tables[tableId]
	if not state then return end

	local rt = state.round
	if not rt or not rt.active then return end

	local role = getRole(state, plr)
	if not role then return end

	local nowServer = workspace:GetServerTimeNow()
	if nowServer < rt.startTime or nowServer > rt.endTime then return end

	local pr = (role == "P1") and rt.prP1 or rt.prP2
	if not pr then return end

	-- USE SKILL
	if action == "UseSkill" then
		local slot = tonumber(data.slot) or 0
		local ok, err = applySkill(state, rt, role, plr, slot)
		if not ok then
			safeFire(plr, "SkillAck", { tableId = tableId, slot = slot, ok = false, err = err or "Skill failed." })
		end
		return
	end

	-- SUBMIT CLICK (clientT + centerSeen)
	local clientT = tonumber(data.clientT)
	local clickT = nowServer
	if clientT then
		clientT = clamp(clientT, rt.startTime, rt.endTime)
		local drift = (clientT - nowServer)
		if math.abs(drift) <= CLIENT_TIME_TOLERANCE then
			clickT = clientT
		else
			serverLog(state, "WARN", ("%s clientT drift %.2fs (ignored)"):format(plr.Name, drift))
		end
	end

	local centerSeen = tonumber(data.centerSeen)

	-- spam control
	local last = rt.lastClickTS[plr] or 0
	if (nowServer - last) < MIN_CLICK_INTERVAL then return end
	rt.lastClickTS[plr] = nowServer

	if pr.stamina <= 0 then return end

	recomputeEffective(nowServer, pr)

	local cost = computeClickCost(pr)
	pr.stamina = clamp(pr.stamina - cost, 0, pr.staminaMax)

	local speedScale, zoneScale = difficultyScales(rt, clickT)
	local baseSpeed = computeBaseSpeed(pr, speedScale)
	local t = math.max(0, clickT - rt.startTime)
	local pointer01 = pointerAtTime(baseSpeed, t)

	local centerServer = (role=="P1") and rt.centerP1 or rt.centerP2
	local zone = computeZones(pr.windowMult, zoneScale)

	local centerUsed = centerServer
	if typeof(centerSeen) == "number" and math.abs(centerSeen - centerServer) <= CENTER_SEEN_TOL then
		centerUsed = centerSeen
	end

	local rating = ratingFromPointer(pointer01, centerUsed, zone)

	-- momentum
	if rating == "MISS" then
		if role == "P1" then rt.comboP1 = 0 else rt.comboP2 = 0 end
	else
		if role == "P1" then rt.comboP1 += 1 else rt.comboP2 += 1 end
	end

	local mg = (MOM_GAIN[rating] or 0) * (pr.momGainMult or 1.0)
	if role == "P1" then rt.momentumP1 = clamp(rt.momentumP1 + mg, 0, 1)
	else rt.momentumP2 = clamp(rt.momentumP2 + mg, 0, 1) end

	-- ticks + progress
	local gained = ticksForRating(rating)
	if gained > 0 then
		if role == "P1" then rt.ticksP1 += gained else rt.ticksP2 += gained end

		local baseScore = computeBaseScore(pr)
		local curMom = (role=="P1") and rt.momentumP1 or rt.momentumP2
		local momMult = 1 + (curMom * MOMENTUM_SCORE_SCALE)
		local pushScore = gained * PROGRESS_STEP_PER_TICK * baseScore * momMult

		if role == "P1" then
			rt.progress = clamp(rt.progress - pushScore, -1, 1)
		else
			rt.progress = clamp(rt.progress + pushScore, -1, 1)
		end
	end

	-- new center AFTER this click
	local newCenter = pickCenterWithin(zone.ok)
	if role == "P1" then rt.centerP1 = newCenter else rt.centerP2 = newCenter end

	safeFire(plr, "ClickAck", {
		tableId = tableId,
		turn = state.turn,
		rating = rating,
		pointer = pointer01,
		center = newCenter,
		stamina = pr.stamina,
		momentum = (role=="P1") and rt.momentumP1 or rt.momentumP2,
		combo = (role=="P1") and rt.comboP1 or rt.comboP2,
		baseSpeed = baseSpeed,
		zone = { okay = zone.ok, good = zone.good, perfect = zone.perfect },
	})

	serverLog(state, (rating=="MISS") and "MISS" or "HIT", ("%s %s"):format(plr.Name, rating))

	safeFireBoth(state.p1, state.p2, "Progress", {
		tableId = state.id,
		turn = state.turn,
		progress = rt.progress,
		ticksP1 = rt.ticksP1,
		ticksP2 = rt.ticksP2,
	})
end)

-- ======================================================
-- TABLE REGISTRATION
-- ======================================================
local function registerTable(model)
	local id = model.Name

	local seatP1Folder = model:FindFirstChild("SeatP1")
	local seatP2Folder = model:FindFirstChild("SeatP2")

	local seatP1 = findSeatIn(seatP1Folder, model)
	local seatP2 = findSeatIn(seatP2Folder, model)

	if not seatP1 or not seatP2 then
		warn("[ArmWrestleService] Table missing seats:", id)
		return
	end

	local state = {
		id = id,
		model = model,
		seatP1 = seatP1,
		seatP2 = seatP2,

		p1 = nil,
		p2 = nil,

		ai1 = false,
		ai2 = false,
		aiChar1 = nil,
		aiChar2 = nil,
		aiDifficulty1 = "Rookie",
		aiDifficulty2 = "Rookie",

		hasOpponent1 = false,
		hasOpponent2 = false,
		hasRealPlayer = false,

		running = false,
		cancelToken = 0,
		winsP1 = 0,
		winsP2 = 0,
		turn = 0,
		round = nil,
	}

	Tables[id] = state

	local function refresh()
		local p1 = getPlayerFromSeat(state.seatP1)
		local p2 = getPlayerFromSeat(state.seatP2)
		local c1 = getCharacterFromSeat(state.seatP1)
		local c2 = getCharacterFromSeat(state.seatP2)

		if state.p1 and state.p1 ~= p1 then cancelTable(state, "P1_LEFT") end
		if state.p2 and state.p2 ~= p2 then cancelTable(state, "P2_LEFT") end

		state.p1 = p1
		state.p2 = p2

		state.ai1 = (p1 == nil and isAICharacter(c1))
		state.ai2 = (p2 == nil and isAICharacter(c2))

		state.aiChar1 = state.ai1 and c1 or nil
		state.aiChar2 = state.ai2 and c2 or nil
		state.aiDifficulty1 = state.ai1 and getAIDifficulty(c1) or "Rookie"
		state.aiDifficulty2 = state.ai2 and getAIDifficulty(c2) or "Rookie"

		if state.aiChar1 then ensureAITalent(state.aiChar1, state.aiDifficulty1) end
		if state.aiChar2 then ensureAITalent(state.aiChar2, state.aiDifficulty2) end

		state.hasOpponent1 = (state.p1 ~= nil) or state.ai1
		state.hasOpponent2 = (state.p2 ~= nil) or state.ai2
		state.hasRealPlayer = (state.p1 ~= nil) or (state.p2 ~= nil)

		local oppNameForP1 = (state.p2 and state.p2.Name) or (state.ai2 and ("Training Bot ["..state.aiDifficulty2.."]")) or nil
		local oppNameForP2 = (state.p1 and state.p1.Name) or (state.ai1 and ("Training Bot ["..state.aiDifficulty1.."]")) or nil

		if state.p1 then
			safeFire(state.p1, "SeatStatus", { tableId = id, role = "P1", opponent = oppNameForP1, bestOf = BEST_OF })
		end
		if state.p2 then
			safeFire(state.p2, "SeatStatus", { tableId = id, role = "P2", opponent = oppNameForP2, bestOf = BEST_OF })
		end

		if state.hasOpponent1 and state.hasOpponent2 and state.hasRealPlayer and not state.running then
			task.spawn(function() startMatch(state) end)
		end
	end

	state.seatP1:GetPropertyChangedSignal("Occupant"):Connect(refresh)
	state.seatP2:GetPropertyChangedSignal("Occupant"):Connect(refresh)
	refresh()

	print("[ArmWrestleService] Registered table:", id)
end

if TABLES_FOLDER then
	for _, child in ipairs(TABLES_FOLDER:GetChildren()) do
		if child:IsA("Model") then
			registerTable(child)
		end
	end

	TABLES_FOLDER.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.wait(0.1)
			registerTable(child)
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	ensureLeaderstats(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	for _, state in pairs(Tables) do
		if state.p1 == plr or state.p2 == plr then
			cancelTable(state, "PLAYER_REMOVED")
			if state.p1 == plr then state.p1 = nil end
			if state.p2 == plr then state.p2 = nil end
		end
	end
end)

print("[ArmWrestleService] Loaded ✅ (Accurate clicks + centerSeen fix + AI talents/skills + difficulties + mid-round events)")
