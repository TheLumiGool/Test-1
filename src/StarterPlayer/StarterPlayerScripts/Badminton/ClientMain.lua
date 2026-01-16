local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remote = ReplicatedStorage:WaitForChild("BadmintonAction")
local player = Players.LocalPlayer

local function onAction(actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if actionName == "Serve" then
		remote:FireServer("Serve")
	elseif actionName == "Swing" then
		remote:FireServer("Swing")
	end

	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("Serve", onAction, false, Enum.KeyCode.E)
ContextActionService:BindAction("Swing", onAction, false, Enum.KeyCode.F)

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")	
end)
