-- ReplicatedStorage/Shared/TalentDefinitions
-- FULL OVERWRITE (Anime Character Talents + still uses your NERF pipeline)
-- NOTE: Your tier "MYTHICAL" maps to this module's "Epic" rarity (no gameplay code changes required).

local TalentDefinitions = {}

TalentDefinitions.Rarities = {
	Common = { weight = 70 },
	Rare = { weight = 22 },
	Epic = { weight = 7 }, -- = Mythical
	Legendary = { weight = 1 },
	Secret = { weight = 0.05 },
}

-- =========================
-- HELPERS / NERF PIPELINE
-- =========================
local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local MOMENTUM_CAP = 1.20

local MomentumBaseline = {
	Common = 0.40,
	Rare = 0.62,
	Epic = 0.82,
	Legendary = 0.98,
	Secret = 1.20,
}

local SCORE_BASE_MULT = 0.88
local SCORE_ADD_MULT = 0.60
local PERFECT_BONUS_MULT = 0.55
local MOMENTUM_ADD_MULT = 0.55
local STAMINA_MAX_MULT = 0.92
local STAMINA_REGEN_MULT = 0.80
local STAMINA_RESTORE_MULT = 0.70
local WINDOW_TIGHTEN_MULT = 0.95

local function nerfStyle(rarity, style)
	style = style or {}

	if style.BaseScore then
		style.BaseScore = style.BaseScore * SCORE_BASE_MULT
	end
	if style.StaminaMax then
		style.StaminaMax = math.floor(style.StaminaMax * STAMINA_MAX_MULT + 0.5)
	end
	if style.StaminaRegen then
		style.StaminaRegen = style.StaminaRegen * STAMINA_REGEN_MULT
	end
	if style.WindowMult then
		style.WindowMult = style.WindowMult * WINDOW_TIGHTEN_MULT
	end

	style.MomentumGainMult = MomentumBaseline[rarity] or style.MomentumGainMult or 0.40
	style.MomentumGainMult = clamp(style.MomentumGainMult, 0.10, MOMENTUM_CAP)

	if style.SliderSpeedMult then
		style.SliderSpeedMult = clamp(style.SliderSpeedMult, 0.78, 1.22)
	end

	return style
end

local function nerfEffects(e)
	if not e then return e end

	if e.BaseScoreAdd then
		e.BaseScoreAdd = e.BaseScoreAdd * SCORE_ADD_MULT
	end

	if e.PerfectBonus then
		e.PerfectBonus = e.PerfectBonus * PERFECT_BONUS_MULT
	end
	if e.NextPerfectBonus then
		e.NextPerfectBonus = e.NextPerfectBonus * PERFECT_BONUS_MULT
	end
	if e.NextPerfectBonusAdd then
		e.NextPerfectBonusAdd = e.NextPerfectBonusAdd * PERFECT_BONUS_MULT
	end

	if e.MomentumAdd then
		e.MomentumAdd = math.floor(e.MomentumAdd * MOMENTUM_ADD_MULT + 0.5)
	end
	if e.NextPerfectMomentumAdd then
		e.NextPerfectMomentumAdd = math.floor(e.NextPerfectMomentumAdd * MOMENTUM_ADD_MULT + 0.5)
	end
	if e.PerfectMomentumAdd then
		e.PerfectMomentumAdd = math.floor(e.PerfectMomentumAdd * MOMENTUM_ADD_MULT + 0.5)
	end

	if e.MomentumGainMult then
		local softened = 1 + ((e.MomentumGainMult - 1) * 0.35)
		e.MomentumGainMult = clamp(softened, 0.70, 1.12)
	end

	if e.StaminaRestore then
		e.StaminaRestore = math.floor(e.StaminaRestore * STAMINA_RESTORE_MULT + 0.5)
	end

	if e.ClickCostMult then
		local t = (e.ClickCostMult - 1)
		e.ClickCostMult = clamp(1 + (t * 0.60), 0.70, 1.25)
	end

	if e.SliderSpeedMult then
		e.SliderSpeedMult = clamp(e.SliderSpeedMult, 0.45, 1.35)
	end

	if e.WindowMult then
		e.WindowMult = clamp(e.WindowMult, 0.85, 1.20)
	end

	if e.MomentumDecayMult then
		e.MomentumDecayMult = clamp(1 - ((1 - e.MomentumDecayMult) * 0.70), 0.35, 1.00)
	end

	if e.NoMomentumDecay == true then
		e.MomentumDecayMult = clamp(e.MomentumDecayMult or 0.35, 0.25, 0.55)
	end

	return e
end

local function nerfTalent(t)
	t.Style = nerfStyle(t.Rarity, t.Style)

	if t.Skills then
		for _, s in ipairs(t.Skills) do
			s.Effects = nerfEffects(s.Effects)

			if t.Rarity == "Epic" then
				s.Cooldown = math.floor((s.Cooldown or 0) * 1.08 + 0.5)
			elseif t.Rarity == "Legendary" then
				s.Cooldown = math.floor((s.Cooldown or 0) * 1.12 + 0.5)
			elseif t.Rarity == "Secret" then
				s.Cooldown = math.floor((s.Cooldown or 0) * 1.15 + 0.5)
			end
		end
	end

	return t
end

-- =========================
-- TALENTS (Characters)
-- Common(5), Rare(5), Epic/Mythical(8), Legendary(8), Secret(5)
-- =========================
TalentDefinitions.List = {

	-- =========================
	-- 🟢 COMMON (5)
	-- =========================

	nerfTalent({
		Id = "Tanjiro_WaterCadence",
		Name = "Tanjiro — Water Cadence",
		Rarity = "Common",
		Desc = "Calm breathing and clean cuts. Consistency beats panic.",
		Style = {
			BaseScore = 0.29,
			StaminaMax = 190,
			WindowMult = 1.05,
			SliderSpeedMult = 0.98,
			StaminaRegen = 0.40,
		},
		Skills = {
			{
				Id = "TotalConcentration",
				Name = "Total Concentration",
				Desc = "For 8s: timing windows widen and momentum decays slower.",
				Cooldown = 38,
				Duration = 8,
				Effects = { WindowMult = 1.18, MomentumDecayMult = 0.72 },
			},
			{
				Id = "HinokamiFeint",
				Name = "Hinokami Feint",
				Desc = "Next PERFECT: bonus score and a small momentum spike (costs stamina).",
				Cooldown = 46,
				Duration = 14,
				Effects = { StaminaCost = 10, NextPerfectBonus = 0.95, NextPerfectMomentumAdd = 14 },
			},
		},
	}),

	nerfTalent({
		Id = "Yuji_DivergentDrive",
		Name = "Yuji — Divergent Drive",
		Rarity = "Common",
		Desc = "Raw athletic power. Land clean hits and keep pushing.",
		Style = {
			BaseScore = 0.30,
			StaminaMax = 175,
			WindowMult = 1.02,
			SliderSpeedMult = 1.04,
			StaminaRegen = 0.34,
		},
		Skills = {
			{
				Id = "CursedReinforcement",
				Name = "Cursed Reinforcement",
				Desc = "For 9s: clicks cost less stamina and momentum decays slower.",
				Cooldown = 42,
				Duration = 9,
				Effects = { ClickCostMult = 0.75, MomentumDecayMult = 0.75 },
			},
			{
				Id = "BlackFlashAttempt",
				Name = "Black Flash Attempt",
				Desc = "Next PERFECT: large bonus score (high risk, longer cooldown).",
				Cooldown = 58,
				Duration = 16,
				Effects = { NextPerfectBonus = 1.20 },
			},
		},
	}),

	nerfTalent({
		Id = "Gon_HunterInstinct",
		Name = "Gon — Hunter Instinct",
		Rarity = "Common",
		Desc = "Simple, stubborn, and scary consistent. Recovers fast.",
		Style = {
			BaseScore = 0.28,
			StaminaMax = 205,
			WindowMult = 1.04,
			SliderSpeedMult = 0.96,
			StaminaRegen = 0.50,
		},
		Skills = {
			{
				Id = "WildFocus",
				Name = "Wild Focus",
				Desc = "For 10s: base score rises slightly and windows widen.",
				Cooldown = 44,
				Duration = 10,
				Effects = { BaseScoreAdd = 0.08, WindowMult = 1.12 },
			},
			{
				Id = "StubbornGrit",
				Name = "Stubborn Grit",
				Desc = "Restore stamina instantly.",
				Cooldown = 55,
				Duration = 0,
				Effects = { StaminaRestore = 70 },
			},
		},
	}),

	nerfTalent({
		Id = "RockLee_TaijutsuForm",
		Name = "Rock Lee — Taijutsu Form",
		Rarity = "Common",
		Desc = "No tricks. Just speed, precision, and pressure.",
		Style = {
			BaseScore = 0.27,
			StaminaMax = 170,
			WindowMult = 0.98,
			SliderSpeedMult = 1.10,
			StaminaRegen = 0.32,
		},
		Skills = {
			{
				Id = "LeafHurricane",
				Name = "Leaf Hurricane",
				Desc = "Consume stamina: instant momentum spike.",
				Cooldown = 40,
				Duration = 0,
				Effects = { StaminaCost = 11, MomentumAdd = 26 },
			},
			{
				Id = "WeightedTraining",
				Name = "Weighted Training",
				Desc = "For 8s: clicks cost less stamina, but slider speeds up.",
				Cooldown = 38,
				Duration = 8,
				Effects = { ClickCostMult = 0.72, SliderSpeedMult = 1.18 },
			},
		},
	}),

	nerfTalent({
		Id = "Mikasa_AckermanFocus",
		Name = "Mikasa — Ackerman Focus",
		Rarity = "Common",
		Desc = "Cold precision. Keeps control when the tempo spikes.",
		Style = {
			BaseScore = 0.28,
			StaminaMax = 210,
			WindowMult = 1.03,
			SliderSpeedMult = 1.00,
			StaminaRegen = 0.46,
		},
		Skills = {
			{
				Id = "ODM_Burst",
				Name = "ODM Burst",
				Desc = "For 6s: slider speeds up but timing windows widen slightly.",
				Cooldown = 36,
				Duration = 6,
				Effects = { SliderSpeedMult = 1.20, WindowMult = 1.10 },
			},
			{
				Id = "ColdResolve",
				Name = "Cold Resolve",
				Desc = "For 10s: momentum decays slower and clicks cost a bit less stamina.",
				Cooldown = 46,
				Duration = 10,
				Effects = { MomentumDecayMult = 0.70, ClickCostMult = 0.80 },
			},
		},
	}),

	-- =========================
	-- 🔵 RARE (5)
	-- =========================

	nerfTalent({
		Id = "Asta_BlackFormEarly",
		Name = "Asta — Anti-Magic Rush",
		Rarity = "Rare",
		Desc = "Brute force and refusal. Short explosive surges.",
		Style = {
			BaseScore = 0.33,
			StaminaMax = 175,
			WindowMult = 0.98,
			SliderSpeedMult = 1.08,
			StaminaRegen = 0.38,
		},
		Skills = {
			{
				Id = "DemonRush",
				Name = "Demon Rush",
				Desc = "For 7s: momentum gain increases and slider speeds up.",
				Cooldown = 46,
				Duration = 7,
				Effects = { MomentumGainMult = 1.35, SliderSpeedMult = 1.25 },
			},
			{
				Id = "AntiMagicGrip",
				Name = "Anti-Magic Grip",
				Desc = "For 9s: momentum decays slower and windows tighten slightly (skill check).",
				Cooldown = 52,
				Duration = 9,
				Effects = { MomentumDecayMult = 0.60, WindowMult = 0.92 },
			},
		},
	}),

	nerfTalent({
		Id = "Killua_AssassinTempo",
		Name = "Killua — Assassin Tempo",
		Rarity = "Rare",
		Desc = "Fast reads, fast hands. Wins on clean timing.",
		Style = {
			BaseScore = 0.32,
			StaminaMax = 185,
			WindowMult = 1.00,
			SliderSpeedMult = 1.10,
			StaminaRegen = 0.52,
		},
		Skills = {
			{
				Id = "Whirlstep",
				Name = "Whirlstep",
				Desc = "For 8s: slider speeds up and clicks cost less stamina.",
				Cooldown = 48,
				Duration = 8,
				Effects = { SliderSpeedMult = 1.25, ClickCostMult = 0.72 },
			},
			{
				Id = "AssassinCalm",
				Name = "Assassin Calm",
				Desc = "For 10s: windows widen and momentum decays slower.",
				Cooldown = 52,
				Duration = 10,
				Effects = { WindowMult = 1.15, MomentumDecayMult = 0.68 },
			},
		},
	}),

	nerfTalent({
		Id = "Inosuke_BeastPressure",
		Name = "Inosuke — Beast Pressure",
		Rarity = "Rare",
		Desc = "Wild angles and relentless pressure. Momentum spikes on PERFECT.",
		Style = {
			BaseScore = 0.34,
			StaminaMax = 165,
			WindowMult = 0.97,
			SliderSpeedMult = 1.06,
			StaminaRegen = 0.34,
		},
		Skills = {
			{
				Id = "BeastCharge",
				Name = "Beast Charge",
				Desc = "Consume stamina: instant momentum spike.",
				Cooldown = 44,
				Duration = 0,
				Effects = { StaminaCost = 12, MomentumAdd = 34 },
			},
			{
				Id = "BoarInstinct",
				Name = "Boar Instinct",
				Desc = "For 10s: each PERFECT adds momentum (limited stacks).",
				Cooldown = 58,
				Duration = 10,
				Effects = { PerfectMomentumAdd = 10, PerfectMomentumMaxStacks = 4 },
			},
		},
	}),

	nerfTalent({
		Id = "Bakugo_ExplosionRhythm",
		Name = "Bakugo — Explosion Rhythm",
		Rarity = "Rare",
		Desc = "High tempo, high aggression. Turns PERFECTs into fireworks.",
		Style = {
			BaseScore = 0.33,
			StaminaMax = 170,
			WindowMult = 0.98,
			SliderSpeedMult = 1.12,
			StaminaRegen = 0.40,
		},
		Skills = {
			{
				Id = "AP_Shot",
				Name = "AP Shot",
				Desc = "Next 2 PERFECT hits: bonus score.",
				Cooldown = 52,
				Duration = 14,
				Effects = { PerfectBonus = 0.70, PerfectBonusHits = 2 },
			},
			{
				Id = "BlastStep",
				Name = "Blast Step",
				Desc = "For 7s: slider speeds up and momentum gain increases.",
				Cooldown = 50,
				Duration = 7,
				Effects = { SliderSpeedMult = 1.28, MomentumGainMult = 1.30 },
			},
		},
	}),

	nerfTalent({
		Id = "Levi_FullGear",
		Name = "Levi — Full Gear",
		Rarity = "Rare",
		Desc = "Surgical control. Punishes mistakes with clean conversions.",
		Style = {
			BaseScore = 0.31,
			StaminaMax = 210,
			WindowMult = 1.02,
			SliderSpeedMult = 1.02,
			StaminaRegen = 0.58,
		},
		Skills = {
			{
				Id = "SpinCut",
				Name = "Spin Cut",
				Desc = "Next PERFECT: bonus score and momentum spike.",
				Cooldown = 46,
				Duration = 14,
				Effects = { NextPerfectBonus = 1.10, NextPerfectMomentumAdd = 22 },
			},
			{
				Id = "CaptainDiscipline",
				Name = "Captain Discipline",
				Desc = "For 12s: clicks cost less stamina and momentum decays slower.",
				Cooldown = 58,
				Duration = 12,
				Effects = { ClickCostMult = 0.70, MomentumDecayMult = 0.68 },
			},
		},
	}),

	-- =========================
	-- 🟣 MYTHICAL = EPIC (8)
	-- =========================

	nerfTalent({
		Id = "Zoro_ThreeSwordDrive",
		Name = "Zoro — Three-Sword Drive",
		Rarity = "Epic",
		Desc = "Heavy base pressure with sharp payoffs on PERFECT chains.",
		Style = {
			BaseScore = 0.36,
			StaminaMax = 190,
			WindowMult = 0.97,
			SliderSpeedMult = 1.06,
			StaminaRegen = 0.62,
		},
		Skills = {
			{
				Id = "OniGiri",
				Name = "Oni Giri",
				Desc = "Consume stamina: heavy momentum spike.",
				Cooldown = 58,
				Duration = 0,
				Effects = { StaminaCost = 14, MomentumAdd = 44 },
			},
			{
				Id = "AsuraHint",
				Name = "Asura Hint",
				Desc = "Next 3 PERFECT hits: bonus score.",
				Cooldown = 72,
				Duration = 16,
				Effects = { PerfectBonus = 0.90, PerfectBonusHits = 3 },
			},
		},
	}),

	nerfTalent({
		Id = "Ichigo_BankaiTYBW",
		Name = "Ichigo — Bankai Burst",
		Rarity = "Epic",
		Desc = "Explosive tempo. Short windows, massive swing potential.",
		Style = {
			BaseScore = 0.35,
			StaminaMax = 175,
			WindowMult = 0.95,
			SliderSpeedMult = 1.10,
			StaminaRegen = 0.72,
		},
		Skills = {
			{
				Id = "GetsugaTempo",
				Name = "Getsuga Tempo",
				Desc = "For 7s: momentum gain increases and slider speeds up.",
				Cooldown = 64,
				Duration = 7,
				Effects = { MomentumGainMult = 1.40, SliderSpeedMult = 1.25 },
			},
			{
				Id = "HollowEdge",
				Name = "Hollow Edge",
				Desc = "Next PERFECT: big bonus score.",
				Cooldown = 60,
				Duration = 16,
				Effects = { NextPerfectBonus = 1.60 },
			},
			{
				Id = "ShunpoReset",
				Name = "Shunpo Reset",
				Desc = "Restore stamina and widen windows briefly.",
				Cooldown = 78,
				Duration = 6,
				Effects = { StaminaRestore = 80, WindowMult = 1.18 },
			},
		},
	}),

	nerfTalent({
		Id = "Tengen_SoundBreath",
		Name = "Tengen — Sound Breathing",
		Rarity = "Epic",
		Desc = "Turns the bar into a rhythm. Builds momentum on sustained accuracy.",
		Style = {
			BaseScore = 0.34,
			StaminaMax = 210,
			WindowMult = 1.00,
			SliderSpeedMult = 1.02,
			StaminaRegen = 0.78,
		},
		Skills = {
			{
				Id = "ScoreTheBeat",
				Name = "Score The Beat",
				Desc = "For 12s: each PERFECT adds momentum (limited stacks).",
				Cooldown = 72,
				Duration = 12,
				Effects = { PerfectMomentumAdd = 10, PerfectMomentumMaxStacks = 6 },
			},
			{
				Id = "FlashyFinish",
				Name = "Flashy Finish",
				Desc = "Next 2 PERFECT hits: bonus score and momentum.",
				Cooldown = 80,
				Duration = 14,
				Effects = { PerfectBonus = 1.00, PerfectBonusHits = 2, PerfectMomentumAdd = 12 },
			},
		},
	}),

	nerfTalent({
		Id = "Kakashi_SharinganRead",
		Name = "Kakashi — Sharingan Read",
		Rarity = "Epic",
		Desc = "Predicts tempo. Safer clicks and cleaner conversions.",
		Style = {
			BaseScore = 0.33,
			StaminaMax = 220,
			WindowMult = 1.03,
			SliderSpeedMult = 0.98,
			StaminaRegen = 0.82,
		},
		Skills = {
			{
				Id = "CopyTheTiming",
				Name = "Copy The Timing",
				Desc = "For 10s: windows widen and clicks cost less stamina.",
				Cooldown = 70,
				Duration = 10,
				Effects = { WindowMult = 1.20, ClickCostMult = 0.72 },
			},
			{
				Id = "ChidoriSnap",
				Name = "Chidori Snap",
				Desc = "Next PERFECT: bonus score and momentum spike (costs stamina).",
				Cooldown = 66,
				Duration = 16,
				Effects = { StaminaCost = 14, NextPerfectBonus = 1.40, NextPerfectMomentumAdd = 26 },
			},
		},
	}),

	nerfTalent({
		Id = "Yuta_RikaBond",
		Name = "Yuta — Rika Bond",
		Rarity = "Epic",
		Desc = "Versatile. Can stabilize or explode depending on the moment.",
		Style = {
			BaseScore = 0.35,
			StaminaMax = 200,
			WindowMult = 1.00,
			SliderSpeedMult = 1.02,
			StaminaRegen = 0.80,
		},
		Skills = {
			{
				Id = "RikaGuard",
				Name = "Rika Guard",
				Desc = "For 12s: momentum decays much slower.",
				Cooldown = 78,
				Duration = 12,
				Effects = { MomentumDecayMult = 0.55 },
			},
			{
				Id = "CopyBurst",
				Name = "Copy Burst",
				Desc = "For 8s: momentum gain increases and windows widen slightly.",
				Cooldown = 72,
				Duration = 8,
				Effects = { MomentumGainMult = 1.35, WindowMult = 1.12 },
			},
			{
				Id = "CursedRefuel",
				Name = "Cursed Refuel",
				Desc = "Restore stamina instantly.",
				Cooldown = 85,
				Duration = 0,
				Effects = { StaminaRestore = 95 },
			},
		},
	}),

	nerfTalent({
		Id = "Eren_FoundingPressure",
		Name = "Eren — Founding Pressure",
		Rarity = "Epic",
		Desc = "Slow inevitability. Locks momentum and grinds you down.",
		Style = {
			BaseScore = 0.34,
			StaminaMax = 235,
			WindowMult = 0.98,
			SliderSpeedMult = 0.96,
			StaminaRegen = 0.76,
		},
		Skills = {
			{
				Id = "PathsLock",
				Name = "Paths Lock",
				Desc = "For 14s: momentum decays extremely slow and windows slightly tighten.",
				Cooldown = 84,
				Duration = 14,
				Effects = { MomentumDecayMult = 0.50, WindowMult = 0.92 },
			},
			{
				Id = "TitanSurge",
				Name = "Titan Surge",
				Desc = "Consume stamina: heavy momentum spike.",
				Cooldown = 78,
				Duration = 0,
				Effects = { StaminaCost = 16, MomentumAdd = 48 },
			},
		},
	}),

	nerfTalent({
		Id = "Luffy_GearFourth",
		Name = "Luffy — Gear Fourth",
		Rarity = "Epic",
		Desc = "Bouncy tempo swings. Big push windows with stamina management.",
		Style = {
			BaseScore = 0.36,
			StaminaMax = 185,
			WindowMult = 0.98,
			SliderSpeedMult = 1.08,
			StaminaRegen = 0.70,
		},
		Skills = {
			{
				Id = "BoundmanBurst",
				Name = "Boundman Burst",
				Desc = "For 8s: momentum gain increases and slider speeds up.",
				Cooldown = 78,
				Duration = 8,
				Effects = { MomentumGainMult = 1.45, SliderSpeedMult = 1.22 },
			},
			{
				Id = "KongGun",
				Name = "Kong Gun",
				Desc = "Next PERFECT: big bonus score and momentum spike (costs stamina).",
				Cooldown = 72,
				Duration = 16,
				Effects = { StaminaCost = 15, NextPerfectBonus = 1.65, NextPerfectMomentumAdd = 30 },
			},
			{
				Id = "BounceBack",
				Name = "Bounce Back",
				Desc = "Restore stamina and reduce click cost briefly.",
				Cooldown = 88,
				Duration = 8,
				Effects = { StaminaRestore = 85, ClickCostMult = 0.75 },
			},
		},
	}),

	nerfTalent({
		Id = "Todoroki_HotColdControl",
		Name = "Todoroki — Hot/Cold Control",
		Rarity = "Epic",
		Desc = "Controls tempo. Slows the bar or widens windows on demand.",
		Style = {
			BaseScore = 0.33,
			StaminaMax = 225,
			WindowMult = 1.02,
			SliderSpeedMult = 0.98,
			StaminaRegen = 0.84,
		},
		Skills = {
			{
				Id = "IceField",
				Name = "Ice Field",
				Desc = "For 9s: slider slows and windows widen slightly.",
				Cooldown = 70,
				Duration = 9,
				Effects = { SliderSpeedMult = 0.75, WindowMult = 1.15 },
			},
			{
				Id = "FlashFire",
				Name = "Flashfire",
				Desc = "For 7s: base score rises and momentum gain increases.",
				Cooldown = 78,
				Duration = 7,
				Effects = { BaseScoreAdd = 0.14, MomentumGainMult = 1.35 },
			},
		},
	}),

	-- =========================
	-- 🟠 LEGENDARY (8)
	-- =========================

	nerfTalent({
		Id = "Naruto_SixPaths",
		Name = "Naruto — Six Paths",
		Rarity = "Legendary",
		Desc = "Balanced god-tier. Stabilizes momentum and cashes out on PERFECT chains.",
		Style = {
			BaseScore = 0.37,
			StaminaMax = 240,
			WindowMult = 1.03,
			SliderSpeedMult = 1.02,
			StaminaRegen = 1.05,
		},
		Skills = {
			{
				Id = "SageCalm",
				Name = "Sage Calm",
				Desc = "For 12s: momentum decays much slower and clicks cost less stamina.",
				Cooldown = 78,
				Duration = 12,
				Effects = { MomentumDecayMult = 0.45, ClickCostMult = 0.70 },
			},
			{
				Id = "TruthseekerPunish",
				Name = "Truthseeker Punish",
				Desc = "Next 3 PERFECT hits: bonus score and momentum.",
				Cooldown = 92,
				Duration = 16,
				Effects = { PerfectBonus = 1.10, PerfectBonusHits = 3, PerfectMomentumAdd = 14 },
			},
			{
				Id = "KuramaRefuel",
				Name = "Kurama Refuel",
				Desc = "Restore stamina instantly.",
				Cooldown = 100,
				Duration = 0,
				Effects = { StaminaRestore = 115 },
			},
		},
	}),

	nerfTalent({
		Id = "Sasuke_Rinnegan",
		Name = "Sasuke — Rinnegan Shift",
		Rarity = "Legendary",
		Desc = "Sharp conversions. Turns one opening into a match swing.",
		Style = {
			BaseScore = 0.38,
			StaminaMax = 220,
			WindowMult = 0.99,
			SliderSpeedMult = 1.06,
			StaminaRegen = 0.98,
		},
		Skills = {
			{
				Id = "Amenotejikara",
				Name = "Amenotejikara",
				Desc = "For 8s: windows widen and the slider speeds up.",
				Cooldown = 86,
				Duration = 8,
				Effects = { WindowMult = 1.18, SliderSpeedMult = 1.18 },
			},
			{
				Id = "ChidoriOneshot",
				Name = "Chidori One-Shot",
				Desc = "Next PERFECT: huge bonus score and momentum spike (costs stamina).",
				Cooldown = 94,
				Duration = 18,
				Effects = { StaminaCost = 18, NextPerfectBonus = 2.10, NextPerfectMomentumAdd = 40 },
			},
			{
				Id = "SusanooGuard",
				Name = "Susanoo Guard",
				Desc = "For 12s: momentum decays extremely slow.",
				Cooldown = 98,
				Duration = 12,
				Effects = { MomentumDecayMult = 0.42 },
			},
		},
	}),

	nerfTalent({
		Id = "Goku_SSB",
		Name = "Goku — Blue Discipline",
		Rarity = "Legendary",
		Desc = "Perfect fundamentals. Thrives at high speed and high pressure.",
		Style = {
			BaseScore = 0.37,
			StaminaMax = 235,
			WindowMult = 1.02,
			SliderSpeedMult = 1.08,
			StaminaRegen = 1.02,
		},
		Skills = {
			{
				Id = "KiControl",
				Name = "Ki Control",
				Desc = "For 10s: windows widen and clicks cost less stamina.",
				Cooldown = 84,
				Duration = 10,
				Effects = { WindowMult = 1.18, ClickCostMult = 0.70 },
			},
			{
				Id = "InstantTransmission",
				Name = "Instant Transmission",
				Desc = "Next PERFECT: bonus score and momentum spike.",
				Cooldown = 90,
				Duration = 16,
				Effects = { NextPerfectBonus = 1.85, NextPerfectMomentumAdd = 30 },
			},
			{
				Id = "BlueBurst",
				Name = "Blue Burst",
				Desc = "For 7s: momentum gain increases and slider speeds up.",
				Cooldown = 92,
				Duration = 7,
				Effects = { MomentumGainMult = 1.45, SliderSpeedMult = 1.20 },
			},
		},
	}),

	nerfTalent({
		Id = "Saitama_OnePunch",
		Name = "Saitama — Casual Strength",
		Rarity = "Legendary",
		Desc = "Unfair base pressure. Wins by out-muscling the tempo.",
		Style = {
			BaseScore = 0.40,
			StaminaMax = 260,
			WindowMult = 1.00,
			SliderSpeedMult = 0.98,
			StaminaRegen = 1.10,
		},
		Skills = {
			{
				Id = "SeriousSeries",
				Name = "Serious Series",
				Desc = "Next PERFECT: massive bonus score and momentum spike.",
				Cooldown = 110,
				Duration = 18,
				Effects = { NextPerfectBonus = 2.30, NextPerfectMomentumAdd = 42 },
			},
			{
				Id = "NoEffort",
				Name = "No Effort",
				Desc = "For 12s: clicks cost less stamina and momentum decays slower.",
				Cooldown = 96,
				Duration = 12,
				Effects = { ClickCostMult = 0.70, MomentumDecayMult = 0.50 },
			},
		},
	}),

	nerfTalent({
		Id = "Kaido_EmperorCrush",
		Name = "Kaido — Emperor Crush",
		Rarity = "Legendary",
		Desc = "Overwhelming force. Converts stamina into huge momentum swings.",
		Style = {
			BaseScore = 0.39,
			StaminaMax = 250,
			WindowMult = 0.99,
			SliderSpeedMult = 1.02,
			StaminaRegen = 1.00,
		},
		Skills = {
			{
				Id = "ThunderBagua",
				Name = "Thunder Bagua",
				Desc = "Consume stamina: heavy momentum spike.",
				Cooldown = 90,
				Duration = 0,
				Effects = { StaminaCost = 18, MomentumAdd = 60 },
			},
			{
				Id = "DragonEndurance",
				Name = "Dragon Endurance",
				Desc = "For 14s: momentum decays extremely slow and restore stamina.",
				Cooldown = 110,
				Duration = 14,
				Effects = { MomentumDecayMult = 0.42, StaminaRestore = 85 },
			},
			{
				Id = "EmperorFinish",
				Name = "Emperor Finish",
				Desc = "Next 2 PERFECT hits: bonus score.",
				Cooldown = 102,
				Duration = 16,
				Effects = { PerfectBonus = 1.25, PerfectBonusHits = 2 },
			},
		},
	}),

	nerfTalent({
		Id = "Madara_TenTails",
		Name = "Madara — Ten-Tails",
		Rarity = "Legendary",
		Desc = "Oppressive control. Locks the bar and punishes missed tempo.",
		Style = {
			BaseScore = 0.38,
			StaminaMax = 255,
			WindowMult = 1.02,
			SliderSpeedMult = 1.00,
			StaminaRegen = 1.06,
		},
		Skills = {
			{
				Id = "LimboPressure",
				Name = "Limbo Pressure",
				Desc = "For 12s: momentum decay becomes extremely slow.",
				Cooldown = 98,
				Duration = 12,
				Effects = { MomentumDecayMult = 0.42 },
			},
			{
				Id = "MeteorDrop",
				Name = "Meteor Drop",
				Desc = "Next PERFECT: huge bonus score.",
				Cooldown = 104,
				Duration = 18,
				Effects = { NextPerfectBonus = 2.20 },
			},
			{
				Id = "Regeneration",
				Name = "Regeneration",
				Desc = "Restore stamina instantly.",
				Cooldown = 110,
				Duration = 0,
				Effects = { StaminaRestore = 120 },
			},
		},
	}),

	nerfTalent({
		Id = "Aizen_Hogyoku",
		Name = "Aizen — Hogyoku",
		Rarity = "Legendary",
		Desc = "Illusion-level control. Makes the bar feel predictable… for you.",
		Style = {
			BaseScore = 0.37,
			StaminaMax = 245,
			WindowMult = 1.04,
			SliderSpeedMult = 1.02,
			StaminaRegen = 1.02,
		},
		Skills = {
			{
				Id = "KyokaSuigetsu",
				Name = "Kyoka Suigetsu",
				Desc = "For 10s: windows widen a lot and momentum decays slower.",
				Cooldown = 100,
				Duration = 10,
				Effects = { WindowMult = 1.20, MomentumDecayMult = 0.45 },
			},
			{
				Id = "PerfectManipulation",
				Name = "Perfect Manipulation",
				Desc = "Next 3 PERFECT hits: bonus score and momentum.",
				Cooldown = 112,
				Duration = 18,
				Effects = { PerfectBonus = 1.15, PerfectBonusHits = 3, PerfectMomentumAdd = 16 },
			},
		},
	}),

	nerfTalent({
		Id = "Gojo_InfinityActive",
		Name = "Gojo — Infinity Active",
		Rarity = "Legendary",
		Desc = "Defense turned into dominance. Stabilizes and then deletes with one window.",
		Style = {
			BaseScore = 0.36,
			StaminaMax = 260,
			WindowMult = 1.02,
			SliderSpeedMult = 1.00,
			StaminaRegen = 1.08,
		},
		Skills = {
			{
				Id = "InfinityGuard",
				Name = "Infinity Guard",
				Desc = "For 14s: momentum decays extremely slow and clicks cost less stamina.",
				Cooldown = 104,
				Duration = 14,
				Effects = { MomentumDecayMult = 0.42, ClickCostMult = 0.70 },
			},
			{
				Id = "HollowPurpleSetup",
				Name = "Hollow Purple (Setup)",
				Desc = "Next PERFECT: massive bonus score and momentum spike (costs stamina).",
				Cooldown = 120,
				Duration = 20,
				Effects = { StaminaCost = 20, NextPerfectBonus = 2.40, NextPerfectMomentumAdd = 45 },
			},
			{
				Id = "SixEyesFocus",
				Name = "Six Eyes Focus",
				Desc = "For 10s: windows widen and slider speeds up slightly.",
				Cooldown = 98,
				Duration = 10,
				Effects = { WindowMult = 1.18, SliderSpeedMult = 1.10 },
			},
		},
	}),

	-- =========================
	-- 🔴 SECRET (5)
	-- =========================

	nerfTalent({
		Id = "Zeno_Erase",
		Name = "Zeno — Erase",
		Rarity = "Secret",
		Desc = "A rule outside the rules. One clean moment can end the round.",
		Style = {
			BaseScore = 0.40,
			StaminaMax = 300,
			WindowMult = 1.02,
			SliderSpeedMult = 1.00,
			StaminaRegen = 1.45,
		},
		Skills = {
			{
				Id = "QuietRoom",
				Name = "Quiet Room",
				Desc = "For 12s: slider slows heavily and windows widen.",
				Cooldown = 170,
				Duration = 12,
				Effects = { SliderSpeedMult = 0.55, WindowMult = 1.20 },
			},
			{
				Id = "EraseCommand",
				Name = "Erase Command",
				Desc = "Next PERFECT: huge bonus score + momentum (costs stamina).",
				Cooldown = 200,
				Duration = 20,
				Effects = { StaminaCost = 22, NextPerfectBonus = 3.00, NextPerfectMomentumAdd = 55 },
			},
			{
				Id = "NoDecay",
				Name = "No Decay",
				Desc = "For 20s: momentum decay is disabled (soft-capped by nerf).",
				Cooldown = 190,
				Duration = 20,
				Effects = { NoMomentumDecay = true, MomentumDecayMult = 0.35 },
			},
		},
	}),

	nerfTalent({
		Id = "Rimuru_TrueDemonLord",
		Name = "Rimuru — Predator King",
		Rarity = "Secret",
		Desc = "Absorbs tempo and converts it into unstoppable control.",
		Style = {
			BaseScore = 0.38,
			StaminaMax = 320,
			WindowMult = 1.05,
			SliderSpeedMult = 0.98,
			StaminaRegen = 1.50,
		},
		Skills = {
			{
				Id = "Predation",
				Name = "Predation",
				Desc = "Restore stamina and gain a momentum spike.",
				Cooldown = 170,
				Duration = 0,
				Effects = { StaminaRestore = 140, MomentumAdd = 50 },
			},
			{
				Id = "GreatSage",
				Name = "Great Sage",
				Desc = "For 18s: windows widen and clicks cost less stamina.",
				Cooldown = 185,
				Duration = 18,
				Effects = { WindowMult = 1.20, ClickCostMult = 0.70 },
			},
			{
				Id = "TempestAuthority",
				Name = "Tempest Authority",
				Desc = "Next 3 PERFECT hits: bonus score and momentum.",
				Cooldown = 210,
				Duration = 24,
				Effects = { PerfectBonus = 1.40, PerfectBonusHits = 3, PerfectMomentumAdd = 18 },
			},
		},
	}),

	nerfTalent({
		Id = "Anos_DemonKing",
		Name = "Anos — Demon King",
		Rarity = "Secret",
		Desc = "Overwrites the match. Mistakes feel… optional.",
		Style = {
			BaseScore = 0.39,
			StaminaMax = 310,
			WindowMult = 1.03,
			SliderSpeedMult = 1.02,
			StaminaRegen = 1.40,
		},
		Skills = {
			{
				Id = "WorldOrder",
				Name = "World Order",
				Desc = "For 25s: mistakes don't reduce momentum.",
				Cooldown = 200,
				Duration = 25,
				Effects = { IgnoreMissPenalty = true },
			},
			{
				Id = "AuthoritySnap",
				Name = "Authority Snap",
				Desc = "For 10s: slider becomes almost still (control).",
				Cooldown = 175,
				Duration = 10,
				Effects = { FreezeSlider = true, SliderSpeedMult = 0.50 },
			},
			{
				Id = "DemonKingJudgement",
				Name = "Demon King Judgement",
				Desc = "Next PERFECT: huge bonus score + momentum.",
				Cooldown = 220,
				Duration = 20,
				Effects = { NextPerfectBonus = 3.10, NextPerfectMomentumAdd = 60 },
			},
		},
	}),

	nerfTalent({
		Id = "SungJinWoo_End",
		Name = "Sung Jin-Woo — Shadow Monarch",
		Rarity = "Secret",
		Desc = "Snowballs hard off clean chains. The longer it goes, the worse it gets.",
		Style = {
			BaseScore = 0.37,
			StaminaMax = 305,
			WindowMult = 1.04,
			SliderSpeedMult = 1.06,
			StaminaRegen = 1.45,
		},
		Skills = {
			{
				Id = "ShadowExtraction",
				Name = "Shadow Extraction",
				Desc = "Restore stamina and slow momentum decay briefly.",
				Cooldown = 175,
				Duration = 10,
				Effects = { StaminaRestore = 135, MomentumDecayMult = 0.45 },
			},
			{
				Id = "RulersAuthority",
				Name = "Ruler's Authority",
				Desc = "Consume stamina: heavy momentum spike.",
				Cooldown = 185,
				Duration = 0,
				Effects = { StaminaCost = 22, MomentumAdd = 62 },
			},
			{
				Id = "ArmyOfShadows",
				Name = "Army of Shadows",
				Desc = "For 18s: each PERFECT adds momentum (limited stacks).",
				Cooldown = 205,
				Duration = 18,
				Effects = { PerfectMomentumAdd = 12, PerfectMomentumMaxStacks = 10 },
			},
		},
	}),

	nerfTalent({
		Id = "Giorno_GER",
		Name = "Giorno — Requiem Return",
		Rarity = "Secret",
		Desc = "Resets the fight state. Stabilizes you, then cashes out one perfect moment.",
		Style = {
			BaseScore = 0.36,
			StaminaMax = 295,
			WindowMult = 1.06,
			SliderSpeedMult = 0.98,
			StaminaRegen = 1.35,
		},
		Skills = {
			{
				Id = "ReturnToZero",
				Name = "Return to Zero",
				Desc = "For 20s: momentum decay is disabled (soft-capped by nerf).",
				Cooldown = 190,
				Duration = 20,
				Effects = { NoMomentumDecay = true, MomentumDecayMult = 0.35 },
			},
			{
				Id = "RequiemStability",
				Name = "Requiem Stability",
				Desc = "For 15s: windows widen and clicks cost less stamina.",
				Cooldown = 175,
				Duration = 15,
				Effects = { WindowMult = 1.20, ClickCostMult = 0.70 },
			},
			{
				Id = "FinalResetHit",
				Name = "Final Reset Hit",
				Desc = "Next PERFECT: huge bonus score + momentum.",
				Cooldown = 215,
				Duration = 22,
				Effects = { NextPerfectBonus = 2.80, NextPerfectMomentumAdd = 55 },
			},
		},
	}),
}

-- =========================
-- INDEX / API
-- =========================
local byId = {}
for _, t in ipairs(TalentDefinitions.List) do
	byId[t.Id] = t
end

function TalentDefinitions.Get(id)
	return byId[id]
end

local function pickByRarity(rarity)
	local pool = {}
	for _, t in ipairs(TalentDefinitions.List) do
		if t.Rarity == rarity then
			table.insert(pool, t)
		end
	end
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

function TalentDefinitions.Roll()
	local total = 0
	for _, r in pairs(TalentDefinitions.Rarities) do
		total += r.weight
	end

	local roll = math.random() * total
	local running = 0
	local pickedRarity = "Common"

	for name, r in pairs(TalentDefinitions.Rarities) do
		running += r.weight
		if roll <= running then
			pickedRarity = name
			break
		end
	end

	return pickByRarity(pickedRarity) or pickByRarity("Common")
end

return TalentDefinitions
