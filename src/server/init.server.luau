--[[
    Server entry point.
    Boot order matters: Net first (creates the remotes), then DataService so
    profiles exist, then the services that consume them. StageService and
    CheckpointService are required by LeaderstatsService and MonetizationService,
    so they init before those.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StageDefinitions = require(Shared.StageDefinitions)

local DataService = require(script.DataService)
local StageService = require(script.StageService)
local CheckpointService = require(script.CheckpointService)
local LeaderstatsService = require(script.LeaderstatsService)
local LevelBuilder = require(script.LevelBuilder)
local MonetizationService = require(script.MonetizationService)

StageDefinitions.init(Config)

local ok, errors = StageDefinitions.validate()
if not ok then
    for _, message in ipairs(errors) do
        warn(`[StageDefinitions] {message}`)
    end
    error(`stage catalogue failed validation ({#errors} problems)`)
end

Net.init()
if Config.GeneratePlaceholderLevels then
    LevelBuilder.build()
end
CheckpointService.init()
DataService.init()
StageService.init()
LeaderstatsService.init()
MonetizationService.init()

print(`[SkywardSprint] server ready — {StageDefinitions.count()} stages`)
