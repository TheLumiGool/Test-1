-- ServerScriptService/ArmWrestleBotSeater
-- Drop-in: spawns/seats a bot into TrainingTable SeatP2.
-- Bot is recognized by ArmWrestleService via Attribute ArmWrestleAI=true.

local ServerStorage = game:GetService("ServerStorage")

local tablesFolder = workspace:WaitForChild("ArmWrestleTables")
local trainingTable = tablesFolder:WaitForChild("TrainingTable")

local function findSeat(model, seatName)
	local s = model:FindFirstChild(seatName)
	if s and (s:IsA("Seat") or s:IsA("VehicleSeat")) then return s end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == seatName and (d:IsA("Seat") or d:IsA("VehicleSeat")) then
			return d
		end
	end
	return nil
end

local seatP2 = findSeat(trainingTable, "SeatP2")
assert(seatP2, "TrainingTable missing SeatP2")

local function ensureBotTemplate()
	local existing = ServerStorage:FindFirstChild("ArmWrestleBotRig")
	if existing then return existing end

	-- Simple humanoid model (enough for seating)
	local bot = Instance.new("Model")
	bot.Name = "ArmWrestleBotRig"
	bot:SetAttribute("ArmWrestleAI", true)
	bot:SetAttribute("AIDifficulty", "Skilled") -- Rookie / Skilled / Elite

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

	print("[ArmWrestleBotSeater] Created ServerStorage/ArmWrestleBotRig ✅")
	return bot
end

local botTemplate = ensureBotTemplate()

-- Remove old seated bot instance
local old = trainingTable:FindFirstChild("TrainingBot")
if old then old:Destroy() end

-- Spawn bot into table model
local bot = botTemplate:Clone()
bot.Name = "TrainingBot"
bot.Parent = trainingTable
bot:PivotTo(seatP2.CFrame * CFrame.new(0, 0, -1.2))

local hum = bot:FindFirstChildOfClass("Humanoid")
assert(hum, "Bot rig missing Humanoid")

task.wait(0.15)
seatP2:Sit(hum)

print("[ArmWrestleBotSeater] Bot seated in TrainingTable SeatP2 ✅")
