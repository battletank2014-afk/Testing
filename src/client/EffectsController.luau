--[[
    EffectsController
    The "juice" layer: checkpoint chime, confetti burst, brief camera punch.
    Purely cosmetic and entirely client-side, so it can never affect gameplay
    truth or the server's progression state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Presentation = require(Shared.Presentation)
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local EffectsController = {}

local function chime()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
    sound.Volume = 0.5
    sound.Parent = player:WaitForChild("PlayerGui")
    sound:Play()
    Debris:AddItem(sound, 3)
end

local function confetti(at: Vector3, color: Color3)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    for _ = 1, 12 do
        local part = Instance.new("Part")
        part.Size = Vector3.new(0.4, 0.4, 0.4)
        part.Color = color
        part.Material = Enum.Material.Neon
        part.CanCollide = false
        part.Anchored = false
        part.CFrame = CFrame.new(at + Vector3.new(
            math.random(-4, 4),
            math.random(2, 6),
            math.random(-4, 4)
        ))
        part.Parent = workspace
        part.AssemblyLinearVelocity = Vector3.new(
            math.random(-12, 12),
            math.random(8, 20),
            math.random(-12, 12)
        )
        Debris:AddItem(part, 2)
    end
end

local function cameraPunch()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    local original = camera.CFrame
    local offset = original * CFrame.new(0, 0, -0.35)
    local down = TweenService:Create(camera, TweenInfo.new(0.08), { CFrame = offset })
    down:Play()
    down.Completed:Wait()
    TweenService:Create(camera, TweenInfo.new(0.15), { CFrame = original }):Play()
end

function EffectsController.init()
    Net.get("PlayEffect").OnClientEvent:Connect(function(payload)
        if payload.kind == "checkpoint" then
            chime()
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                confetti(root.Position, Presentation.CheckpointColor)
            end
            cameraPunch()
        end
    end)
end

return EffectsController
