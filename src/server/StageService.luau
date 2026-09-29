--[[
    StageService
    Owns player progression. Server-authoritative: the client asks, this module
    decides. Every accepted completion is validated against ordering, proximity
    and a cooldown before it is allowed to change state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StageDefinitions = require(Shared.StageDefinitions)

local DataService = require(script.Parent.DataService)
local CheckpointService = require(script.Parent.CheckpointService)

local StageService = {}

--[[ Fires with the Player whenever their progression state changes. ]]
StageService.onChanged = Instance.new("BindableEvent")

--[=[ types ]=]

export type RunState = {
    stage: number,
    startedAt: number?,
    deaths: number,
    lastCompleteAt: number,
    requestTimes: { number },
}

local runs: { [Player]: RunState } = {}

--[=[ helpers ]=]

local function newRun(): RunState
    return {
        stage = 1,
        startedAt = nil,
        deaths = 0,
        lastCompleteAt = 0,
        requestTimes = {},
    }
end

local function geometryFor(stageId: number): Model?
    local level = workspace:FindFirstChild("Level")
    if not level then
        return nil
    end
    return level:FindFirstChild(`Stage_{stageId}`) :: Model?
end

--[[ Where the player must be standing to claim a completion. ]]
local function endPadPosition(stageId: number): Vector3?
    local model = geometryFor(stageId)
    if not model then
        return nil
    end
    local pad = model:FindFirstChild("EndPad")
    if not pad or not pad:IsA("BasePart") then
        return nil
    end
    return pad.Position
end

local function characterRoot(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    return (root and root:IsA("BasePart")) and root or nil
end

--[[ Sliding one-minute window rate limit on completion requests. ]]
local function withinRateLimit(run: RunState, now: number): boolean
    local windowStart = now - 60
    local kept = {}
    for _, t in ipairs(run.requestTimes) do
        if t >= windowStart then
            table.insert(kept, t)
        end
    end
    run.requestTimes = kept
    if #kept >= Config.MaxRequestPerMinute then
        return false
    end
    table.insert(kept, now)
    return true
end

--[=[ progression ]=]

local function broadcast(run: RunState, player: Player)
    Net.get("StageChanged"):FireClient(player, {
        stage = run.stage,
        total = StageDefinitions.count(),
        startedAt = run.startedAt,
        deaths = run.deaths,
    })
end

--[[
    Advances a player by one stage. Called by the completion remote and by the
    skip product. Returns (ok, reason).
]]
function StageService.advance(player: Player, reason: string): (boolean, string?)
    local run = runs[player]
    if not run then
        return false, "no_run"
    end

    local stage = StageDefinitions.get(run.stage)
    if not stage then
        return false, "no_such_stage"
    end

    if run.stage == 1 and run.startedAt == nil then
        run.startedAt = os.clock()
    end

    run.stage += 1

    local profile = DataService.get(player)
    if profile then
        profile.furthestStage = math.max(profile.furthestStage, run.stage)
    end

    if run.stage > StageDefinitions.count() then
        StageService.finish(player, reason)
        return true, nil
    end

    broadcast(run, player)
    StageService.onChanged:Fire(player)
    Net.get("StageCompleted"):FireClient(player, {
        stage = run.stage - 1,
        world = stage.world,
        name = stage.name,
    })

    CheckpointService.teleportToStart(player, run.stage)
    DataService.saveNow(player)
    return true, nil
end

--[[ Called once the player clears the final stage. ]]
function StageService.finish(player: Player, reason: string)
    local run = runs[player]
    if not run or run.startedAt == nil then
        return
    end

    local elapsed = os.clock() - run.startedAt
    local profile = DataService.get(player)
    if profile then
        profile.wins += 1
        if profile.bestTimeSec == nil or elapsed < profile.bestTimeSec then
            profile.bestTimeSec = elapsed
        end
    end

    Net.get("RunFinished"):FireClient(player, {
        timeSec = elapsed,
        deaths = run.deaths,
        reason = reason,
    })

    StageService.onChanged:Fire(player)
    DataService.saveNow(player)
end

--[[ Client asked to complete its current stage. Returns (ok, reason). ]]
local function onRequestComplete(player: Player, claimedStage: number): (boolean, string?)
    local run = runs[player]
    if not run then
        return false, "no_run"
    end

    if typeof(claimedStage) ~= "number" then
        return false, "bad_payload"
    end

    local now = os.clock()
    if now - run.lastCompleteAt < Config.CompleteCooldown then
        return false, "cooldown"
    end

    if not withinRateLimit(run, now) then
        return false, "rate_limited"
    end

    -- The claim must match the stage the server believes the player is on.
    if claimedStage ~= run.stage then
        return false, "wrong_stage"
    end

    -- Proximity: the player has to actually be at this stage's end pad.
    local padPosition = endPadPosition(run.stage)
    if not padPosition then
        return false, "no_geometry"
    end

    local root = characterRoot(player)
    if not root then
        return false, "no_character"
    end

    if (root.Position - padPosition).Magnitude > Config.MaxCheckpointDistance then
        return false, "too_far"
    end

    run.lastCompleteAt = now
    return StageService.advance(player, "completed")
end

--[=[ lifecycle ]=]

function StageService.getRun(player: Player): RunState?
    return runs[player]
end

function StageService.onDeath(player: Player)
    local run = runs[player]
    if not run then
        return
    end
    run.deaths += 1
    local profile = DataService.get(player)
    if profile then
        profile.totalDeaths += 1
    end
    broadcast(run, player)
end

function StageService.init()
    -- Runs are created when the profile is actually in memory, not on
    -- PlayerAdded, so a slow DataStore read can't leave a run without a profile.
    DataService.loaded.Event:Connect(function(player: Player)
        local profile = DataService.get(player)
        local run = newRun()
        if profile then
            run.stage = profile.furthestStage
        end
        runs[player] = run
        broadcast(run, player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        runs[player] = nil
    end)

    Net.get("RequestComplete").OnServerInvoke = onRequestComplete
end

return StageService
