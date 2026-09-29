--[[
    Client entry point.
    Detects a completed stage locally (standing on an EndPad) and asks the server
    to confirm. The local check exists only to avoid spamming the remote every
    frame — the server re-validates everything independently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local HudController = require(script.HudController)
local EffectsController = require(script.EffectsController)

local player = Players.LocalPlayer

local currentStage = 1
local claimed = false

local function endPadPosition(stageId: number): Vector3?
    local level = workspace:FindFirstChild("Level")
    if not level then
        return nil
    end
    local model = level:FindFirstChild(`Stage_{stageId}`)
    if not model then
        return nil
    end
    local pad = model:FindFirstChild("EndPad")
    if not pad or not pad:IsA("BasePart") then
        return nil
    end
    return pad.Position
end

local function rootPosition(): Vector3?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        return nil
    end
    return root.Position
end

local function watchEndPad()
    RunService.Heartbeat:Connect(function()
        if claimed then
            return
        end

        local padPosition = endPadPosition(currentStage)
        local position = rootPosition()
        if not padPosition or not position then
            return
        end

        if (position - padPosition).Magnitude <= 6 then
            claimed = true
            local ok, reason = Net.get("RequestComplete"):InvokeServer(currentStage)
            if not ok and reason ~= "cooldown" then
                claimed = false
            end
        end
    end)
end

HudController.init()
EffectsController.init()

Net.get("StageChanged").OnClientEvent:Connect(function(payload)
    currentStage = payload.stage
    claimed = false
end)

watchEndPad()
