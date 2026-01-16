local CourtConfig = require(script.Parent.CourtConfig)

local Racket = {}
Racket.__index = Racket

function Racket.new(owner)
	local self = setmetatable({}, Racket)
	self.Owner = owner
	self.IsSwinging = false
	self.SwingStart = 0
	self.LastSwingTime = 0
	return self
end

function Racket:CanSwing()
	return not self.IsSwinging
end

function Racket:StartSwing()
	if not self:CanSwing() then
		return false
	end

	self.IsSwinging = true
	self.SwingStart = os.clock()
	self.LastSwingTime = self.SwingStart
	return true
end

function Racket:IsInHitWindow()
	if not self.IsSwinging then
		return false
	end

	local elapsed = os.clock() - self.SwingStart
	return elapsed >= CourtConfig.Swing.WindupTime
		and elapsed <= CourtConfig.Swing.WindupTime + CourtConfig.Swing.HitWindow
end

function Racket:FinishSwing()
	self.IsSwinging = false
end

return Racket
