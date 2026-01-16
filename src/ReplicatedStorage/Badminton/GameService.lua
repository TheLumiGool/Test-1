local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourtConfig = require(ReplicatedStorage.Badminton.CourtConfig)
local Shuttlecock = require(ReplicatedStorage.Badminton.Shuttlecock)
local PlayerController = require(ReplicatedStorage.Badminton.PlayerController)

local GameService = {}
GameService.__index = GameService
GameService.RemoteName = "BadmintonAction"

function GameService.new()
	local self = setmetatable({}, GameService)
	self.Controllers = {}
	self.Shuttlecock = nil
	self.Court = nil
	self.RemoteEvent = nil
	return self
end

function GameService:CreateCourt()
	local court = Instance.new("Part")
	court.Name = "BadmintonCourt"
	court.Size = Vector3.new(CourtConfig.Dimensions.Length, CourtConfig.Dimensions.BoundaryHeight, CourtConfig.Dimensions.Width)
	court.Anchored = true
	court.Position = Vector3.new(0, CourtConfig.Dimensions.BoundaryHeight / 2, 0)
	court.Material = Enum.Material.Wood
	court.Color = Color3.fromRGB(180, 140, 90)
	court.Parent = workspace

	local net = Instance.new("Part")
	net.Name = "Net"
	net.Size = Vector3.new(1, CourtConfig.Dimensions.NetHeight, CourtConfig.Dimensions.Width)
	net.Anchored = true
	net.Position = Vector3.new(0, CourtConfig.Dimensions.NetHeight / 2, 0)
	net.Material = Enum.Material.Fabric
	net.Color = Color3.fromRGB(235, 235, 235)
	net.Parent = workspace

	self.Court = court
end

function GameService:CreateShuttlecock()
	local part = Instance.new("Part")
	part.Name = "Shuttlecock"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.8, 0.8, 0.8)
	part.Anchored = true
	part.Position = Vector3.new(0, 8, 0)
	part.Color = Color3.fromRGB(245, 245, 245)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = workspace

	self.Shuttlecock = Shuttlecock.new(part)
end

function GameService:CreateRemotes()
	local remote = ReplicatedStorage:FindFirstChild(GameService.RemoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = GameService.RemoteName
		remote.Parent = ReplicatedStorage
	end

	self.RemoteEvent = remote
end

function GameService:OnPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		self.Controllers[player] = PlayerController.new(player, character)
		character:MoveTo(CourtConfig.SpawnPoints.Home)
	end)
end

function GameService:HandleAction(player, action)
	local controller = self.Controllers[player]
	if not controller or not self.Shuttlecock then
		return
	end

	if action == "Serve" then
		controller:Serve(self.Shuttlecock)
	elseif action == "Swing" then
		controller:Swing(self.Shuttlecock)
	end
end

function GameService:Start()
	self:CreateCourt()
	self:CreateShuttlecock()
	self:CreateRemotes()

	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	self.RemoteEvent.OnServerEvent:Connect(function(player, action)
		self:HandleAction(player, action)
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		if self.Shuttlecock then
			self.Shuttlecock:Step(deltaTime)
		end
	end)
end

return GameService
