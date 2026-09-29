--[[
    Stage catalogue tests.

    Pure Luau — no Roblox instance APIs — so this runs under Lune outside Studio.
    Run with: lune run tests/StageDefinitions.spec.luau
]]

local StageDefinitions = require("../src/shared/StageDefinitions")
local Config = require("../src/shared/Config")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
    if condition then
        print(`  ok   {name}`)
    else
        failures += 1
        print(`  FAIL {name}{detail and ` — {detail}` or ""}`)
    end
end

StageDefinitions.init(Config)

print("StageDefinitions")

local ok, errors = StageDefinitions.validate()
check("catalogue validates against design rules", ok)
if not ok then
    for _, message in ipairs(errors) do
        print(`       {message}`)
    end
end

check(
    "builds exactly Config.TotalStages",
    StageDefinitions.count() == Config.TotalStages,
    `got {StageDefinitions.count()}, want {Config.TotalStages}`
)

check("ids are contiguous from 1", (function()
    for index = 1, StageDefinitions.count() do
        local stage = StageDefinitions.get(index)
        if not stage or stage.id ~= index then
            return false
        end
    end
    return true
end)())

check("difficulty never rises by more than 1", (function()
    local previous = nil
    for _, stage in ipairs(StageDefinitions.Stages) do
        if previous and stage.difficulty - previous > 1 then
            return false
        end
        previous = stage.difficulty
    end
    return true
end)())

check("difficulty stays within 1..5", (function()
    for _, stage in ipairs(StageDefinitions.Stages) do
        if stage.difficulty < 1 or stage.difficulty > 5 then
            return false
        end
    end
    return true
end)())

check("every 5th stage in a world is a breather", (function()
    for _, stage in ipairs(StageDefinitions.Stages) do
        local localIndex = ((stage.id - 1) % 15) + 1
        if (localIndex % 5 == 0) ~= stage.isBreather then
            return false
        end
    end
    return true
end)())

check("harder stages get more checkpoints", (function()
    for _, stage in ipairs(StageDefinitions.Stages) do
        local expected
        if stage.difficulty <= 2 then
            expected = 1
        elseif stage.difficulty == 3 then
            expected = 2
        elseif stage.difficulty == 4 then
            expected = 3
        else
            expected = 4
        end
        if stage.checkpointCount ~= expected then
            return false
        end
    end
    return true
end)())

check("geometry names match the stage id", (function()
    for _, stage in ipairs(StageDefinitions.Stages) do
        if stage.geometryName ~= `Stage_{stage.id}` then
            return false
        end
    end
    return true
end)())

check("every stage names at least one mechanic", (function()
    for _, stage in ipairs(StageDefinitions.Stages) do
        if #stage.mechanics == 0 then
            return false
        end
    end
    return true
end)())

check("build() is pure — two calls agree", (function()
    local a = StageDefinitions.build(Config)
    local b = StageDefinitions.build(Config)
    if #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index].difficulty ~= b[index].difficulty then
            return false
        end
    end
    return true
end)())

check("get() returns nil for out-of-range ids", StageDefinitions.get(0) == nil and StageDefinitions.get(999) == nil)

print("")
if failures == 0 then
    print("all tests passed")
else
    print(`{failures} test(s) failed`)
    process.exit(1)
end
