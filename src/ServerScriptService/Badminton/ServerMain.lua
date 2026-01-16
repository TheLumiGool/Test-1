local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameService = require(ReplicatedStorage.Badminton.GameService)

local service = GameService.new()
service:Start()
