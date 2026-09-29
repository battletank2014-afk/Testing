--[[
    MonetizationService
    Passes and developer products.

    Two rules that are easy to get wrong and expensive to fix:
      1. ProcessReceipt must be idempotent — Roblox retries, so check the
         PurchaseId before granting anything.
      2. Grant on the server from the receipt, never from a client signal.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)

local MonetizationService = {}

local Enum2 = Enum.ProductPurchaseDecision

--[[ Receipt ids we have already honoured, per player. ]]
local granted: { [number]: { [string]: boolean } } = {}

local function alreadyGranted(userId: number, purchaseId: string): boolean
    local perPlayer = granted[userId]
    return perPlayer ~= nil and perPlayer[purchaseId] == true
end

local function markGranted(userId: number, purchaseId: string)
    granted[userId] = granted[userId] or {}
    granted[userId][purchaseId] = true
end

--[=[ products ]=]

local function grantCheckpointSave(player: Player): boolean
    return DataService.saveNow(player)
end

local function grantTrailEffect(player: Player): boolean
    local profile = DataService.get(player)
    if not profile then
        return false
    end
    profile.trailUntil = os.time() + 3600
    return DataService.saveNow(player)
end

local PRODUCT_GRANTS: { [number]: (Player) -> boolean } = {
    [Config.DeveloperProducts.CheckpointSave] = grantCheckpointSave,
    [Config.DeveloperProducts.TrailEffect] = grantTrailEffect,
}

local function onProcessReceipt(receipt: ReceiptInfo)
    local player = game:GetService("Players"):GetPlayerByUserId(receipt.PlayerId)
    if not player then
        -- Player left mid-purchase; retry later rather than losing the sale.
        return Enum2.NotProcessedYet
    end

    if alreadyGranted(receipt.PlayerId, receipt.PurchaseId) then
        return Enum2.PurchaseGranted
    end

    local grant = PRODUCT_GRANTS[receipt.ProductId]
    if not grant then
        warn(`[Monetization] unknown product {receipt.ProductId}`)
        return Enum2.NotProcessedYet
    end

    if not grant(player) then
        return Enum2.NotProcessedYet
    end

    markGranted(receipt.PlayerId, receipt.PurchaseId)
    return Enum2.PurchaseGranted
end

--[=[ passes ]=]

function MonetizationService.ownsPass(player: Player, passId: number): boolean
    if passId == 0 then
        return false
    end
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
    end)
    return ok and owns == true
end

--[[ Consumes one skip for a pass holder. Returns (ok, reason). ]]
function MonetizationService.skipStage(player: Player): (boolean, string?)
    if not MonetizationService.ownsPass(player, Config.GamePasses.SkipStage) then
        return false, "no_pass"
    end

    local run = StageService.getRun(player)
    if not run then
        return false, "no_run"
    end

    return StageService.advance(player, "skipped")
end

function MonetizationService.init()
    MarketplaceService.ProcessReceipt = onProcessReceipt
    Net.get("SkipStage").OnServerInvoke = function(player: Player)
        return MonetizationService.skipStage(player)
    end
end

return MonetizationService
