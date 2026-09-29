--[[
    LevelBuilder (development utility)
    Generates placeholder geometry for every stage so the game is playable from a
    headless build, before any hand-authored art exists.

    Set Config.GeneratePlaceholderLevels = true to use it. In production this
    stays off and level geometry is authored by hand in Studio under
    Workspace.Level, with checkpoint parts tagged "ObbyCheckpoint" and each
    stage Model named `Stage_<id>` containing `StartPad` and `EndPad`.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Presentation = require(Shared.Presentation)
local StageDefinitions = require(Shared.StageDefinitions)

local LevelBuilder = {}

local STAGE_LENGTH = 140     -- studs between stage start and end
local WORLD_HEIGHT = 60      -- vertical gap between worlds

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.Color = color
    part.Material = material
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

local function buildStage(stage, worldIndex: number, localIndex: number): Model
    local palette = Presentation.Palette[stage.world]
    local baseColor = palette[1]
    local accent = palette[2]

    local model = Instance.new("Model")
    model.Name = stage.geometryName

    local origin = Vector3.new(
        (worldIndex - 1) * 400,
        (worldIndex - 1) * WORLD_HEIGHT,
        (localIndex - 1) * STAGE_LENGTH
    )

    local startPad = makePart(
        "StartPad",
        Vector3.new(14, 1, 14),
        CFrame.new(origin),
        Presentation.CheckpointColor,
        Enum.Material.SmoothPlastic
    )
    startPad.Parent = model

    -- Difficulty drives gap count and spacing, so harder stages feel longer.
    local gapCount = 3 + stage.difficulty * 2
    local spacing = STAGE_LENGTH / (gapCount + 1)
    local previousPosition = origin

    for i = 1, gapCount do
        local position = origin + Vector3.new(0, 0, spacing * i)
        local width = math.max(6, 16 - stage.difficulty * 1.5)
        local platform = makePart(
            `Platform_{i}`,
            Vector3.new(width, 1, width),
            CFrame.new(position),
            i % 2 == 0 and accent or baseColor,
            Enum.Material.SmoothPlastic
        )
        platform.Parent = model

        -- Place a checkpoint part on roughly every checkpointCount-th platform.
        if stage.checkpointCount > 0 and i % math.max(1, math.floor(gapCount / stage.checkpointCount)) == 0 then
            local checkpoint = makePart(
                `Checkpoint_{i}`,
                Vector3.new(width, 1, width),
                CFrame.new(position + Vector3.new(0, 0.6, 0)),
                Presentation.CheckpointColor,
                Enum.Material.Neon
            )
            checkpoint.CanCollide = false
            checkpoint:SetAttribute("StageId", stage.id)
            checkpoint:SetAttribute("CheckpointIndex", i)
            checkpoint.Parent = model
            CollectionService:AddTag(checkpoint, "ObbyCheckpoint")
        end

        previousPosition = position
    end

    local endPad = makePart(
        "EndPad",
        Vector3.new(16, 1, 16),
        CFrame.new(previousPosition + Vector3.new(0, 0, spacing)),
        Presentation.EndPadColor,
        Enum.Material.Neon
    )
    endPad.Parent = model

    return model
end

--[[ Creates geometry for any stage that doesn't already have a Model. ]]
function LevelBuilder.build()
    local level = workspace:FindFirstChild("Level")
    if not level then
        level = Instance.new("Folder")
        level.Name = "Level"
        level.Parent = workspace
    end

    local built = 0
    for _, world in ipairs(Config.Worlds) do
        local worldIndex = 0
        for index, candidate in ipairs(Config.Worlds) do
            if candidate.name == world.name then
                worldIndex = index
            end
        end

        for localIndex = 1, 15 do
            local stageId = (worldIndex - 1) * 15 + localIndex
            local stage = StageDefinitions.get(stageId)
            if stage and not level:FindFirstChild(stage.geometryName) then
                buildStage(stage, worldIndex, localIndex).Parent = level
                built += 1
            end
        end
    end

    print(`[LevelBuilder] generated {built} placeholder stages`)
end

return LevelBuilder
