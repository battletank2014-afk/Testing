--[[
    StageDefinitions
    The stage catalogue. Deliberately pure data + pure functions: it touches no
    Roblox instance APIs and takes its config by injection, so it can be
    unit-tested outside Studio (Lune) as well as used in-game.

    Geometry lives in Workspace.Level as a Model named `Stage_<id>`. This module
    only describes progression metadata; StageService resolves the geometry.

    Call `StageDefinitions.init(Config)` once at startup before reading Stages.
]]

export type Stage = {
    id: number,
    world: string,
    name: string,
    difficulty: number,      -- 1..5
    mechanics: { string },
    checkpointCount: number,
    geometryName: string,    -- Model name to look for in Workspace.Level
    isBreather: boolean,
}

type World = { name: string, firstStage: number, lastStage: number }
type ConfigShape = { TotalStages: number, Worlds: { World } }

local WORLD_MECHANICS: { [string]: { primary: string, secondary: string } } = {
    Grasslands = { primary = "jump", secondary = "truss" },
    NeonCaverns = { primary = "moving_platform", secondary = "conveyor" },
    FrozenPeaks = { primary = "disappearing_platform", secondary = "ice" },
    LavaCore = { primary = "pendulum", secondary = "kill_brick" },
}

local StageDefinitions = {}

StageDefinitions.Stages = {} :: { Stage }
StageDefinitions.ById = {} :: { [number]: Stage }
StageDefinitions._config = nil :: ConfigShape?

--[[ Checkpoints scale with difficulty so hard stages never punish a long re-run. ]]
local function checkpointsFor(difficulty: number): number
    if difficulty <= 2 then
        return 1
    elseif difficulty == 3 then
        return 2
    elseif difficulty == 4 then
        return 3
    end
    return 4
end

--[[
    Difficulty ramp for one world.

    Raw ramp is 1,1,1,1,2,2,2,2,3,3,3,3,4,4,4 across the 15 local stages. Each
    world shifts that up by its index, and every 5th stage is a breather that
    drops one point. The result never rises by more than +1 between consecutive
    stages, which is the design rule the tests enforce.
]]
local function difficultyFor(worldIndex: number, localIndex: number): number
    local raw = 1 + math.floor((localIndex - 1) / 4)
    local shifted = raw + (worldIndex - 1)
    if localIndex % 5 == 0 then
        shifted -= 1
    end
    return math.clamp(shifted, 1, 5)
end

local function mechanicsFor(world: string, localIndex: number): { string }
    local set = WORLD_MECHANICS[world]
    if localIndex <= 5 then
        return { set.primary }
    elseif localIndex <= 10 then
        return { set.secondary }
    end
    return { set.primary, set.secondary }
end

--[[ Builds the full catalogue from config. Pure: same input, same output. ]]
function StageDefinitions.build(config: ConfigShape): { Stage }
    local stages: { Stage } = {}
    local id = 0

    for worldIndex, world in ipairs(config.Worlds) do
        for localIndex = 1, 15 do
            id += 1
            local difficulty = difficultyFor(worldIndex, localIndex)
            table.insert(stages, {
                id = id,
                world = world.name,
                name = `{world.name} {localIndex}`,
                difficulty = difficulty,
                mechanics = mechanicsFor(world.name, localIndex),
                checkpointCount = checkpointsFor(difficulty),
                geometryName = `Stage_{id}`,
                isBreather = localIndex % 5 == 0,
            })
        end
    end

    return stages
end

--[[ Populates Stages/ById. Idempotent — safe to call from several entry points. ]]
function StageDefinitions.init(config: ConfigShape)
    StageDefinitions._config = config
    StageDefinitions.Stages = StageDefinitions.build(config)

    local map: { [number]: Stage } = {}
    for _, stage in ipairs(StageDefinitions.Stages) do
        map[stage.id] = stage
    end
    StageDefinitions.ById = map
end

function StageDefinitions.get(id: number): Stage?
    return StageDefinitions.ById[id]
end

function StageDefinitions.count(): number
    return #StageDefinitions.Stages
end

--[[
    Validates the catalogue against the design rules. Returns ok plus every
    violation found, so tests can assert on specifics rather than a bare boolean.
]]
function StageDefinitions.validate(): (boolean, { string })
    local config = StageDefinitions._config
    local stages = StageDefinitions.Stages
    local errors: { string } = {}

    if not config then
        return false, { "init() was never called" }
    end

    if #stages ~= config.TotalStages then
        table.insert(errors, `expected {config.TotalStages} stages, built {#stages}`)
    end

    for index, stage in ipairs(stages) do
        if stage.id ~= index then
            table.insert(errors, `stage at position {index} has id {stage.id}`)
        end
        if stage.difficulty < 1 or stage.difficulty > 5 then
            table.insert(errors, `stage {stage.id} difficulty {stage.difficulty} out of range`)
        end
        if stage.checkpointCount < 1 then
            table.insert(errors, `stage {stage.id} has no checkpoints`)
        end
        if #stage.mechanics == 0 then
            table.insert(errors, `stage {stage.id} has no mechanics`)
        end
        if stage.geometryName ~= `Stage_{stage.id}` then
            table.insert(errors, `stage {stage.id} geometry name mismatch`)
        end

        local previous = stages[index - 1]
        if previous and stage.difficulty - previous.difficulty > 1 then
            table.insert(
                errors,
                `difficulty jumps {previous.difficulty} -> {stage.difficulty} at stage {stage.id}`
            )
        end
    end

    return #errors == 0, errors
end

return StageDefinitions
