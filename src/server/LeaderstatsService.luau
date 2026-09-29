--[[
    LeaderstatsService
    Publishes Stage / Wins / Deaths to the default player list. Purely cosmetic
    mirror of DataService + StageService state; never a source of truth.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StageDefinitions = require(Shared.StageDefinitions)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)

local LeaderstatsService = {}

local function stat(container: Instance, name: string, value: number): IntValue
    local existing = container:FindFirstChild(name)
    if existing and existing:IsA("IntValue") then
        return existing
    end
    local created = Instance.new("IntValue")
    created.Name = name
    created.Value = value
    created.Parent = container
    return created
end

local function setStat(player: Player, name: string, value: number)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        return
    end
    local valueObject = leaderstats:FindFirstChild(name)
    if valueObject and valueObject:IsA("IntValue") then
        valueObject.Value = value
    end
end

--[[ Recomputes every leaderstat from authoritative state. ]]
function LeaderstatsService.refresh(player: Player)
    local run = StageService.getRun(player)
    local profile = DataService.get(player)
    if not run or not profile then
        return
    end

    setStat(player, "Stage", run.stage)
    setStat(player, "Wins", profile.wins)
    setStat(player, "Deaths", run.deaths)
end

function LeaderstatsService.init()
    DataService.loaded.Event:Connect(function(player: Player)
        local leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"

        stat(leaderstats, "Stage", 1)
        stat(leaderstats, "Wins", 0)
        stat(leaderstats, "Deaths", 0)

        leaderstats.Parent = player
        LeaderstatsService.refresh(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        -- nothing to tear down; the folder dies with the player
    end)

    -- Keep the display in sync whenever progression moves.
    StageService.onChanged.Event:Connect(function(player: Player)
        LeaderstatsService.refresh(player)
    end)
end

return LeaderstatsService
