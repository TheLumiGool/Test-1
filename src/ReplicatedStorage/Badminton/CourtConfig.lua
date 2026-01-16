local CourtConfig = {}

CourtConfig.Dimensions = {
	Length = 44,
	Width = 20,
	NetHeight = 5,
	BoundaryHeight = 0.2,
}

CourtConfig.SpawnPoints = {
	Home = Vector3.new(-16, 3, 0),
	Away = Vector3.new(16, 3, 0),
}

CourtConfig.Serve = {
	MinHeight = 5,
	MaxHeight = 14,
	ForwardSpeed = 64,
	LiftSpeed = 32,
}

CourtConfig.Swing = {
	WindupTime = 0.15,
	RecoveryTime = 0.2,
	HitWindow = 0.2,
}

CourtConfig.Shuttlecock = {
	Gravity = Vector3.new(0, -30, 0),
	Drag = 0.98,
	BounceDamping = 0.35,
	MaxSpeed = 120,
}

CourtConfig.Audio = {
	Swing = "rbxassetid://9118820206",
	Hit = "rbxassetid://9118821105",
	Whistle = "rbxassetid://9118821568",
}

return CourtConfig
