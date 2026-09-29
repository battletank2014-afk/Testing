--[[
    CheckpointService
    Watches stage geometry and drives respawns.

    Two responsibilities:
      1. Resolve where a player should respawn for a given stage (its StartPad,
         or the last checkpoint they touched inside that stage).
      2. Register checkpoint parts as they stream in, so touching one moves the
         player's respawn point forward.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StageDefinitions = require(Shared.StageDefinitions)

local CheckpointService = {}

local CHECKPOINT_TAG = "ObbyCheckpoint"

--[=[ types ]=]

export type Checkpoint = {
    stage: number,
    index: number,
    cframe: CFrame,
}

--[=[ state ]=]

-- player -> { stage -> { Checkpoint } } keyed by checkpoint index
local touched: { [Player]: { [number]: { [number]: Checkpoint } } } = {}

--[=[ helpers ]=]

local function levelFolder(): Folder?
    return workspace:FindFirstChild("Level") :: Folder?
end

local function stageModel(stageId: number): Model?
    local level = levelFolder()
    if not level then
        return nil
    end
    return level:FindFirstChild(`Stage_{stageId}`) :: Model?
end

local function partCFrame(parent: Instance?, name: string): CFrame?
    if not parent then
        return nil
    end
    local part = parent:FindFirstChild(name)
    if not part or not part:IsA("BasePart") then
        return nil
    end
    return part.CFrame
end

local function characterRoot(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    return (root and root:IsA("BasePart")) and root or nil
end

--[[ Parses `Stage_12` -> 12. Returns nil for anything else. ]]
local function stageIdFromName(name: string): number?
    local digits = name:match("^Stage_(%d+)$")
    if not digits then
        return nil
    end
    return tonumber(digits)
end

--[=[ respawn resolution ]=]

--[[
    Where should this player reappear for `stageId`? Prefers the furthest
    checkpoint they have touched in that stage, then the stage StartPad, then
    the world spawn.
]]
function CheckpointService.getRespawnCFrame(player: Player, stageId: number): CFrame
    local perStage = touched[player]
    local checkpoints = perStage and perStage[stageId]
    if checkpoints then
        local best: Checkpoint? = nil
        for _, checkpoint in pairs(checkpoints) do
            if best == nil or checkpoint.index > best.index then
                best = checkpoint
            end
        end
        if best then
            return best.cframe
        end
    end

    local model = stageModel(stageId)
    local startPad = partCFrame(model, "StartPad")
    if startPad then
        return startPad
    end

    local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
    if spawn then
        return spawn.CFrame
    end
    return CFrame.new(0, 10, 0)
end

--[[ Teleports the player onto a stage's start pad. ]]
function CheckpointService.teleportToStart(player: Player, stageId: number)
    local model = stageModel(stageId)
    local startPad = partCFrame(model, "StartPad")
    if not startPad then
        return
    end
    local root = characterRoot(player)
    if not root then
        return
    end
    root.CFrame = startPad + Vector3.new(0, 4, 0)
end

--[[ Sends the player back to their checkpoint for their current stage. ]]
function CheckpointService.respawn(player: Player, stageId: number)
    local root = characterRoot(player)
    if not root then
        return
    end
    root.CFrame = CheckpointService.getRespawnCFrame(player, stageId) + Vector3.new(0, 4, 0)
end

--[=[ checkpoint registration ]=]

local function onCheckpointTouched(checkpointPart: BasePart, player: Player)
    local stageId = checkpointPart:GetAttribute("StageId") or stageIdFromName(checkpointPart.Parent and checkpointPart.Parent.Name or "")
    local index = checkpointPart:GetAttribute("CheckpointIndex")
    if typeof(stageId) ~= "number" or typeof(index) ~= "number" then
        return
    end

    touched[player] = touched[player] or {}
    local perStage = touched[player][stageId] or {}
    touched[player][stageId] = perStage

    -- Only ever move the respawn point forward.
    local existing = perStage[index]
    if existing then
        return
    end

    perStage[index] = {
        stage = stageId,
        index = index,
        cframe = checkpointPart.CFrame,
    }

    Net.get("PlayEffect"):FireClient(player, {
        kind = "checkpoint",
        stage = stageId,
        index = index,
    })
end

local function registerCheckpoint(instance: Instance)
    if not instance:IsA("BasePart") then
        return
    end
    instance.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        if not character then
            return
        end
        local player = Players:GetPlayerFromCharacter(character)
        if player then
            onCheckpointTouched(instance, player)
        end
    end)
end

function CheckpointService.init()
    for _, instance in ipairs(CollectionService:GetTagged(CHECKPOINT_TAG)) do
        registerCheckpoint(instance)
    end
    CollectionService:GetInstanceAddedSignal(CHECKPOINT_TAG):Connect(registerCheckpoint)

    Players.PlayerRemoving:Connect(function(player)
        touched[player] = nil
    end)
end

return CheckpointService
