local CourtConfig = require(script.Parent.CourtConfig)
local Racket = require(script.Parent.Racket)

local PlayerController = {}
PlayerController.__index = PlayerController

function PlayerController.new(player, character)
	local self = setmetatable({}, PlayerController)
	self.Player = player
	self.Character = character
	self.Racket = Racket.new(player)
	self.LastServeTime = 0
	return self
end

function PlayerController:GetFacingDirection()
	local root = self.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return Vector3.new(1, 0, 0)
	end
	return root.CFrame.LookVector
end

function PlayerController:CanServe()
	return os.clock() - self.LastServeTime > 1
end

function PlayerController:Serve(shuttlecock)
	if not self:CanServe() then
		return
	end

	self.LastServeTime = os.clock()
	local direction = self:GetFacingDirection()
	shuttlecock:Serve(direction)
end

function PlayerController:Swing(shuttlecock)
	if not self.Racket:StartSwing() then
		return
	end

	local direction = self:GetFacingDirection()
	local impulse = direction.Unit * CourtConfig.Serve.ForwardSpeed
		+ Vector3.new(0, CourtConfig.Serve.LiftSpeed * 0.8, 0)
	shuttlecock:ApplyImpulse(impulse, self.Player)
end

return PlayerController
