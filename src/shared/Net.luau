--[[
    Net
    Single source of truth for remote names and lookup. Client and server both
    require this module, so the string names can never drift apart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- name -> { className = "RemoteEvent" | "RemoteFunction" }
local DEFINITIONS = {
    StageCompleted = "RemoteEvent",   -- server -> client: toast, advance HUD
    StageChanged = "RemoteEvent",     -- server -> client: authoritative stage set
    RunFinished = "RemoteEvent",      -- server -> client: final time
    RequestComplete = "RemoteFunction", -- client -> server: ask to advance
    SkipStage = "RemoteFunction",     -- client -> server: consume a skip
    PlayEffect = "RemoteEvent",       -- server -> client: checkpoint juice
}

local folder

local function getFolder(): Folder
    if RunService:IsServer() then
        local existing = ReplicatedStorage:FindFirstChild("Net")
        if existing then
            return existing :: Folder
        end
        local created = Instance.new("Folder")
        created.Name = "Net"
        created.Parent = ReplicatedStorage
        return created
    end
    return ReplicatedStorage:WaitForChild("Net") :: Folder
end

--[[ Creates the folder and every remote. Server-only; called once at startup. ]]
function Net.init()
    assert(RunService:IsServer(), "Net.init() must run on the server")
    folder = getFolder()
    for name, className in pairs(DEFINITIONS) do
        if not folder:FindFirstChild(name) then
            local remote = Instance.new(className)
            remote.Name = name
            remote.Parent = folder
        end
    end
end

--[[ Returns the remote by name, waiting for it on the client. ]]
function Net.get(name: string): Instance
    assert(DEFINITIONS[name], `unknown remote "{name}"`)
    if RunService:IsServer() then
        return folder:FindFirstChild(name) :: Instance
    end
    return (getFolder() :: Folder):WaitForChild(name)
end

return Net
