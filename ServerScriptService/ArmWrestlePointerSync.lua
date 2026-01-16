-- ServerScriptService/ArmWrestlePointerSync (ModuleScript)
-- Server-authoritative pointer streaming + drift checks

local PointerSync = {}

PointerSync.SPEEDUP_K = 0.010 -- MUST match client + match logic
PointerSync.FPS = 30          -- pointer updates per second to clients

local sessions = {} -- [tableId] = { running=true, players={}, baseSpeed=1, startTime=0, lastPointer=0.5, remote=nil }

local function clamp(x,a,b) return math.max(a, math.min(b, x)) end

local function pingpong01(x)
	local m = x % 2
	if m <= 1 then return m else return 2 - m end
end

function PointerSync.PointerAtTime(baseSpeed, tSinceStart)
	-- phase = base*(t + 0.5*k*t^2)
	local k = PointerSync.SPEEDUP_K
	local phase = baseSpeed * (tSinceStart + 0.5 * k * (tSinceStart * tSinceStart))
	return pingpong01(phase)
end

function PointerSync.Stop(tableId)
	local s = sessions[tableId]
	if s then
		s.running = false
		sessions[tableId] = nil
	end
end

function PointerSync.Start(tableId: string, players: {any}, baseSpeed: number, startTime: number, remoteEvent: RemoteEvent)
	PointerSync.Stop(tableId)

	local s = {
		running = true,
		players = players or {},
		baseSpeed = tonumber(baseSpeed) or 1.0,
		startTime = tonumber(startTime) or workspace:GetServerTimeNow(),
		lastPointer = 0.5,
		remote = remoteEvent,
	}
	sessions[tableId] = s

	task.spawn(function()
		local dt = 1 / PointerSync.FPS
		while s.running do
			local now = workspace:GetServerTimeNow()
			local t = math.max(0, now - s.startTime)
			local p = PointerSync.PointerAtTime(s.baseSpeed, t)
			s.lastPointer = p

			for _, plr in ipairs(s.players) do
				if plr and plr.Parent then
					remoteEvent:FireClient(plr, "Pointer", {
						tableId = tableId,
						pointer = p,
						serverNow = now,
					})
				end
			end

			task.wait(dt)
		end
	end)
end

function PointerSync.SampleNow(tableId: string, baseSpeed: number, startTime: number)
	local now = workspace:GetServerTimeNow()
	local t = math.max(0, now - (tonumber(startTime) or now))
	local p = PointerSync.PointerAtTime(tonumber(baseSpeed) or 1.0, t)

	local s = sessions[tableId]
	if s then s.lastPointer = p end

	return p, now
end

-- Basic exploit/desync signal:
-- if clientT is far from serverNow, they're time-warping / lag spoofing.
function PointerSync.ClientTimeDriftSeconds(serverNow: number, clientT: number?)
	if typeof(clientT) ~= "number" then return 0 end
	return math.abs(clientT - serverNow)
end

return PointerSync
