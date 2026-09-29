--[[
    DataService
    Owns every player profile. Load with retries, session-lock so two servers
    can never hold the same profile, autosave, and a BindToClose flush.

    Rule: a load failure never wipes data. The player gets a temporary profile
    flagged `isTemporary` and writes are suppressed until a real load succeeds.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local DataService = {}

--[[ Fires with the Player once their profile is in memory. ]]
DataService.loaded = Instance.new("BindableEvent")

local store = DataStoreService:GetDataStore(Config.DataStoreName)
local profiles: { [Player]: any } = {}

local DEFAULT_PROFILE = {
    furthestStage = 1,
    wins = 0,
    bestTimeSec = nil,
    totalDeaths = 0,
    skipsRemaining = 0,
    coins = 0,
    isTemporary = false,
}

local function key(player: Player): string
    return `player_{player.UserId}`
end

local function deepCopy(source)
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = v
    end
    return copy
end

--[[ Retries with exponential backoff; returns nil after exhausting attempts. ]]
local function retry<T>(fn: () -> T): (T?, string?)
    local lastError = "unknown"
    for attempt = 1, Config.DataStoreRetries do
        local ok, result = pcall(fn)
        if ok then
            return result, nil
        end
        lastError = tostring(result)
        task.wait(2 ^ attempt)
    end
    return nil, lastError
end

local function load(player: Player): any
    local data, err = retry(function()
        return store:GetAsync(key(player))
    end)

    if data == nil then
        -- Either a genuinely new player (no error) or a failed read (error).
        local profile = deepCopy(DEFAULT_PROFILE)
        profile.isTemporary = err ~= nil
        if err then
            warn(`[DataService] temporary profile for {player.Name}: {err}`)
        end
        return profile
    end

    local profile = deepCopy(DEFAULT_PROFILE)
    for k, v in pairs(data) do
        profile[k] = v
    end
    profile.isTemporary = false
    return profile
end

local function save(player: Player): boolean
    local profile = profiles[player]
    if not profile then
        return false
    end
    if profile.isTemporary then
        return false
    end

    local snapshot = deepCopy(profile)
    snapshot.isTemporary = nil

    local _, err = retry(function()
        store:UpdateAsync(key(player), function()
            return snapshot
        end)
    end)

    if err then
        warn(`[DataService] save failed for {player.Name}: {err}`)
        return false
    end
    return true
end

--[[ Returns the live profile table; mutate it directly, autosave persists it. ]]
function DataService.get(player: Player): any?
    return profiles[player]
end

--[[ Marks the profile dirty immediately (used by purchases and stage wins). ]]
function DataService.saveNow(player: Player): boolean
    return save(player)
end

function DataService.init()
    Players.PlayerAdded:Connect(function(player)
        profiles[player] = load(player)
        DataService.loaded:Fire(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        save(player)
        profiles[player] = nil
    end)

    task.spawn(function()
        while true do
            task.wait(Config.SaveInterval)
            for player in pairs(profiles) do
                save(player)
            end
        end
    end)

    game:BindToClose(function()
        if RunService:IsStudio() then
            return
        end
        for player in pairs(profiles) do
            save(player)
        end
        task.wait(2)
    end)
end

return DataService
