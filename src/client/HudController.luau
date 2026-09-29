--[[
    HudController
    Builds the on-screen HUD entirely in code (no .rbxmx UI to keep in sync) and
    mirrors server state. The client never decides progression; it only renders
    what the server told it and asks permission to advance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudController = {}

local state = {
    stage = 1,
    total = 60,
    startedAt = nil,
    deaths = 0,
}

local labels: { [string]: TextLabel } = {}
local skipButton: TextButton

local function makeLabel(parent: Instance, name: string, position: UDim2, size: UDim2, textSize: number): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.4
    label.TextScaled = false
    label.TextSize = textSize
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Position = position
    label.Size = size
    label.Text = ""
    label.Parent = parent
    return label
end

local function buildGui()
    local existing = playerGui:FindFirstChild("ObbyHud")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ObbyHud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    labels.stage = makeLabel(gui, "Stage", UDim2.fromScale(0.5, 0.03), UDim2.fromScale(0.4, 0.06), 28)
    labels.stage.AnchorPoint = Vector2.new(0.5, 0)
    labels.stage.Position = UDim2.fromScale(0.5, 0.02)

    labels.timer = makeLabel(gui, "Timer", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(180, 32), 24)
    labels.timer.AnchorPoint = Vector2.new(1, 0)
    labels.timer.TextXAlignment = Enum.TextXAlignment.Right

    labels.toast = makeLabel(gui, "Toast", UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.6, 0.07), 32)
    labels.toast.AnchorPoint = Vector2.new(0.5, 0)
    labels.toast.TextColor3 = Color3.fromRGB(120, 255, 160)
    labels.toast.TextTransparency = 1

    skipButton = Instance.new("TextButton")
    skipButton.Name = "SkipStage"
    skipButton.Text = "Skip Stage"
    skipButton.Font = Enum.Font.GothamBold
    skipButton.TextSize = 20
    skipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    skipButton.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
    skipButton.AnchorPoint = Vector2.new(1, 1)
    skipButton.Position = UDim2.new(1, -24, 1, -24)
    skipButton.Size = UDim2.fromOffset(160, 56)
    skipButton.Visible = false
    skipButton.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = skipButton

    skipButton.Activated:Connect(function()
        local ok, reason = Net.get("SkipStage"):InvokeServer()
        if not ok then
            labels.toast.Text = `Can't skip ({reason})`
            labels.toast.TextColor3 = Color3.fromRGB(255, 140, 140)
            HudController.showToast()
        end
    end)

    gui.Parent = playerGui
end

function HudController.showToast()
    local toast = labels.toast
    toast.TextTransparency = 0
    task.spawn(function()
        task.wait(1.6)
        for i = 1, 20 do
            toast.TextTransparency = i / 20
            task.wait(0.03)
        end
    end)
end

local function render()
    labels.stage.Text = `Stage {state.stage} / {state.total}`
    if state.stage > 1 then
        skipButton.Visible = true
    end
end

local function tick()
    while true do
        if state.startedAt then
            local elapsed = os.clock() - state.startedAt
            labels.timer.Text = string.format("%d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60))
        end
        task.wait(0.1)
    end
end

function HudController.init()
    buildGui()
    render()
    task.spawn(tick)

    Net.get("StageChanged").OnClientEvent:Connect(function(payload)
        state.stage = payload.stage
        state.total = payload.total
        state.startedAt = payload.startedAt
        state.deaths = payload.deaths
        render()
    end)

    Net.get("StageCompleted").OnClientEvent:Connect(function(payload)
        labels.toast.TextColor3 = Color3.fromRGB(120, 255, 160)
        labels.toast.Text = `Stage {payload.stage} complete!`
        HudController.showToast()
    end)

    Net.get("RunFinished").OnClientEvent:Connect(function(payload)
        labels.toast.TextColor3 = Color3.fromRGB(255, 220, 120)
        labels.toast.Text = string.format("Finished in %d:%02d!", math.floor(payload.timeSec / 60), math.floor(payload.timeSec % 60))
        HudController.showToast()
    end)

    -- Desktop convenience: R to respawn at the last checkpoint.
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == Enum.KeyCode.R then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.Health = 0
            end
        end
    end)
end

return HudController
