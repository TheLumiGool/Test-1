-- ServerScriptService/ArmWrestleBot
-- Picks click times to hit near center with miss chance based on difficulty.

local Bot = {}

local SPEEDUP_K = 0.010

local function pingpong01(x)
	local m = x % 2
	if m <= 1 then return m else return 2 - m end
end

local function pointerAtTime(baseSpeed, t)
	local phase = baseSpeed * (t + 0.5 * SPEEDUP_K * (t*t))
	return pingpong01(phase)
end

local DIFF = {
	Rookie = { aim=0.10, miss=0.35, interval={0.33,0.50} },
	Skilled = { aim=0.06, miss=0.20, interval={0.28,0.42} },
	Elite = { aim=0.035, miss=0.10, interval={0.22,0.36} },
}

-- returns next click serverTime (absolute), given startTime/baseSpeed/center and serverNow
function Bot.nextClickTime(difficulty, serverNow, startTime, baseSpeed, center)
	local d = DIFF[difficulty] or DIFF.Rookie

	-- when should bot attempt another click
	local minI, maxI = d.interval[1], d.interval[2]
	local attemptAt = serverNow + (minI + math.random()*(maxI-minI))

	-- miss roll
	if math.random() < d.miss then
		return attemptAt -- "random click time" (will often miss)
	end

	-- aim near center with noise
	local target = center + (math.random() - 0.5) * 2 * d.aim
	target = math.clamp(target, 0.02, 0.98)

	-- brute search next ~2 seconds for closest pointer
	local bestT, bestErr = attemptAt, math.huge
	local t0 = math.max(0, attemptAt - startTime)
	for i=0, 200 do
		local t = t0 + i*0.01
		local p = pointerAtTime(baseSpeed, t)
		local err = math.abs(p - target)
		if err < bestErr then
			bestErr = err
			bestT = startTime + t
		end
	end

	return bestT
end

return Bot
