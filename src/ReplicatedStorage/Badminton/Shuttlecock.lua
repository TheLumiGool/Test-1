local CourtConfig = require(script.Parent.CourtConfig)

local Shuttlecock = {}
Shuttlecock.__index = Shuttlecock

function Shuttlecock.new(part)
	local self = setmetatable({}, Shuttlecock)
	self.Part = part
	self.Velocity = Vector3.zero
	self.InPlay = false
	self.LastHitBy = nil
	self.LastTouchTime = 0
	return self
end

function Shuttlecock:Reset(position)
	self.Part.Position = position
	self.Velocity = Vector3.zero
	self.InPlay = false
	self.LastHitBy = nil
	self.LastTouchTime = 0
end

function Shuttlecock:Serve(direction)
	self.InPlay = true
	self.Velocity = direction.Unit * CourtConfig.Serve.ForwardSpeed
		+ Vector3.new(0, CourtConfig.Serve.LiftSpeed, 0)
end

function Shuttlecock:ApplyImpulse(impulse, hitter)
	self.InPlay = true
	self.Velocity = self.Velocity + impulse
	self.Velocity = self.Velocity.Magnitude > CourtConfig.Shuttlecock.MaxSpeed
		and self.Velocity.Unit * CourtConfig.Shuttlecock.MaxSpeed
		or self.Velocity
	self.LastHitBy = hitter
	self.LastTouchTime = os.clock()
end

function Shuttlecock:Step(deltaTime)
	if not self.InPlay then
		return
	end

	self.Velocity += CourtConfig.Shuttlecock.Gravity * deltaTime
	self.Velocity *= CourtConfig.Shuttlecock.Drag

	local newPosition = self.Part.Position + self.Velocity * deltaTime
	if newPosition.Y <= CourtConfig.Dimensions.BoundaryHeight then
		newPosition = Vector3.new(newPosition.X, CourtConfig.Dimensions.BoundaryHeight, newPosition.Z)
		self.Velocity = Vector3.new(
			self.Velocity.X,
			-self.Velocity.Y * CourtConfig.Shuttlecock.BounceDamping,
			self.Velocity.Z
		)
		self.InPlay = false
	end

	self.Part.Position = newPosition
end

return Shuttlecock
