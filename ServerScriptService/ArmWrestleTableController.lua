--// ArmWrestleTableController (ModuleScript) - ServerScriptService
-- Per-table isolated controller (multi-table safe).
-- Includes new Grip Triangle: Crush/Focus/Fortify mapped to Attack/Neutral/Defense internally.

local Players = game:GetService("Players")


local Controller = {}
Controller.__index = Controller

-- =========================
-- CONFIG
-- =========================
local DEFAULT_CONFIG = {
	BestOf = 3,
	RoundsToWin = 2,

	-- turn cadence
	TurnDuration = 4.0,     -- seconds to click
	TurnInterval = 0.20,    -- delay between turns
	MaxTurnsPerRound = 16,  -- ~1 minute cap depending on interval

	-- base minigame
	BasePointerSpeed = 0.95,
	BaseZoneOkay = 0.22,
	BaseZoneGood = 0.14,
	BaseZonePerfect = 0.08,

	PushStep = 0.22,
	WinProgress = 1.00,

	-- difficulty scaling
	DifficultyPerTurn = 0.03,
	MaxDifficulty = 1.55,
	LosingAssist = 0.40,

	-- bar scaling
	MinBarScale = 0.80,
	MaxBarScale = 1.18,

	-- stamina
	StaminaCost = { Neutral = 6, Attack = 12, Defense = 9 },
	BaseRegen = 7,
	RegenPerEndurance = 0.06,
	RegenCap = 14,
	FatigueMaxMult = 1.30,
	StunResetStamina = 100,

	-- defense safety (small comeback helper)
	DefenseLastStandSaveProgress = 0.92,

	-- =========================
	-- GRIP TRIANGLE
	-- Attack = CRUSH
	-- Neutral = FOCUS
	-- Defense = FORTIFY
	-- Crush beats Fortify
	-- Focus beats Crush
	-- Fortify beats Focus
	-- =========================
	GripBias = 1.12,        -- power multiplier for favored grip
	GripNerf = 0.90,        -- power multiplier for unfavored grip

	-- Crush whiff vs Focus => Dazed next turn
	DazedTurns = 1,
	DazedPointerMult = 1.18,  -- harder (faster pointer)
	DazedZoneMult = 0.88,     -- harder (smaller zones)

	-- Focus win vs Crush => Perfect Window (next click auto-perfect, once)
	PerfectWindowTurns = 1,

	-- Fortify win vs Focus => Resolve gain
	ResolveGain = 25,
	ResolveMax = 100,

	-- Fortify held too long => Strain (weakens next Crush)
	FortifyHoldToStrain = 3,     -- after N consecutive fortify turns
	StrainTurns = 1,
	StrainCrushWinMult = 0.92,   -- crush bonus reduced
}

local VALID_GRIPS = {Neutral=true, Attack=true, Defense=true}

-- =========================
-- HELPERS
-- =========================
local function clamp(x,a,b) if x<a then return a elseif x>b then return b end return x end
local function pingpong01(x) local m=x%2 if m<=1 then return m end return 2-m end

local function safeStat(player: Player, statName: string): number
	local v = player:GetAttribute(statName)
	if typeof(v) == "number" then return math.max(0, v) end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local obj = ls:FindFirstChild(statName)
		if obj and obj:IsA("NumberValue") then return math.max(0, obj.Value) end
	end
	return 1
end

local function getStats(player: Player)
	return {
		Strength = safeStat(player, "Strength"),
		Speed = safeStat(player, "Speed"),
		Fortitude = safeStat(player, "Fortitude"),
		Endurance = safeStat(player, "Endurance"),
	}
end

local function sumCore(s)
	return (s.Strength * 1.0) + (s.Speed * 0.7) + (s.Fortitude * 0.6) + (s.Endurance * 0.6)
end

local function computeAdvantageScale(myStats, oppStats)
	local my = sumCore(myStats)
	local opp = sumCore(oppStats)
	if opp <= 0 then opp = 0.01 end
	local ratio = my / opp
	local zoneScale = clamp(ratio, 0.65, 1.55)
	local speedScale = clamp(1 / ratio, 0.70, 1.30)
	return zoneScale, speedScale, ratio
end

local function computeDifficultyScalar(cfg, turn, losingAmt01)
	local global = 1 + ((turn - 1) * cfg.DifficultyPerTurn)
	global = clamp(global, 1.0, cfg.MaxDifficulty)

	local assist = 1 - (losingAmt01 * cfg.LosingAssist)
	assist = clamp(assist, 0.78, 1.0)

	return global * assist
end

local function ratingFromDistance(dist, zoneOkay, zoneGood, zonePerfect)
	local pR = zonePerfect * 0.5
	local gR = zoneGood * 0.5
	local oR = zoneOkay * 0.5
	if dist <= pR then return "PERFECT", 3 end
	if dist <= gR then return "GOOD", 2 end
	if dist <= oR then return "OKAY", 1 end
	return "MISS", 0
end

local function computePointerPos(clickTime, startTime, pointerSpeed)
	local t = math.max(0, clickTime - startTime)
	return pingpong01(t * pointerSpeed)
end

-- stamina attrs
local function getStamina(plr: Player): number
	return tonumber(plr:GetAttribute("AW_Stamina")) or 0
end
local function getMaxStamina(plr: Player, fallback: number): number
	return tonumber(plr:GetAttribute("AW_StaminaMax")) or fallback
end
local function setStamina(plr: Player, v: number) plr:SetAttribute("AW_Stamina", v) end
local function setMaxStamina(plr: Player, v: number) plr:SetAttribute("AW_StaminaMax", v) end

-- resolve attrs
local function getResolve(plr: Player): number
	return tonumber(plr:GetAttribute("AW_Resolve")) or 0
end
local function setResolve(plr: Player, v: number) plr:SetAttribute("AW_Resolve", v) end

-- Grip triangle: favored grip
local function gripBeats(gA: string, gB: string): boolean
	-- Attack(Crush) beats Defense(Fortify)
	-- Neutral(Focus) beats Attack(Crush)
	-- Defense(Fortify) beats Neutral(Focus)
	return (gA=="Attack" and gB=="Defense")
		or (gA=="Neutral" and gB=="Attack")
		or (gA=="Defense" and gB=="Neutral")
end

-- =========================
-- CONSTRUCTOR
-- =========================
local function resolveSeat(node: Instance?): Seat?
	if not node then return nil end
	if node:IsA("Seat") then return node end
	return node:FindFirstChildWhichIsA("Seat", true)
end

function Controller.new(tableModel: Model, remoteEvent: RemoteEvent)
	assert(tableModel and tableModel:IsA("Model"), "tableModel must be a Model")
	assert(remoteEvent and remoteEvent:IsA("RemoteEvent"), "remoteEvent must be a RemoteEvent")

	local node1 = tableModel:FindFirstChild("SeatP1", true)
	local node2 = tableModel:FindFirstChild("SeatP2", true)
	local seatP1 = resolveSeat(node1)
	local seatP2 = resolveSeat(node2)

	assert(seatP1 and seatP1:IsA("Seat"), ("[%s] Missing SeatP1 Seat (SeatP1 must be Seat or contain Seat)"):format(tableModel.Name))
	assert(seatP2 and seatP2:IsA("Seat"), ("[%s] Missing SeatP2 Seat (SeatP2 must be Seat or contain Seat)"):format(tableModel.Name))

	local self = setmetatable({}, Controller)
	self.model = tableModel
	self.tableId = tableModel.Name
	self.remote = remoteEvent
	self.seatP1 = seatP1
	self.seatP2 = seatP2

	self.cfg = table.clone(DEFAULT_CONFIG)
	for k, v in pairs(self.cfg) do
		local av = tableModel:GetAttribute(k)
		if typeof(av) == typeof(v) then
			self.cfg[k] = av
		end
	end

	-- match state
	self.matchActive = false
	self.matchId = 0
	self.p1, self.p2 = nil, nil
	self.prevP1, self.prevP2 = nil, nil

	self.progress = 0
	self.roundIndex = 1
	self.winsP1, self.winsP2 = 0, 0

	self.turnIndex = 0
	self.turnStartTime = 0
	self.targetCenter = 0
	self.turnSettings = {}
	self.submitted = {}
	self.usedGrip = {}
	self.stunnedThisTurn = {}
	self.turnToken = 0
	self.resolvedTurnIndex = 0

	-- persistent grip selections
	self.gripChoice = {}

	-- new triangle state
	self.dazedTurns = {}
	self.perfectReady = {}
	self.perfectTurns = {}
	self.fortifyHold = {}
	self.strainTurns = {}

	self.defenseLastStandAvail = {}

	-- conns
	self._conns = {}
	table.insert(self._conns, seatP1:GetPropertyChangedSignal("Occupant"):Connect(function() self:_onSeatsChanged() end))
	table.insert(self._conns, seatP2:GetPropertyChangedSignal("Occupant"):Connect(function() self:_onSeatsChanged() end))

	self:_onSeatsChanged()
	return self
end

function Controller:Destroy()
	for _, c in ipairs(self._conns) do if c then c:Disconnect() end end
	self._conns = {}
	self:_resetMatchState()
end

-- =========================
-- INTERNAL
-- =========================
function Controller:_fire(plr: Player, action: string, data: table)
	data = data or {}
	data.tableId = self.tableId
	self.remote:FireClient(plr, action, data)
end

function Controller:_resetMatchState()
	self.matchActive = false
	self.progress = 0
	self.roundIndex = 1
	self.winsP1, self.winsP2 = 0, 0
	self.turnIndex = 0
	self.turnStartTime = 0
	self.targetCenter = 0
	self.turnSettings = {}
	self.submitted = {}
	self.usedGrip = {}
	self.stunnedThisTurn = {}
	self.turnToken = 0
	self.resolvedTurnIndex = 0
	self.defenseLastStandAvail = {}
end

function Controller:_getPlayerFromSeat(seat: Seat): Player?
	local occ = seat.Occupant
	if not occ then return nil end
	return Players:GetPlayerFromCharacter(occ.Parent)
end

function Controller:_setGrip(plr: Player, grip: string): boolean
	if not VALID_GRIPS[grip] then return false end
	self.gripChoice[plr] = grip
	return true
end

function Controller:_getGrip(plr: Player): string
	return self.gripChoice[plr] or "Neutral"
end

function Controller:_regenAmount(plr: Player)
	local e = getStats(plr).Endurance
	local r = self.cfg.BaseRegen + (e * self.cfg.RegenPerEndurance)
	return clamp(r, 0, self.cfg.RegenCap)
end

function Controller:_fatigueMult(plr: Player)
	local cur = getStamina(plr)
	local mx = math.max(1, getMaxStamina(plr, self.cfg.StunResetStamina))
	local ratio = clamp(cur / mx, 0, 1)
	local t = 1 - ratio
	return 1 + (t * (self.cfg.FatigueMaxMult - 1))
end

function Controller:_clampStamina(plr: Player)
	local mx = math.max(1, getMaxStamina(plr, self.cfg.StunResetStamina))
	setStamina(plr, clamp(getStamina(plr), 0, mx))
end

function Controller:_canAfford(plr: Player, grip: string)
	local cost = self.cfg.StaminaCost[grip] or self.cfg.StaminaCost.Neutral
	return getStamina(plr) >= cost, cost
end

function Controller:_charge(plr: Player, amount: number)
	setStamina(plr, getStamina(plr) - amount)
	self:_clampStamina(plr)
end

function Controller:_give(plr: Player, amount: number)
	setStamina(plr, getStamina(plr) + amount)
	self:_clampStamina(plr)
end

function Controller:_giveResolve(plr: Player, amount: number)
	local v = clamp(getResolve(plr) + amount, 0, self.cfg.ResolveMax)
	setResolve(plr, v)
end

function Controller:_cancelMatch(reason: string)
	local a, b = self.p1, self.p2
	if a then self:_fire(a, "MatchCancelled", {reason = reason}) end
	if b then self:_fire(b, "MatchCancelled", {reason = reason}) end
	self:_resetMatchState()
end

function Controller:_endMatch(winner: Player, loser: Player)
	self:_fire(winner, "MatchEnd", {result="WIN", winsP1=self.winsP1, winsP2=self.winsP2})
	self:_fire(loser,  "MatchEnd", {result="LOSE", winsP1=self.winsP1, winsP2=self.winsP2})
	self:_resetMatchState()
end

function Controller:_startNewRound()
	self.progress = 0
	self.turnIndex = 0
	self.submitted[self.p1], self.submitted[self.p2] = nil, nil
	self.usedGrip[self.p1], self.usedGrip[self.p2] = nil, nil
	self.stunnedThisTurn[self.p1], self.stunnedThisTurn[self.p2] = false, false
	self.turnSettings = {}
	self.resolvedTurnIndex = 0
	self.turnToken += 1
	self.defenseLastStandAvail[self.p1] = true
	self.defenseLastStandAvail[self.p2] = true
end

function Controller:_awardRoundWin(roundWinner: Player)
	if not self.p1 or not self.p2 then return end
	local winnerRole = (roundWinner == self.p1) and "P1" or "P2"
	if winnerRole == "P1" then self.winsP1 += 1 else self.winsP2 += 1 end

	self:_fire(self.p1, "RoundEnd", {round=self.roundIndex, winner=winnerRole, winsP1=self.winsP1, winsP2=self.winsP2})
	self:_fire(self.p2, "RoundEnd", {round=self.roundIndex, winner=winnerRole, winsP1=self.winsP1, winsP2=self.winsP2})

	if self.winsP1 >= self.cfg.RoundsToWin then self:_endMatch(self.p1, self.p2); return end
	if self.winsP2 >= self.cfg.RoundsToWin then self:_endMatch(self.p2, self.p1); return end

	self.roundIndex += 1
	self:_startNewRound()

	task.delay(0.9, function()
		if self.matchActive and self.p1 and self.p2 then
			self:_startTurn()
		end
	end)
end

function Controller:_pushTurnStart(plr: Player, opponent: Player)
	local base = self.turnSettings[plr]
	local wanted = self:_getGrip(plr)

	local mx = getMaxStamina(plr, self.cfg.StunResetStamina)
	local cur = getStamina(plr)

	local afford, cost = self:_canAfford(plr, wanted)
	local effective = (self.stunnedThisTurn[plr] and "Neutral") or (afford and wanted or "Neutral")

	self:_fire(plr, "TurnStart", {
		matchId = self.matchId,
		round = self.roundIndex,
		bestOf = self.cfg.BestOf,
		winsP1 = self.winsP1,
		winsP2 = self.winsP2,

		turn = self.turnIndex,
		startTime = self.turnStartTime,
		duration = self.cfg.TurnDuration,

		targetCenter = self.targetCenter,
		pointerSpeed = base.pointerSpeed,
		zone = {okay=base.zoneOk, good=base.zoneGood, perfect=base.zonePerf},

		progress = self.progress,
		opponent = opponent.Name,
		barScale = base.barScale,
		difficulty = base.difficulty,

		grip = effective,
		gripWanted = wanted,
		gripCost = cost,
		gripAffordable = afford,

		stamina = {cur = cur, max = mx},
		resolve = {cur = getResolve(plr), max = self.cfg.ResolveMax},

		status = {
			dazed = (self.dazedTurns[plr] or 0) > 0,
			perfectReady = self.perfectReady[plr] == true,
			strained = (self.strainTurns[plr] or 0) > 0,
		},

		stunned = self.stunnedThisTurn[plr] == true,
	})
end

function Controller:_forceMiss(plr: Player)
	if not self.submitted[plr] then
		self.submitted[plr] = {turn=self.turnIndex, clickTime=nil, forcedMiss=true}
		self.usedGrip[plr] = self:_getGrip(plr)
	end
end

-- =========================
-- TURN LIFECYCLE
-- =========================
function Controller:_resolveTurn()
	if not self.matchActive or not self.p1 or not self.p2 then return end
	if self.resolvedTurnIndex == self.turnIndex then return end

	local sub1 = self.submitted[self.p1]
	local sub2 = self.submitted[self.p2]
	if not sub1 or not sub2 then return end
	if sub1.turn ~= self.turnIndex or sub2.turn ~= self.turnIndex then return end

	self.resolvedTurnIndex = self.turnIndex

	local p1, p2 = self.p1, self.p2
	local g1Wanted = self.usedGrip[p1] or self:_getGrip(p1)
	local g2Wanted = self.usedGrip[p2] or self:_getGrip(p2)

	-- apply stamina afford + stun
	local function effectiveGrip(plr: Player, wanted: string)
		if self.stunnedThisTurn[plr] then return "Neutral" end
		local afford = self:_canAfford(plr, wanted)
		return afford and wanted or "Neutral"
	end

	local g1 = effectiveGrip(p1, g1Wanted)
	local g2 = effectiveGrip(p2, g2Wanted)

	-- pay stamina cost
	self:_charge(p1, self.cfg.StaminaCost[g1] or self.cfg.StaminaCost.Neutral)
	self:_charge(p2, self.cfg.StaminaCost[g2] or self.cfg.StaminaCost.Neutral)

	-- compute ratings
	local base1 = self.turnSettings[p1]
	local base2 = self.turnSettings[p2]

	local r1, score1, pos1 = "MISS", 0, 0.0
	local r2, score2, pos2 = "MISS", 0, 0.0

	-- perfect window: auto-perfect once if ready
	local function consumePerfect(plr: Player)
		if self.perfectReady[plr] == true then
			self.perfectReady[plr] = false
			return true
		end
		return false
	end

	local p1AutoPerfect = (not sub1.forcedMiss) and (not self.stunnedThisTurn[p1]) and consumePerfect(p1)
	local p2AutoPerfect = (not sub2.forcedMiss) and (not self.stunnedThisTurn[p2]) and consumePerfect(p2)

	if p1AutoPerfect then
		r1, score1 = "PERFECT", 3
	else
		if not sub1.forcedMiss and sub1.clickTime and not self.stunnedThisTurn[p1] then
			pos1 = computePointerPos(sub1.clickTime, self.turnStartTime, base1.pointerSpeed)
			r1, score1 = ratingFromDistance(math.abs(pos1 - self.targetCenter), base1.zoneOk, base1.zoneGood, base1.zonePerf)
		end
	end

	if p2AutoPerfect then
		r2, score2 = "PERFECT", 3
	else
		if not sub2.forcedMiss and sub2.clickTime and not self.stunnedThisTurn[p2] then
			pos2 = computePointerPos(sub2.clickTime, self.turnStartTime, base2.pointerSpeed)
			r2, score2 = ratingFromDistance(math.abs(pos2 - self.targetCenter), base2.zoneOk, base2.zoneGood, base2.zonePerf)
		end
	end

	-- base power from stats + score
	local s1 = getStats(p1)
	local s2 = getStats(p2)

	local function power(baseScore, stats)
		local enduranceBase = 0.10 * clamp(stats.Endurance, 0, 100)
		local mult = 1 + (0.05 * clamp(stats.Strength, 0, 100)) + (0.02 * clamp(stats.Speed, 0, 100))
		return (baseScore + enduranceBase) * mult
	end

	local pwr1 = power(score1, s1)
	local pwr2 = power(score2, s2)

	-- Grip Triangle bias (rock-paper-scissors)
	if gripBeats(g1, g2) then
		pwr1 *= self.cfg.GripBias
		pwr2 *= self.cfg.GripNerf
	elseif gripBeats(g2, g1) then
		pwr2 *= self.cfg.GripBias
		pwr1 *= self.cfg.GripNerf
	end

	-- Strain weakens next Crush (Attack)
	if g1 == "Attack" and (self.strainTurns[p1] or 0) > 0 then
		pwr1 *= self.cfg.StrainCrushWinMult
		self.strainTurns[p1] -= 1
	end
	if g2 == "Attack" and (self.strainTurns[p2] or 0) > 0 then
		pwr2 *= self.cfg.StrainCrushWinMult
		self.strainTurns[p2] -= 1
	end

	-- delta from power difference
	local fortFactor = 1 / (1 + 0.03*(clamp(s1.Fortitude,0,100) + clamp(s2.Fortitude,0,100)))
	local delta = (pwr2 - pwr1) * self.cfg.PushStep * fortFactor
	-- delta > 0 => P2 won the exchange; delta < 0 => P1 won

	local newProgress = clamp(self.progress + delta, -self.cfg.WinProgress, self.cfg.WinProgress)

	-- Defense last stand (still useful to avoid instant pin once)
	if newProgress >= self.cfg.WinProgress and g1=="Defense" and self.defenseLastStandAvail[p1] then
		self.defenseLastStandAvail[p1] = false
		newProgress = self.cfg.DefenseLastStandSaveProgress
		self:_fire(p1, "DefenseSave", {who="YOU"})
		self:_fire(p2, "DefenseSave", {who="OPP"})
	end
	if newProgress <= -self.cfg.WinProgress and g2=="Defense" and self.defenseLastStandAvail[p2] then
		self.defenseLastStandAvail[p2] = false
		newProgress = -self.cfg.DefenseLastStandSaveProgress
		self:_fire(p2, "DefenseSave", {who="YOU"})
		self:_fire(p1, "DefenseSave", {who="OPP"})
	end

	self.progress = newProgress

	-- =========================
	-- TRIANGLE SPECIAL EFFECTS
	-- =========================
	-- Determine who won this exchange
	local p1Won = delta < 0
	local p2Won = delta > 0
	local tie = delta == 0

	-- Crush whiff vs Focus => dazed attacker next turn (only if Focus wins)
	if g1=="Attack" and g2=="Neutral" and p2Won then
		self.dazedTurns[p1] = self.cfg.DazedTurns
	end
	if g2=="Attack" and g1=="Neutral" and p1Won then
		self.dazedTurns[p2] = self.cfg.DazedTurns
	end

	-- Focus beats Crush => Perfect Window (next turn auto-perfect once)
	if g1=="Neutral" and g2=="Attack" and p1Won then
		self.perfectReady[p1] = true
		self.perfectTurns[p1] = self.cfg.PerfectWindowTurns
	end
	if g2=="Neutral" and g1=="Attack" and p2Won then
		self.perfectReady[p2] = true
		self.perfectTurns[p2] = self.cfg.PerfectWindowTurns
	end

	-- Fortify beats Focus => gain Resolve
	if g1=="Defense" and g2=="Neutral" and p1Won then
		self:_giveResolve(p1, self.cfg.ResolveGain)
	end
	if g2=="Defense" and g1=="Neutral" and p2Won then
		self:_giveResolve(p2, self.cfg.ResolveGain)
	end

	-- Fortify held too long => Strain on next Crush
	local function updateFortifyHold(plr: Player, grip: string)
		if grip == "Defense" then
			self.fortifyHold[plr] = (self.fortifyHold[plr] or 0) + 1
			if self.fortifyHold[plr] >= self.cfg.FortifyHoldToStrain then
				self.fortifyHold[plr] = 0
				self.strainTurns[plr] = math.max(self.strainTurns[plr] or 0, self.cfg.StrainTurns)
			end
		else
			self.fortifyHold[plr] = 0
		end
	end
	updateFortifyHold(p1, g1)
	updateFortifyHold(p2, g2)

	-- decay perfect window counter (if you want limited duration)
	local function tickPerfect(plr: Player)
		local t = self.perfectTurns[plr]
		if t and t > 0 then
			t -= 1
			self.perfectTurns[plr] = t
			if t <= 0 then
				self.perfectReady[plr] = false
			end
		end
	end
	tickPerfect(p1)
	tickPerfect(p2)

	-- =========================
	-- SEND TURN RESULT
	-- =========================
	self:_fire(p1, "TurnResult", {
		round=self.roundIndex, winsP1=self.winsP1, winsP2=self.winsP2, turn=self.turnIndex,
		your={rating=r1, pointer=pos1, timedOut=sub1.forcedMiss, autoPerfect=p1AutoPerfect},
		their={rating=r2},
		progress=self.progress,
		grip=g1,
		stamina={cur=getStamina(p1), max=getMaxStamina(p1, self.cfg.StunResetStamina)},
		resolve={cur=getResolve(p1), max=self.cfg.ResolveMax},
		status = {
			dazed = (self.dazedTurns[p1] or 0) > 0,
			perfectReady = self.perfectReady[p1] == true,
			strained = (self.strainTurns[p1] or 0) > 0,
		},
	})
	self:_fire(p2, "TurnResult", {
		round=self.roundIndex, winsP1=self.winsP1, winsP2=self.winsP2, turn=self.turnIndex,
		your={rating=r2, pointer=pos2, timedOut=sub2.forcedMiss, autoPerfect=p2AutoPerfect},
		their={rating=r1},
		progress=self.progress,
		grip=g2,
		stamina={cur=getStamina(p2), max=getMaxStamina(p2, self.cfg.StunResetStamina)},
		resolve={cur=getResolve(p2), max=self.cfg.ResolveMax},
		status = {
			dazed = (self.dazedTurns[p2] or 0) > 0,
			perfectReady = self.perfectReady[p2] == true,
			strained = (self.strainTurns[p2] or 0) > 0,
		},
	})

	-- win check
	if self.progress <= -self.cfg.WinProgress then self:_awardRoundWin(p1); return end
	if self.progress >=  self.cfg.WinProgress then self:_awardRoundWin(p2); return end

	task.delay(self.cfg.TurnInterval, function()
		if self.matchActive and self.p1 and self.p2 then
			self:_startTurn()
		end
	end)
end

function Controller:_startTurn()
	if not self.matchActive or not self.p1 or not self.p2 then return end

	self.turnIndex += 1
	self.turnToken += 1
	local myToken = self.turnToken
	self.resolvedTurnIndex = 0

	self.submitted[self.p1], self.submitted[self.p2] = nil, nil
	self.usedGrip[self.p1], self.usedGrip[self.p2] = nil, nil
	self.stunnedThisTurn[self.p1], self.stunnedThisTurn[self.p2] = false, false

	if self.turnIndex > self.cfg.MaxTurnsPerRound then
		local winner = (self.progress < 0) and self.p1 or ((self.progress > 0) and self.p2 or ((math.random(1,2)==1) and self.p1 or self.p2))
		self:_awardRoundWin(winner)
		return
	end

	-- stun check BEFORE regen
	local function applyStun(plr: Player)
		if getStamina(plr) <= 0 then
			self.stunnedThisTurn[plr] = true
			local mx = getMaxStamina(plr, self.cfg.StunResetStamina)
			if mx < self.cfg.StunResetStamina then setMaxStamina(plr, self.cfg.StunResetStamina) end
			setStamina(plr, self.cfg.StunResetStamina)
		end
	end
	applyStun(self.p1)
	applyStun(self.p2)

	-- regen
	self:_give(self.p1, self:_regenAmount(self.p1))
	self:_give(self.p2, self:_regenAmount(self.p2))

	-- dazed tick (applies difficulty next turn)
	local function tickDazed(plr: Player)
		local t = self.dazedTurns[plr]
		if t and t > 0 then
			self.dazedTurns[plr] = t - 1
			return true
		end
		return false
	end
	local p1Dazed = tickDazed(self.p1)
	local p2Dazed = tickDazed(self.p2)

	local s1 = getStats(self.p1)
	local s2 = getStats(self.p2)

	local losing1 = clamp(self.progress, 0, 1)
	local losing2 = clamp(-self.progress, 0, 1)

	local zoneScale1, speedScale1, ratio1 = computeAdvantageScale(s1, s2)
	local zoneScale2, speedScale2, ratio2 = computeAdvantageScale(s2, s1)

	local diff1 = computeDifficultyScalar(self.cfg, self.turnIndex, losing1) * self:_fatigueMult(self.p1)
	local diff2 = computeDifficultyScalar(self.cfg, self.turnIndex, losing2) * self:_fatigueMult(self.p2)

	-- dazed makes harder
	local dazedPtr1 = p1Dazed and self.cfg.DazedPointerMult or 1
	local dazedPtr2 = p2Dazed and self.cfg.DazedPointerMult or 1
	local dazedZone1 = p1Dazed and self.cfg.DazedZoneMult or 1
	local dazedZone2 = p2Dazed and self.cfg.DazedZoneMult or 1

	self.targetCenter = Random.new():NextNumber(0.18, 0.82)

	local pointer1 = (self.cfg.BasePointerSpeed * speedScale1) * diff1 * dazedPtr1
	local pointer2 = (self.cfg.BasePointerSpeed * speedScale2) * diff2 * dazedPtr2

	local zOk1 = clamp(((self.cfg.BaseZoneOkay    * zoneScale1) / diff1) * dazedZone1, 0.08, 0.45)
	local zGd1 = clamp(((self.cfg.BaseZoneGood    * zoneScale1) / diff1) * dazedZone1, 0.05, 0.35)
	local zPf1 = clamp(((self.cfg.BaseZonePerfect * zoneScale1) / diff1) * dazedZone1, 0.04, 0.28)

	local zOk2 = clamp(((self.cfg.BaseZoneOkay    * zoneScale2) / diff2) * dazedZone2, 0.08, 0.45)
	local zGd2 = clamp(((self.cfg.BaseZoneGood    * zoneScale2) / diff2) * dazedZone2, 0.05, 0.35)
	local zPf2 = clamp(((self.cfg.BaseZonePerfect * zoneScale2) / diff2) * dazedZone2, 0.04, 0.28)

	local function barScaleFrom(ratio, diff, losingAmt)
		local statBoost = clamp(1 + (ratio - 1) * 0.18, 0.95, 1.14)
		local diffShrink = clamp(1 / diff, 0.78, 1.0)
		local losingBoost = 1 + (0.10 * losingAmt)
		return clamp(statBoost * diffShrink * losingBoost, self.cfg.MinBarScale, self.cfg.MaxBarScale)
	end

	local bar1 = barScaleFrom(ratio1, diff1, losing1)
	local bar2 = barScaleFrom(ratio2, diff2, losing2)

	self.turnStartTime = workspace:GetServerTimeNow()
	self.turnSettings[self.p1] = {pointerSpeed=pointer1, zoneOk=zOk1, zoneGood=zGd1, zonePerf=zPf1, barScale=bar1, difficulty=diff1}
	self.turnSettings[self.p2] = {pointerSpeed=pointer2, zoneOk=zOk2, zoneGood=zGd2, zonePerf=zPf2, barScale=bar2, difficulty=diff2}

	self:_pushTurnStart(self.p1, self.p2)
	self:_pushTurnStart(self.p2, self.p1)

	task.delay(self.cfg.TurnDuration + 0.05, function()
		if not self.matchActive or myToken ~= self.turnToken then return end
		if self.resolvedTurnIndex == self.turnIndex then return end
		if not self.p1 or not self.p2 then return end
		self:_forceMiss(self.p1)
		self:_forceMiss(self.p2)
		self:_resolveTurn()
	end)
end

function Controller:_startMatch()
	self.matchActive = true
	self.matchId += 1
	self.winsP1, self.winsP2 = 0, 0
	self.roundIndex = 1

	for _, plr in ipairs({self.p1, self.p2}) do
		if plr then
			local mx = tonumber(plr:GetAttribute("AW_StaminaMax")) or self.cfg.StunResetStamina
			setMaxStamina(plr, mx)
			local cur = tonumber(plr:GetAttribute("AW_Stamina")) or mx
			setStamina(plr, cur)

			if plr:GetAttribute("AW_Resolve") == nil then
				setResolve(plr, 0)
			end

			self.gripChoice[plr] = self.gripChoice[plr] or "Neutral"
			self.dazedTurns[plr] = 0
			self.perfectReady[plr] = false
			self.perfectTurns[plr] = 0
			self.fortifyHold[plr] = 0
			self.strainTurns[plr] = 0
		end
	end

	self:_startNewRound()

	self:_fire(self.p1, "MatchStart", {opponent=self.p2.Name, bestOf=self.cfg.BestOf})
	self:_fire(self.p2, "MatchStart", {opponent=self.p1.Name, bestOf=self.cfg.BestOf})

	self:_startTurn()
end

function Controller:_onSeatsChanged()
	local newP1 = self:_getPlayerFromSeat(self.seatP1)
	local newP2 = self:_getPlayerFromSeat(self.seatP2)

	-- cancel match if someone leaves/changes
	if self.matchActive and (newP1 ~= self.p1 or newP2 ~= self.p2 or not newP1 or not newP2) then
		self.p1, self.p2 = newP1, newP2
		self:_cancelMatch("A player left the chair.")
	end

	-- seat left notif
	if self.prevP1 and self.prevP1 ~= newP1 then self:_fire(self.prevP1, "SeatLeft", {}) end
	if self.prevP2 and self.prevP2 ~= newP2 then self:_fire(self.prevP2, "SeatLeft", {}) end

	self.prevP1, self.prevP2 = newP1, newP2
	self.p1, self.p2 = newP1, newP2

	-- seat status (UI even if solo)
	if newP1 then self:_fire(newP1, "SeatStatus", {role="P1", opponent=newP2 and newP2.Name or nil}) end
	if newP2 then self:_fire(newP2, "SeatStatus", {role="P2", opponent=newP1 and newP1.Name or nil}) end

	-- start match
	if newP1 and newP2 and not self.matchActive then
		self:_startMatch()
	end
end

-- =========================
-- PUBLIC: REMOTE HANDLER
-- =========================
function Controller:HandleClientEvent(player: Player, action: string, data: table)
	if not self.matchActive then return end
	if player ~= self.p1 and player ~= self.p2 then return end
	if typeof(action) ~= "string" then return end
	if typeof(data) ~= "table" then data = {} end
	if data.tableId ~= self.tableId then return end
	if self.stunnedThisTurn[player] then return end

	if action == "SetGrip" then
		if self.resolvedTurnIndex == self.turnIndex then return end
		if data.turn ~= self.turnIndex then return end
		if self.submitted[player] then return end

		local requested = tostring(data.grip or "Neutral")
		self:_setGrip(player, requested)

		local base = self.turnSettings[player]
		if base then
			local wanted = self:_getGrip(player)
			local afford, cost = self:_canAfford(player, wanted)
			local grip = afford and wanted or "Neutral"

			self:_fire(player, "GripApplied", {
				turn = self.turnIndex,
				grip = grip,
				gripWanted = wanted,
				gripCost = cost,
				gripAffordable = afford,
				pointerSpeed = base.pointerSpeed,
				stamina = {cur=getStamina(player), max=getMaxStamina(player, self.cfg.StunResetStamina)},
				resolve = {cur=getResolve(player), max=self.cfg.ResolveMax},
				status = {
					dazed = (self.dazedTurns[player] or 0) > 0,
					perfectReady = self.perfectReady[player] == true,
					strained = (self.strainTurns[player] or 0) > 0,
				},
				stunned = false,
			})
		end
		return
	end

	if action == "Submit" then
		if self.resolvedTurnIndex == self.turnIndex then return end
		if data.turn ~= self.turnIndex then return end
		if self.submitted[player] then return end

		self.usedGrip[player] = self:_getGrip(player)

		if data.timedOut == true then
			self.submitted[player] = {turn=self.turnIndex, clickTime=nil, forcedMiss=true}
		else
			local clickTime = data.clickTime
			if typeof(clickTime) ~= "number" then
				self.submitted[player] = {turn=self.turnIndex, clickTime=nil, forcedMiss=true}
			else
				if clickTime < self.turnStartTime or clickTime > (self.turnStartTime + self.cfg.TurnDuration + 0.10) then
					self.submitted[player] = {turn=self.turnIndex, clickTime=nil, forcedMiss=true}
				else
					self.submitted[player] = {turn=self.turnIndex, clickTime=clickTime, forcedMiss=false}
				end
			end
		end

		self:_resolveTurn()
		return
	end
end

return Controller
